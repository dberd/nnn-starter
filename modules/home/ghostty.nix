{...}: {
  # Stylix themes the terminal. Handing this to Noctalia was tried and reverted:
  # it does not template ghostty, so the config came out with neither colours nor
  # font — the exact failure the previous comment here warned about.
  #
  # The consequence stands: Stylix writes this theme into the nix store, so the
  # terminal cannot follow a runtime theme switch in Noctalia. Since the Stylix
  # palette is now derived from the same wallpaper Noctalia generates from, the
  # two agree — they just re-derive at different times (build vs runtime).
  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;

    # Font + colors are supplied by Stylix; these are the ergonomic extras.
    settings = {
      window-padding-x = 12;
      window-padding-y = 12;
      window-decoration = false;
      cursor-style = "block";
      cursor-style-blink = false;
      mouse-hide-while-typing = true;
      copy-on-select = "clipboard";
      confirm-close-surface = false;
      window-inherit-working-directory = true;
      # Background opacity is managed by Stylix (stylix.opacity.terminal).
    };
  };
}
