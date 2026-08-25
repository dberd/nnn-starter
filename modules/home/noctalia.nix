{
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
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
        default.path = "/home/${username}/Pictures/wallpapers/wallhaven-1pw769_2560x1440.png";
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

        # Widget lists are replaced wholesale, not merged, so all three sections
        # are restated in full even where they match the default. Note the
        # underscores: some ids are hyphenated and some are not.
        #
        # Left: the focused window's title, then the machine's vitals. Grouping
        # them here rather than at the right end keeps the whole "what is running
        # and what is it costing" story in one place, next to the workspaces.
        start = [
          "launcher"
          "wallpaper"
          "workspaces"
          "active_window"
          "cpu"
          "ram"
        ];

        center = ["clock"];

        # `clipboard` is deliberately absent: the icon is gone from the bar, but
        # nothing about the clipboard itself changes — the history service is
        # separate, and Mod+V still opens the panel (see modules/home/niri.nix).
        end = [
          "media"
          "tray"
          "notifications"
          "keyboard_layout"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "battery"
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
