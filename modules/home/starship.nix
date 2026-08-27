{...}: {
  # Stylix's starship target writes `palette = "base16"` into starship.toml,
  # which remaps every colour NAME below to a wallpaper-derived hex and makes
  # starship emit 24-bit truecolour. That bypasses the terminal palette
  # entirely: with a blue wallpaper the whole prompt comes out in four shades of
  # blue, including the `bold green` character below, and it looks wrong in any
  # terminal that is not themed from the same picture — VSCodium's integrated
  # terminal on its stock dark theme being the obvious one.
  #
  # Off, so the names below stay names and the terminal resolves them: Noctalia's
  # live palette in ghostty (see modules/home/ghostty.nix, which made the same
  # call for the same reason), the editor's own theme in VSCodium.
  stylix.targets.starship.enable = false;

  programs.starship = {
    enable = true;
    # fish ships its own prompt; starship replaces it, and unlike fish_prompt it
    # is configured declaratively here.
    enableFishIntegration = true;

    settings = {
      add_newline = true;
      command_timeout = 1000;

      # A clean two-line prompt. The style names here are ANSI names on
      # purpose — see the Stylix note at the top.
      format = "$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      directory.truncation_length = 3;
      directory.truncate_to_repo = true;

      nix_shell.symbol = " ";
      git_branch.symbol = " ";

      cmd_duration = {
        min_time = 2000;
        format = "[ $duration]($style) ";
      };
    };
  };
}
