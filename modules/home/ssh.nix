{lib, ...}: {
  # GitHub is used over ssh (the corporate GitLab is https + libsecret, see
  # ./git.nix). Keys themselves are NOT managed here — copy ~/.ssh/id_ed25519
  # over by hand; only the client config is declarative.
  programs.ssh = {
    enable = true;
    # We write our own `Host *` block below instead of home-manager's default one.
    enableDefaultConfig = false;

    # `settings` takes native ssh_config option names (the older camelCase
    # `matchBlocks` API is deprecated). Attribute names become `Host <name>`.
    settings = {
      "github.com" = {
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = "yes";
      };

      # ssh takes the first value it sees for each option, so the catch-all has
      # to be emitted after the specific host — hence the explicit dag ordering
      # rather than relying on attribute sort order.
      "*" = lib.hm.dag.entryAfter ["github.com"] {
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
