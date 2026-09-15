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

  # lazygit as a raw package, and deliberately NOT programs.lazygit.
  #
  # Colour comes from Noctalia's template (see theme.templates in
  # ./noctalia.nix) so it follows a palette switch at runtime. That template's
  # hook splices a theme block into ~/.config/lazygit/config.yml, and turning
  # the Stylix target off is not enough to free that path the way it is for bat
  # and btop: home-manager's lazygit module writes config.yml unconditionally,
  # settings or no settings, so the file would stay a read-only store symlink
  # and the hook would abort on it.
  #
  # Nothing is lost by dropping the module — it only ever set `enable` here, and
  # lazygit runs fine with no config at all until the hook writes one.
  stylix.targets.lazygit.enable = false;

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  home.packages = [pkgs.lazygit];
}
