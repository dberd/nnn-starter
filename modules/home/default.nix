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
    ./mango.nix
    ./noctalia.nix
    ./direnv.nix
    ./dev.nix
    ./claude-code.nix
    ./opencode.nix
    ./apps.nix
    ./media.nix
    ./vscodium.nix
    ./workspace.nix
    # Discord: legcord (modules/nixos/gaming.nix), not upstream's vesktop.
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Match system.stateVersion in hosts/common/default.nix. Don't bump casually.
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  # Nothing here installs rofi — the launcher is Noctalia's. Stylix's rofi
  # target is on anyway and writes `programs.rofi.font`, which home-manager has
  # renamed to `programs.rofi.settings.font`, so every evaluation carried that
  # warning. Same reasoning and same fix as targets.regreet in
  # modules/nixos/stylix.nix: the rename is Stylix's to follow, and switching
  # the target off is how this config stops carrying the noise.
  stylix.targets.rofi.enable = false;
}
