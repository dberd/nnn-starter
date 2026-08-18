{
  pkgs,
  local,
  ...
}: {
  programs.git = {
    enable = true;

    # Build git with the libsecret credential helper so passwords land in
    # gnome-keyring (services.gnome.gnome-keyring.enable, modules/nixos/desktop.nix)
    # instead of plaintext ~/.git-credentials, which is what `helper = store`
    # did before. The override means git compiles from source rather than coming
    # from the binary cache — a couple of minutes on first build.
    package = pkgs.git.override {withLibsecret = true;};

    # Work identity, applied by path. Mirrors the previous
    # ~/.gitconfig + ~/.gitconfig-efko split; home-manager writes the included
    # file into the store for us.
    includes = [
      {
        condition = "gitdir:~/Work/Repos/";
        contents.user = {
          name = "Бердников Дмитрий Павлович";
          email = "d.berdnikov@efko.ru";
        };
      }
    ];

    settings = {
      # ⇩ Personal identity comes from local.nix; work identity above.
      user.name = local.gitUserName;
      user.email = local.gitUserEmail;

      # git resolves this to git-credential-libsecret from git's own libexec.
      credential.helper = "libsecret";

      # Corporate GitLab is reachable over https only; rewrite the ssh-style
      # remotes that exist in older clones.
      url."https://gitlab.sddt.efko.ru/".insteadOf = "git@git.sddt.efko.ru:";

      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      merge.conflictstyle = "zdiff3";
      diff.colorMoved = "default";

      alias = {
        st = "status -sb";
        co = "checkout";
        br = "branch";
        ci = "commit";
        lg = "log --oneline --graph --decorate --all";
      };
    };
  };

  # delta gives syntax-highlighted, side-by-side diffs (themed by Stylix).
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
    };
  };

  programs.lazygit.enable = true;

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };
}
