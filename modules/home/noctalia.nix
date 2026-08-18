{
  pkgs,
  inputs,
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

    # Remaining settings are pinned from a live session: configure them in the
    # control center (Mod+Space → settings), then copy the resulting keys out of
    # ~/.config/quickshell/noctalia/settings.json into `settings` here. Still to
    # pin: weather location (Moscow), clock format, idle/lock timeouts, and the
    # colour-generation options (generationMethod = "tonal-spot",
    # monitorForColors) that make the palette follow the wallpaper.
  };

  # Noctalia draws the wallpaper — Stylix only reads the image to derive its own
  # palette, it never puts anything on screen. Noctalia wants a *directory*, and
  # a nix store path is read-only and changes on every rebuild, so the wallpapers
  # are materialised into the home directory instead.
  home.file."Pictures/wallpapers".source = ../../themes/wallpapers;
}
