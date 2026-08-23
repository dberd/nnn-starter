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
