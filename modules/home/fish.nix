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

    interactiveShellInit = ''
      # Keep fish inside `nix-shell` instead of falling back to bash.
      ${pkgs.any-nix-shell}/bin/any-nix-shell fish | source
    '';

    # sing-box's Clash API on 127.0.0.1:9091 (modules/nixos/singbox.nix) — the
    # same control surface the bar widget drives, reachable directly and
    # without it. See docs/proxy.md, section 2.
    functions = {
      proxy-node = {
        description = "Switch the sing-box proxy node (vavn-lv / vavn-fr-hy2 / direct)";
        body = ''
          curl -s -X PUT http://127.0.0.1:9091/proxies/proxy \
              -d (printf '{"name":"%s"}' $argv[1]) >/dev/null
        '';
      };
      proxy-mode = {
        description = "Switch the sing-box routing mode (Rule / Global / Direct)";
        body = ''
          curl -s -X PATCH http://127.0.0.1:9091/configs \
              -d (printf '{"mode":"%s"}' $argv[1]) >/dev/null
        '';
      };
      proxy-status = {
        description = "Show the current sing-box proxy node and available nodes";
        body = ''
          curl -s http://127.0.0.1:9091/proxies/proxy | jq '{now, all}'
        '';
      };
    };
  };
}
