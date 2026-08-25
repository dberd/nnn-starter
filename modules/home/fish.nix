{
  lib,
  pkgs,
  ...
}: {
  # `nix-shell` / `nix-shell -p` hardcode bash. any-nix-shell re-execs fish
  # inside the ad-hoc environment so we keep our shell, aliases, and prompt.
  home.packages = [pkgs.any-nix-shell];

  # Everything upstream's zsh module had to bolt on with plugins — command
  # autosuggestions, syntax highlighting, shared/deduped history, word-wise
  # Ctrl+arrow movement — fish does natively, so there is nothing to enable.
  programs.fish = {
    enable = true;

    # Modern-unix muscle memory: keep the old names, get the new tools.
    # The lsd module also defines ls/ll/la, so force ours to win the merge.
    shellAliases = {
      ls = lib.mkForce "lsd";
      ll = lib.mkForce "lsd -l";
      la = lib.mkForce "lsd -la";
      lt = lib.mkForce "lsd --tree";
      cat = "bat";
      top = "btop";
      du = "dust";
      df = "duf";
      ps = "procs";
      ping = "gping";
      vim = "nvim";
      vi = "nvim";
      g = "git";
      lg = "lazygit";

      # nh-powered rebuilds from anywhere.
      rebuild = "nh os switch";
      update = "nh os switch --update";
    };

    # Runs for EVERY fish, not just interactive ones: the VSCodium build and
    # watch tasks spawn fish non-interactively, and without this they would see
    # the default Node instead of the version the project's .nvmrc asks for.
    # `--use-on-cd` switches on entering a directory that has one; both Angular
    # frontends pin 16 that way (modules/home/dev.nix explains why 16).
    shellInit = ''
      ${pkgs.fnm}/bin/fnm env --use-on-cd --shell fish | source
    '';

    interactiveShellInit = ''
      # Keep fish inside `nix-shell` instead of falling back to bash.
      ${pkgs.any-nix-shell}/bin/any-nix-shell fish | source
    '';
  };
}
