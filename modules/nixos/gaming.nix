# Gaming stack. Imported ONLY from hosts/nnn-desktop — the ThinkPad
# deliberately gets none of this.
{pkgs, ...}: {
  programs.steam = {
    enable = true;
    # A dedicated gamescope session selectable from the login screen; also lets
    # individual titles be launched under gamescope for scaling/HDR/FSR.
    gamescopeSession.enable = true;
    # Opens the ports Steam Remote Play needs (27031-27036 udp / 27036 tcp).
    remotePlay.openFirewall = true;
    # Proton-GE covers titles the stock Proton doesn't.
    extraCompatPackages = [pkgs.proton-ge-bin];
  };

  # CPU governor + niceness tweaks while a game is running.
  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    gamescope # micro-compositor: scaling, framelimit, FSR
    lutris # launcher for non-Steam / Wine titles
    heroic # Epic + GOG + Amazon launcher
    mangohud # in-game FPS/temp overlay
    legcord # lightweight Discord client
  ];

  # Note: 32-bit graphics libraries (needed by Steam) come from
  # hardware.graphics.enable32Bit in ./desktop.nix.
}
