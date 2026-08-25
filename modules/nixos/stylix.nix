{pkgs, ...}: {
  # One palette to rule them all. Stylix derives colors for niri, noctalia,
  # ghostty, bat, btop, neovim, GTK/Qt and more from a single base16 scheme.
  stylix = {
    enable = true;
    polarity = "dark";

    # No base16Scheme on purpose: with it unset Stylix derives the palette from
    # `image` below, so its colours agree with the ones Noctalia generates from
    # the same wallpaper (see modules/home/noctalia.nix). The vendored
    # themes/kanagawa.yaml stays in the repo as a fallback — set
    #   base16Scheme = ../../themes/kanagawa.yaml;
    # to go back to a fixed palette.
    #
    # Caveat worth knowing: Stylix computes this at BUILD time while Noctalia
    # recomputes at runtime. Swap the wallpaper live and Noctalia follows
    # immediately, but Stylix-themed apps (GTK, Qt, neovim) only catch up
    # on the next `nixos-rebuild switch`.
    # Keep this the same file as wallpaper.default.path in
    # modules/home/noctalia.nix — both derive a palette from it, and pointing
    # them at different pictures is how the desktop ends up in two colour
    # schemes at once.
    image = ../../themes/wallpapers/wallhaven-1pw769_2560x1440.png;

    # A hint of terminal transparency for that layered desktop look.
    opacity.terminal = 0.95;

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    fonts = {
      # If column alignment ever looks off in ghostty/btop, switch the name to
      # "JetBrainsMono Nerd Font Mono" (the strictly monospaced variant).
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };

      sizes = {
        terminal = 12;
        applications = 11;
        desktop = 11;
        popups = 11;
      };
    };
  };
}
