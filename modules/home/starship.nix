{...}: {
  programs.starship = {
    enable = true;
    # fish ships its own prompt, but Stylix doesn't theme it — starship is
    # already wired into the Kanagawa palette, so it stays as the prompt.
    enableFishIntegration = true;

    settings = {
      add_newline = true;
      command_timeout = 1000;

      # A clean two-line prompt; colors come from Stylix.
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
