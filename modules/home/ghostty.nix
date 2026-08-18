{...}: {
  # Colour is handed to Noctalia instead of Stylix: a Stylix-written theme lives
  # in the nix store, so it can never follow a runtime theme switch in the shell.
  # (This target is home-manager-level — ghostty is an HM program, so it does not
  # exist under the NixOS stylix module.)
  #
  # Revert this if Noctalia turns out not to template ghostty, otherwise the
  # terminal ends up with no theme at all.
  stylix.targets.ghostty.enable = false;

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
