{
  lib,
  pkgs,
  ...
}: {
  # Same call as stylix.targets.starship in ./starship.nix, for the same reason.
  # Stylix's fish target sources a generated base16-stylix.fish that runs
  # `set -U fish_color_*` with wallpaper-derived hex — fish_color_param 98bed6,
  # fish_color_comment 6fa6b7, a 41708a selection background. Literal colours
  # override whatever palette the terminal has, so the shell comes out blue in
  # VSCodium's stock dark theme while looking fine in ghostty, which is themed
  # from the same wallpaper.
  #
  # Off, fish falls back to its built-in defaults, which are ANSI names the
  # terminal resolves for itself.
  stylix.targets.fish.enable = false;

  # `set -U` writes to ~/.config/fish/fish_variables, fish's own persistent
  # state, which home-manager does not own — so switching the targets off does
  # not undo what earlier generations wrote, and the console would stay blue.
  #
  # Unconditional and idempotent rather than a one-shot: a stamp file was the
  # first attempt and it failed exactly the way stamps do — the erase ran, the
  # NixOS half of the target immediately put the values back at the next
  # interactive shell, and the stamp meant the cleanup never got a second try.
  #
  # The trade-off, stated plainly: this config takes the position that fish
  # colours belong to the terminal's palette, so ANY fish_color_* left in
  # universal scope is state it wants gone. Pick colours in the terminal theme,
  # not with `fish_config` — a theme chosen there would be wiped on the next
  # rebuild.
  home.activation.fishColorsReset = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.fish}/bin/fish -c '
      for v in (set -nU)
        if string match -qr "^fish_(pager_)?color_" -- $v
          set -eU $v
        end
      end
    '
  '';

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
