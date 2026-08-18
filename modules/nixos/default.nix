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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # (allowUnfree + overlays are set in flake.nix where the inputs are in scope.)

  # A lean system-wide package set; everything user-facing lives in home-manager.
  environment.systemPackages = [];
}
