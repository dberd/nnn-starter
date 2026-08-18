{
  pkgs,
  username,
  local,
  ...
}: {
  # ⇩ username/description come from local.nix.
  users.users.${username} = {
    isNormalUser = true;
    description = local.fullName;
    # Pinned rather than auto-assigned, so anything keyed on the uid (firewall
    # rules, cgroup paths, NFS mounts) can't silently stop matching later.
    uid = 1000;
    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "video"
      "audio"
      "input"
    ];
    shell = pkgs.fish;
  };

  # fish must be enabled at the system level to be a valid login shell. This
  # also generates fish completions from the man pages of installed packages.
  programs.fish.enable = true;

  # Passwordless sudo for the wheel group keeps `nixos-rebuild` snappy. Drop the
  # `wheelNeedsPassword = false` line if you'd rather be prompted.
  security.sudo.wheelNeedsPassword = false;
}
