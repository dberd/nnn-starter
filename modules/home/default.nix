{username, ...}: {
  imports = [
    ./cli.nix
    ./fish.nix
    ./starship.nix
    ./git.nix
    ./ssh.nix
    ./ghostty.nix
    ./neovim.nix
    ./mime.nix
    ./gtk.nix
    ./niri.nix
    ./noctalia.nix
    ./direnv.nix
    ./dev.nix
    ./claude-code.nix
    ./apps.nix
    ./media.nix
    ./vscodium.nix
    # Discord: legcord (modules/nixos/gaming.nix), not upstream's vesktop.
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Match system.stateVersion in hosts/common/default.nix. Don't bump casually.
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
