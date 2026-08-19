{...}: {
  # Colour comes from Noctalia, not Stylix: it templates ghostty from the live
  # palette (see theme.templates in modules/home/noctalia.nix), so the terminal
  # follows a theme switch at runtime. Stylix writes into the store at build
  # time and cannot.
  #
  # Noctalia's apply.sh wants to append `theme = noctalia` to this config, but
  # the file is a store symlink it cannot edit — so the line is set here and the
  # script finds it already correct.
  stylix.targets.ghostty.enable = false;

  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;

    # Font still comes from Stylix; colour comes from Noctalia's template.
    settings = {
      # Set by us now that Stylix no longer writes this file.
      theme = "noctalia";
      # Fully opaque: the 0.95 Stylix used made the desktop show through, which
      # read as the terminal blurring when it lost focus.
      background-opacity = 1.0;

      window-padding-x = 12;
      window-padding-y = 12;
      window-decoration = false;
      cursor-style = "block";
      cursor-style-blink = false;
      mouse-hide-while-typing = true;
      copy-on-select = "clipboard";
      confirm-close-surface = false;
      window-inherit-working-directory = true;
    };
  };
}
