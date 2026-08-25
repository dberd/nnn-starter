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

  # Legcord 1.2.4 registers its internal `legcord://` scheme with
  # `corsEnabled: false`, so shelter's fetch of legcord://plugins/*/plugin.json
  # from the https://discord.com origin is blocked by Chromium's CORS check.
  # None of the bundled shelter plugins install as a result — including
  # `legcord-screenshare`, which draws the "Share" dialog that hands the picked
  # PipeWire source back to the main process. Without it the portal dialog
  # appears, the selection goes nowhere, and Discord receives no stream at all
  # (no video and no audio). Flipping the flag is the whole fix; screencasting
  # itself (niri's Mutter ScreenCast API + xdg-desktop-portal-gnome, see
  # ./niri.nix) was never the problem.
  #
  # Upstream bug, not a nixpkgs one — drop this once Legcord ships the fix.
  nixpkgs.overlays = [
    (_final: prev: {
      legcord = prev.legcord.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace src/protocol.ts \
              --replace-fail "corsEnabled: false" "corsEnabled: true"
          '';
      });
    })
  ];

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
