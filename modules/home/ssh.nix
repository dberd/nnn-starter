{lib, ...}: {
  # Client config only — the keys themselves are NOT managed here. Copy
  # ~/.ssh/id_ed25519_* over by hand; they are already registered with GitHub
  # and the corporate GitLab, so don't generate new ones.
  programs.ssh = {
    enable = true;
    # We write our own `Host *` block below instead of home-manager's default one.
    enableDefaultConfig = false;

    # `settings` takes native ssh_config option names (the older camelCase
    # `matchBlocks` API is deprecated). Attribute names become `Host <name>`.
    settings = {
      "github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519_github_dberd";
        IdentitiesOnly = "yes";
        PreferredAuthentications = "publickey";
      };

      # Corporate GitLab. Note that modules/home/git.nix rewrites this host's
      # ssh URLs to https (carried over from the old ~/.gitconfig), so in
      # practice git reaches it over https and this block only applies to plain
      # `ssh`/`scp` use.
      "git.sddt.efko.ru" = {
        HostName = "git.sddt.efko.ru";
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519_gitlab_efko";
        IdentitiesOnly = "yes";
        PreferredAuthentications = "publickey";
      };

      # ssh takes the first value it sees for each option, so the catch-all has
      # to be emitted after the specific hosts — hence the explicit dag ordering
      # rather than relying on attribute sort order.
      "*" = lib.hm.dag.entryAfter ["github.com" "git.sddt.efko.ru"] {
        ServerAliveInterval = 60;
        # Reuse one connection for repeated git operations, but don't let a
        # master socket outlive a VPN reconnect for long.
        ControlMaster = "auto";
        ControlPath = "~/.ssh/control-%r@%h:%p";
        ControlPersist = "10m";
      };
    };
  };
}
