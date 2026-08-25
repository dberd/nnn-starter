{...}: {
  imports = [
    ./boot.nix
    ./networking.nix
    ./audio.nix
    ./fonts.nix
    ./niri.nix
    ./noctalia.nix
    ./desktop.nix
    ./stylix.nix
    ./users.nix
    ./dev.nix
    ./claude-code.nix
    ./secrets.nix
    ./vpn.nix
    ./docker.nix # optional: comment out if you don't want containers
    # NOTE: hardware is per-host — each hosts/<name>/default.nix imports exactly
    # one of ./hardware/{amd-desktop,intel-laptop}.nix. Same for ./gaming.nix
    # (desktop only) and ./apple-studio-display.nix (unused here).
  ];

  # Flakes + the modern nix CLI.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true;

  # Pull niri and noctalia as prebuilt binaries instead of compiling them.
  nix.settings.extra-substituters = [
    "https://niri.cachix.org"
    "https://noctalia.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
  ];

  # Free space thresholds fire during builds, not once a week on a timer, so
  # the disk cannot fill at the moment it matters. "Old generations must not
  # exceed N% of the disk" is not expressible: the store is deduplicated and
  # paths are shared between generations, so a per-generation size does not
  # exist as a quantity.
  nix.settings.min-free = 20 * 1024 * 1024 * 1024;
  nix.settings.max-free = 60 * 1024 * 1024 * 1024;

  # Hard-link identical files in the store. Usually saves more than deleting a
  # couple of generations would.
  nix.optimise = {
    automatic = true;
    dates = ["weekly"];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # (allowUnfree + overlays are set in flake.nix where the inputs are in scope.)

  # A lean system-wide package set; everything user-facing lives in home-manager.
  environment.systemPackages = [];
}
