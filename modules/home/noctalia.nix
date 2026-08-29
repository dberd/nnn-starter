{
  lib,
  pkgs,
  inputs,
  username,
  local,
  ...
}: let
  # One picture for every output. Pinning each monitor rather than relying on
  # `wallpaper.default` matters because the palette is derived from the image:
  # two different images would mean two screens disagreeing about the theme.
  # This has to stay the same file as stylix.image in modules/nixos/stylix.nix.
  wallpaperPath = "/home/${username}/Pictures/wallpapers/wallhaven-1pw769_2560x1440.png";

  # Lock-screen login box, one per output — a box only appears on the screen it
  # was placed on, so a host with two panels needs two or waking on the second
  # one gives a lock screen with nowhere to type.
  #
  # Noctalia records positions in OUTPUT-LOCAL LOGICAL pixels, i.e. the mode
  # divided by the scale, and rescales them if the output later differs from
  # what was recorded. That makes them derivable instead of something to drag
  # around in the editor, which is what they used to be: the two hand-placed
  # boxes sat at 90.1% and 89.0% of their panel's height — a difference nobody
  # chose — so both are now simply centred horizontally and put at 90%. On the
  # 1080p panel that moves the box 11 logical pixels down from where it was.
  logical = m: {
    w = m.mode.width / m.scale;
    h = m.mode.height / m.scale;
  };

  loginBox = name: let
    l = logical local.monitors.${name};
  in {
    type = "login_box";
    output = name;
    cx = l.w / 2;
    cy = l.h * 0.9;
    box_width = 720.0;
    box_height = 196.0;
    placement_width = l.w;
    placement_height = l.h;
    rotation = 0.0;
    settings = {
      layout = "regular";
      background_color = "surface_variant";
      background_opacity = 0.88;
      background_radius = 12.0;
      input_opacity = 1.0;
      input_radius = 6.0;
      center_password_text = false;
      show_caps_lock = true;
      show_keyboard_layout = true;
      show_login_button = true;
      show_media = true;
      show_session_buttons = true;
      show_unlock_hint = true;
      show_weather = true;
    };
  };

  outputs = builtins.attrNames local.monitors;
  boxId = name: "lockscreen-login-box@${name}";
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
        default.path = wallpaperPath;

        # Cross-fade the wallpaper in at shell start instead of having it snap
        # onto the black background.
        transition_on_startup = true;

        # `default` is only the fallback for an output with no entry here, so
        # every output this host declares gets pinned explicitly — see the
        # `wallpaperPath` binding at the top for why they all get the same file.
        monitors = lib.genAttrs outputs (_: {path = wallpaperPath;});

        # The star in the wallpaper panel. Each entry remembers the theme that
        # was in use when it was starred, so picking it again restores the whole
        # look and not just the image. Replaced wholesale like every other list,
        # so a star added in the GUI has to be brought back here.
        favorite = [
          {
            path = "/home/${username}/Pictures/wallpapers/kanagawa-wave.png";
            palette_source = "wallpaper";
            theme_mode = "dark";
            wallpaper_scheme = "m3-content";
          }
        ];
      };

      # Palette generated from the wallpaper, the same model DankMaterialShell
      # used. Pinned here (rather than left to the control center) so the second
      # host reproduces it.
      #
      # This has to agree with stylix.image in modules/nixos/stylix.nix, which
      # derives its own palette from the same file — otherwise Noctalia's
      # surfaces and everything Stylix paints come from two different pictures.
      #
      # Changing it in the control center writes ~/.local/state/noctalia/settings.toml
      # instead, and that file wins over this one at runtime. To bring a change
      # made in the GUI back here, read it out of `noctalia config export merged`.
      theme = {
        source = "wallpaper";
        mode = "dark";
        wallpaper_scheme = "m3-tonal-spot";

        # Picked while browsing palettes in the control center. Both are inert
        # while `source` stays "wallpaper": they are read only when source is
        # "builtin" or "community" respectively. Recorded so the picks survive,
        # and so trying either is a one-word change to `source` above.
        builtin = "Dracula";
        community_palette = "One";
      };

      location.address = "Moscow, Russia";

      # This desktop has no backlight device, so brightness has to go over
      # DDC/CI to the monitors themselves. Noctalia supports it but ships the
      # switch off, which is why it reported "brightness control unavailable"
      # even once ddcutil and hardware.i2c were in place.
      brightness.enable_ddcutil = true;

      # Push palette / wallpaper / theme mode to the login screen whenever they
      # change, so the greeter matches the desktop instead of drifting away from
      # it. Sync writes /var/lib/noctalia-greeter/sync.toml; the declarative
      # greeter.toml (hosts/nnn-desktop/default.nix) is never touched by it and
      # still wins for the keys it sets.
      #
      # privilege_command pins the escalation to pkexec. Left unset the shell
      # prefers run0, whose polkit action is systemd1.manage-units — "run
      # anything as root" — and that is not something to hand out without a
      # password. pkexec's action is per-binary, which is what the rule in
      # modules/nixos/noctalia.nix grants.
      shell.greeter_sync = {
        auto_sync = true;
        privilege_command = "pkexec";
      };

      # Apps launched from the launcher otherwise live inside Noctalia's own
      # cgroup, so restarting the shell takes them down with it — which is how
      # a `systemctl --user restart noctalia` managed to kill VSCodium. As
      # transient units they outlive the shell.
      shell.launch_apps_as_systemd_services = true;

      # Control centre tiles are replaced wholesale like the widget lists, so
      # the six defaults are restated here.
      control_center.shortcuts = [
        {type = "wifi";}
        {type = "bluetooth";}
        {type = "caffeine";}
        {type = "nightlight";}
        {type = "notification";}
        {type = "power_profile";}
      ];

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

        # Capsule groups. A group is its own little pill in the bar: the widgets
        # named in `members` are drawn together on one `fill` backing, and the
        # group is then placed in start/center/end by its id as "group:<id>".
        # Members are NOT also listed in start/end — a widget belongs either to
        # a group or to the bar directly, never both.
        #
        # `fill = "surface_variant"` is the palette's raised surface, so the
        # pills read as slightly lifted out of the bar rather than boxed in by a
        # border. `accordion` would collapse a group down to one icon until it
        # is hovered; left off, since these three are all things to be read at a
        # glance, not opened.
        capsule_group = [
          {
            id = "g1";
            members = ["cpu" "ram"];
            enabled = true;
            fill = "surface_variant";
            opacity = 1.0;
            padding = 6.0;
            accordion = false;
            accordion_direction = "end";
          }
          {
            id = "g2";
            members = ["wallpaper" "wallhaven"];
            enabled = true;
            fill = "surface_variant";
            opacity = 1.0;
            padding = 6.0;
            accordion = false;
            accordion_direction = "end";
          }
          {
            id = "g3";
            members = ["volume" "brightness"];
            enabled = true;
            fill = "surface_variant";
            opacity = 1.0;
            padding = 6.0;
            accordion = false;
            accordion_direction = "end";
          }
        ];

        # Widget lists are replaced wholesale, not merged, so all three sections
        # are restated in full even where they match the default. Note the
        # underscores: some ids are hyphenated and some are not.
        #
        # Left: the two wallpaper controls (g2) and the machine's vitals (g1)
        # sit between the workspaces and the window title, so the whole "what is
        # running and what is it costing" story stays in one place. active_window
        # goes last because it is the one item with no fixed width — anything
        # after it would shift around as the title changes.
        start = [
          "launcher"
          "workspaces"
          "group:g2"
          "group:g1"
          "active_window"
        ];

        center = ["clock"];

        # `clipboard` is deliberately absent: the icon is gone from the bar, but
        # nothing about the clipboard itself changes — the history service is
        # separate, and Mod+V still opens the panel (see modules/home/niri.nix).
        #
        # `notes` and `wallhaven` come from plugins (see `plugins.enabled`
        # below); their widget definitions are in `widget` further down.
        end = [
          "media"
          "tray"
          "keyboard_layout"
          "notes"
          "network"
          "bluetooth"
          "group:g3"
          "battery"
          "notifications"
          "control-center"
          "session"
        ];
      };

      # Per-widget settings. A "widget" id is an instance, not a type — several
      # ids can share one `type` and differ only in their options, which is how
      # the stock `cpu` and `ram` are both `type = "sysmon"`.
      #
      # Swap and GPU tiles were both tried here and dropped: four numbers in a
      # row cost more bar width than they were worth. If either comes back, the
      # sysmon stats are cpu_usage, cpu_temp, ram_pct, swap_pct, gpu_usage,
      # gpu_temp, gpu_vram_used, disk_used, disk_free, disk_used_pct,
      # disk_free_pct, net_rx, net_tx — read out of the shell binary, since the
      # schema does not enumerate them.
      widget = {
        # Trimmed from the default 260. The widget always prints the full window
        # title and has no "app name only" mode: it renders the toplevel's title
        # and falls back to the app id only when that title is empty. Narrowing
        # it is therefore the only lever — and it has to stay generous, because
        # the text is elided from the END, which is exactly where most apps put
        # their own name ("file.md — VSCodium").
        active_window.max_length = 240.0;

        # Hide the player outright when nothing is playing, instead of parking a
        # permanent "Nothing Playing" label in the bar.
        #
        # Note this key is absent from `noctalia config export full` — that dump
        # skips booleans still sitting at their default. It is real: the shell
        # binary carries the string and `noctalia config validate` accepts it
        # without the "unknown setting" warning it raises for typos.
        media.hide_when_no_media = true;

        # Percentage rather than the default "ram_used", which prints a figure
        # in GiB. Next to cpu_usage in the same capsule, two percentages line up
        # and stay the same width; a GiB figure does neither.
        ram.stat = "ram_pct";

        # Plugin-provided widgets. The `type` is "<plugin>:<widget>", and the
        # plugin has to be in `plugins.enabled` below or the id resolves to
        # nothing and the slot in the bar is silently dropped.
        notes.type = "noctalia/notes:notes";
        wallhaven = {
          type = "noctalia/wallhaven:wallhaven";
          # Default glyph is the generic plugin puzzle piece, which says nothing
          # about what the button does.
          glyph = "photo-search";
        };
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

      # Noctalia can theme external apps from the active palette, which is what
      # makes them follow a theme switch at runtime — something Stylix cannot do,
      # since it writes into the store at build time. Each id here has its Stylix
      # target switched off in the matching home module, so exactly one of the two
      # owns each file: ghostty in ./ghostty.nix, gtk3/gtk4 in ./gtk.nix.
      #
      # Only these three. The rest of the catalogue is either irrelevant or worse
      # than what we have:
      #   qt      — the template has no post_hook, so it writes
      #             qt{5,6}ct/colors/noctalia.conf and nothing ever selects it;
      #             and our Qt style is Kvantum, which paints from its own theme
      #             and ignores the qtct palette anyway. Stylix keeps Qt.
      #   btop,   — their apply.sh writes *through* the config symlink
      #   starship  (`cat "$tmp" > "$file"`), which lands in read-only
      #             /nix/store and fails. Only the GTK template handles that case
      #             (it replaces the symlink with a real file), which is why it is
      #             the one that can be taken.
      #   niri    — needs `include "noctalia.kdl"`, a directive niri-stable 25.08
      #             does not have. See the focus-ring note in ./niri.nix.
      theme.templates.builtin_ids = ["ghostty" "gtk3" "gtk4"];

      # Lock on idle. Noctalia has this built in — it was simply disabled, so no
      # systemd unit is needed for it.
      idle.behavior.lock = {
        enabled = true;
        timeout = 600;
      };

      # Plugins. This list only says which ones are *on* — the code itself is
      # git-cloned by Noctalia's own plugin manager into
      # ~/.local/state/noctalia/plugins, outside Nix's hands. So on a fresh
      # machine the shell has to fetch them once before `notes` and `wallhaven`
      # resolve to anything; bitwarden has no bar widget and shows up as a
      # launcher provider instead.
      plugins.enabled = [
        "noctalia/wallhaven"
        "noctalia/notes"
        "noctalia/bitwarden"
      ];

      # Panels (launcher, clipboard, control center, session, wallpaper, polkit).
      #
      # "attached" hangs the panel off the bar under the widget that opened it,
      # instead of "floating" it in the middle of the screen; open_near_click
      # then puts it under the pointer rather than centred on the bar item, which
      # matters on a 2560px-wide monitor where the two can be half a screen
      # apart. `floating_layer = "top"` drops the still-floating panels out of
      # the overlay layer so they sit under, not over, the lock screen.
      shell.panel = {
        launcher_placement = "attached";
        clipboard_placement = "attached";
        polkit_placement = "attached";
        floating_layer = "top";
        open_near_click_launcher = true;
        open_near_click_clipboard = true;
        open_near_click_control_center = true;
        open_near_click_session = true;
        open_near_click_wallpaper = true;
      };

      # Show the public IP in the network panel. Costs a lookup against an
      # external service whenever the panel opens — which is also what makes it
      # a usable "is the VPN actually up?" check (see ~/vpn-check.sh).
      shell.external_ip_enabled = true;

      # In niri's overview, typing goes straight into Noctalia's launcher rather
      # than being swallowed. Makes the overview a search-and-launch surface
      # instead of a picker you have to leave before launching anything.
      shell.niri_overview_type_to_launch_enabled = true;

      # UI sounds (volume steps, notifications, screenshots). Off by default.
      audio.enable_sounds = true;

      # Notification history keeps 4 hours. The default is 0 — unlimited, not
      # none — so the list grew forever.
      notification.history_retention_hours = 4;

      # Drop the events card from the calendar tab: there is no calendar source
      # wired up, so it only ever rendered an empty box.
      control_center.calendar.show_events_card = false;

      # Hot corner: throw the pointer into the top-left to open the launcher.
      #
      # NOTE this is dormant — `hot_corners.enabled` is still at its default
      # `false`, so no corner is armed and the action never fires. Set
      # `hot_corners.enabled = true;` to turn the feature on.
      hot_corners.top_left.action = "launcher";

      # Dock. Also dormant: `dock.enabled` is at its default `false`, so nothing
      # is drawn and neither key has any effect yet. Kept because they are the
      # two that decide whether a dock is bearable — never steal screen space
      # from windows, and only hide when a window would actually overlap it.
      dock = {
        reserve_space = false;
        smart_auto_hide = true;
      };

      # Lock screen widgets, one login box per output. Both the set of boxes and
      # their placement are derived from local.monitors — see the `loginBox`
      # binding at the top of this file for the arithmetic and for why it is
      # arithmetic rather than numbers dragged around in the editor.
      #
      # NOTE dormant: `lockscreen_widgets.enabled` is at its default `false`, so
      # the lock screen still draws its own built-in login box and these are not
      # used. Set `lockscreen_widgets.enabled = true;` to switch over.
      lockscreen_widgets = {
        widget_order = map boxId outputs;
        widget = lib.listToAttrs (map (name: lib.nameValuePair (boxId name) (loginBox name)) outputs);
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
