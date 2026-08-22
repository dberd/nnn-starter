{
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  # The pinned community plugin tree with two defects taken out of
  # mihomo-control, both of which stop its `service` entry from running — and
  # that entry is the one that owns every HTTP request the plugin makes. The bar
  # widget and the panel load either way, which is what makes the failure
  # confusing: the plugin is visibly there and simply never shows a number.
  #
  # 1. Two `check(...)` calls in the self-test block at the end of service.luau
  #    end their argument list with a trailing comma. Luau allows that in a
  #    table constructor and not in a call, so the file does not compile at all:
  #
  #      [luau] luau_load failed … service.luau:673:
  #      Expected expression after ',' but got ')' instead
  #
  #    This is not a version gap to wait out — luau 0.726, newer than anything
  #    the shell carries, rejects it just the same. The plugin's own test runner
  #    never catches it because it exercises group_logic.lua, not service.luau.
  #
  # 2. With that fixed, the service loads group_logic.lua by calling the global
  #    `load`, which does not exist here: the host sandboxes the interpreter
  #    (luaL_sandbox) and offers its own `require` instead. That require insists
  #    on a relative path ending in .luau, which is exactly why the plugin
  #    reached for `load` — its helper is named .lua so that plain-Lua unit
  #    tests can dofile() it. So the helper is copied under a second name and
  #    the loader rewritten to require it; the .lua original stays where the
  #    tests expect it.
  #
  # Both edits are anchored on content rather than line numbers, and the build
  # fails if either stops matching — a fix upstream should surface as a rebuild
  # error, not as a patch that quietly does nothing. luau-compile over every
  # entry afterwards is the proof that what ships actually parses.
  communityPlugins = pkgs.runCommand "noctalia-community-plugins-patched" {
    nativeBuildInputs = [pkgs.luau];
  } ''
    cp -r ${inputs.noctalia-community-plugins} $out
    chmod -R u+w $out
    cd $out/mihomo-control

    before=$(grep -c ',$' service.luau)
    sed -i -z 's/,\n\(\s*)\)/\n\1/g' service.luau
    [ "$(grep -c ',$' service.luau)" -lt "$before" ] \
      || { echo "trailing-comma patch matched nothing"; exit 1; }

    grep -q 'load(source, "@group_logic.lua")' service.luau \
      || { echo "group_logic loader is not what we expected"; exit 1; }
    cp group_logic.lua group_logic.luau
    cat > repl.txt <<'EOF'

    local function require_group_logic()
      if group_logic == nil then
        group_logic = require("./group_logic.luau")
      end
      return group_logic
    end
    EOF
    sed -i -e '/^local function require_group_logic()$/,/^end$/d' \
           -e '/^local group_logic$/r repl.txt' service.luau
    rm repl.txt

    for f in *.luau; do
      luau-compile --binary "$f" > /dev/null || { echo "$f does not parse"; exit 1; }
    done
  '';
in {
  # The Noctalia desktop shell: bar, launcher, notifications, control center,
  # lock screen and wallpaper, all in one.
  programs.noctalia = {
    enable = true;

    # Prebuilt package from noctalia.cachix.org (see modules/nixos/noctalia.nix).
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

    # Run as a systemd user service tied to the graphical (niri) session so it
    # starts and stops with your login.
    systemd.enable = true;

    # Written to ~/.config/noctalia/config.toml. Note there are two files:
    # this declarative one, and ~/.local/state/noctalia/settings.toml which the
    # control center writes at runtime. Keys below come from
    # `noctalia config export full`, and the module validates them at build time
    # (`noctalia config validate`), so a typo fails the build rather than
    # silently doing nothing.
    settings = {
      # This was empty, which is the whole reason there was no wallpaper — and,
      # since the lock screen draws the same wallpaper, why that was black too.
      wallpaper = {
        directory = "/home/${username}/Pictures/wallpapers";
        default.path = "/home/${username}/Pictures/wallpapers/kanagawa-wave.png";
      };

      # Palette generated from the wallpaper, the same model DankMaterialShell
      # used. Pinned here (rather than left to the control center) so the second
      # host reproduces it.
      theme = {
        source = "wallpaper";
        mode = "dark";
        wallpaper_scheme = "m3-content";
      };

      location.address = "Moscow, Russia";

      # This desktop has no backlight device, so brightness has to go over
      # DDC/CI to the monitors themselves. Noctalia supports it but ships the
      # switch off, which is why it reported "brightness control unavailable"
      # even once ddcutil and hardware.i2c were in place.
      brightness.enable_ddcutil = true;

      # Apps launched from the launcher otherwise live inside Noctalia's own
      # cgroup, so restarting the shell takes them down with it — which is how
      # a `systemctl --user restart noctalia` managed to kill VSCodium. As
      # transient units they outlive the shell.
      shell.launch_apps_as_systemd_services = true;

      # ── Proxy widget ──────────────────────────────────────────────────────
      # The bar's control surface for the sing-box in modules/nixos/singbox.nix.
      # It is `mihomo-control`, written for Mihomo (Clash Meta), and it works
      # unchanged against sing-box because both answer the same Clash external
      # controller API — the endpoints it calls were checked one by one against
      # our build before this was wired up: /proxies with the selector's `now`
      # and `all`, PUT /proxies/<group> to switch, /connections for the running
      # totals, /group/<name>/delay to time every node at once.
      #
      # It replaced a draft that pointed at ruh-vpn, whose backend is a Python
      # service of its own and whose server model has no room for Hysteria2 —
      # which is the transport of the node actually in use here.
      #
      # Declaring `source` replaces Noctalia's two built-in git sources rather
      # than adding to them, which is the point: upstream would clone the
      # community repository at whatever HEAD happened to be current, while a
      # `path` source is documented as "an immutable local directory (e.g. a Nix
      # store path) the host treats read-only" — so the plugin version is pinned
      # in flake.lock and update/auto-update become no-ops.
      plugins = {
        # Background git pulls, off. This is a `plugins`-level setting taking
        # "all"|"official"|"none" — it used to be a boolean on each source, and
        # left there it is silently ignored ("plugins.source.auto_update:
        # unknown setting" in the shell log). Our only source is a store path
        # the host treats as read-only anyway; this stops the shell from
        # reaching for the network on startup and every six hours besides.
        auto_update = "none";
        source = [
          {
            name = "community-pinned";
            kind = "path";
            location = "${communityPlugins}";
            enabled = true;
          }
        ];
        enabled = ["mdj2812/mihomo-control"];
      };

      # Control centre tiles are replaced wholesale like the widget lists, so
      # the six defaults are restated here with the proxy mode switch appended.
      control_center.shortcuts = [
        {type = "wifi";}
        {type = "bluetooth";}
        {type = "caffeine";}
        {type = "nightlight";}
        {type = "notification";}
        {type = "power_profile";}
        {type = "mdj2812/mihomo-control:mode";}
      ];

      # Per-plugin settings live at the config root, not under [plugins].
      # The port is sing-box's Clash API, deliberately not the conventional
      # 9090: Throne would take that one if its own dashboard were ever switched
      # on, and the two run side by side until Throne goes.
      plugin_settings."mdj2812/mihomo-control" = {
        host = "127.0.0.1";
        port = "9091";
        # cp.cloudflare.com rather than the gstatic default: the default is not
        # reachable from here without the proxy, which makes every latency test
        # look like a dead node.
        test_url = "http://cp.cloudflare.com/";
      };

      # Bar: `scale` is the overall size knob; padding is the vertical breathing
      # room. Capsules are how Noctalia separates sections — each group gets its
      # own backing, which reads as a divider between them.
      bar.default = {
        scale = 1.15;
        padding = 18;
        # Default leaves 180px free at each end, which is why the bar looked
        # narrow. Matching niri's layout gaps lines it up with the edges a
        # window reaches when maximised.
        margin_ends = 12;
        capsule = true;

        # Widget lists are replaced wholesale, not merged, so the default order
        # is restated here with keyboard_layout added. Note the underscore: the
        # other ids are hyphenated, this one is not. Found by feeding candidates
        # to the shell and watching which ones it did not reject — the schema
        # does not list widgets and the validator accepts any string.
        end = [
          "media"
          "tray"
          "notifications"
          "clipboard"
          "keyboard_layout"
          # Plugin widgets are addressed as "<plugin id>:<entry id>".
          "mdj2812/mihomo-control:widget"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "battery"
          "control-center"
          "session"
        ];
      };

      # Noctalia's backdrop is a tinted layer-shell surface meant to dim the
      # desktop behind its own panels. It is not what puts the wallpaper into
      # niri's overview — the niri layer-rule does that, and it moves this
      # surface into the backdrop too, where the surface can no longer dim
      # anything. All it did there was tint the overview *outside* the
      # workspace rectangles, which is exactly the translucent bordered pane
      # that showed on every workspace. Off, the surface is not created at all.
      backdrop.enabled = false;

      # On-screen display for volume, brightness, caps lock and friends.
      # Noctalia defaults to top_center, which lands right where the top of the
      # focused window is — the part of the screen you actually read. Bottom
      # centre is what GNOME and Windows 11 both settle on, and it keeps the top
      # strip free for the bar. offset_x is zeroed because with a centred anchor
      # a horizontal offset only pushes the panel off-centre; the default 20 is
      # meant for corner placements.
      osd = {
        position = "bottom_center";
        offset_x = 0;
        offset_y = 24;
      };

      # Noctalia can theme external apps from the active palette. ghostty is in
      # its catalogue; enabling it here is what makes the terminal follow a
      # theme switch at runtime, which Stylix cannot do (it writes into the
      # store at build time).
      theme.templates.builtin_ids = ["ghostty"];

      # Lock on idle. Noctalia has this built in — it was simply disabled, so no
      # systemd unit is needed for it.
      idle.behavior.lock = {
        enabled = true;
        timeout = 600;
      };

      # Deliberately not set:
      #   shell.time_format — already 24h
      #   shell.date_format — "%A, %x" takes its format from the locale, and
      #     LC_TIME=en_IE (hosts/common) already makes that dd/mm/yyyy
      #   shell.polkit_agent — leave off: niri-flake already runs one, and a
      #     second agent would just race it for the D-Bus name
    };
  };

  # Noctalia draws the wallpaper — Stylix only reads the image to derive its own
  # palette, it never puts anything on screen. Noctalia wants a *directory* to
  # browse, and you want to drop new wallpapers into it from a file manager.
  #
  # `home.file."Pictures/wallpapers".source` cannot do that: it makes the whole
  # directory one symlink into the nix store, so the folder comes out owned by
  # root and mode r-xr-xr-x — nothing can be added to it and nothing removed.
  # Instead the repo's wallpapers are seeded into a real directory as ordinary
  # writable files. `cp -n` never overwrites, so anything you put there by hand,
  # including a replacement for kanagawa-wave.png, survives every rebuild; and
  # `--no-preserve=mode` drops the store's read-only bits from the copies.
  #
  # Runs after linkGeneration so home-manager has already removed the old store
  # symlink; the guard below covers the one-time migration from it.
  home.activation.seedWallpapers = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ -L "$HOME/Pictures/wallpapers" ]; then
      run rm $VERBOSE_ARG "$HOME/Pictures/wallpapers"
    fi
    run mkdir -p $VERBOSE_ARG "$HOME/Pictures/wallpapers"
    run cp -rn --no-preserve=mode ${../../themes/wallpapers}/. "$HOME/Pictures/wallpapers/"
  '';
}
