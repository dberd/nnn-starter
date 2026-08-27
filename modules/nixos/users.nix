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

  # Stylix ships its fish target as BOTH a home-manager and a NixOS module, and
  # each writes its own copy. Turning off only the home-manager one (see
  # modules/home/fish.nix, which explains why we want it off at all) leaves this
  # one writing `source …/base16-stylix.fish` into /etc/fish/config.fish — which
  # every interactive fish reads BEFORE the user config, so the colours came
  # back regardless. Both halves have to go.
  stylix.targets.fish.enable = false;

  # Passwordless sudo for the wheel group keeps `nixos-rebuild` snappy. Drop the
  # `wheelNeedsPassword = false` line if you'd rather be prompted.
  security.sudo.wheelNeedsPassword = false;
}
