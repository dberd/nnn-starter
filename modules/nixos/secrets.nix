{username, ...}: {
  # Secrets live encrypted in secrets/secrets.yaml and are decrypted at
  # activation. Edit them with:
  #
  #   nix develop            # brings sops and age into $PATH
  #   sops secrets/secrets.yaml
  #
  # The private key is /var/lib/sops-nix/key.txt. It is the one piece that
  # cannot be in the repo — bringing it (on a USB stick, or by pasting it) is
  # the only manual step left when deploying this configuration to a new
  # machine. Its public half is recorded in .sops.yaml.
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;

    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Nothing to derive a key from: sshd is not enabled, so there are no host
    # keys. Stated explicitly so activation fails loudly rather than silently
    # looking for keys that will never exist.
    age.sshKeyPaths = [];
    gnupg.sshKeyPaths = [];

    # These are placed straight into the user's home rather than left in
    # /run/secrets: snxctl and ssh both look for them at fixed paths, and both
    # refuse to use a key that is group- or world-readable.
    secrets = {
      snx-rs-conf = {
        owner = username;
        mode = "0600";
        path = "/home/${username}/.config/snx-rs/snx-rs.conf";
      };
      ssh-github = {
        owner = username;
        mode = "0600";
        path = "/home/${username}/.ssh/id_ed25519_github_dberd";
      };
      ssh-gitlab = {
        owner = username;
        mode = "0600";
        path = "/home/${username}/.ssh/id_ed25519_gitlab_efko";
      };
    };
  };
}
