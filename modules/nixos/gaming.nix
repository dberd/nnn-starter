# Gaming stack. Imported ONLY from hosts/nnn-desktop — the ThinkPad
# deliberately gets none of this.
{
  local,
  pkgs,
  ...
}: let
  # The biggest panel and its mode, derived in hosts/<host>/local.nix from the
  # same attrset niri takes its outputs from. Everything below aims at it.
  inherit (local.gameOutput) mode;

  # gamescope's -r is whole Hz: local.monitors carries the exact DRM figure
  # (74.968 on the Philips), which would truncate to 74 and land on the wrong
  # mode, so round instead.
  refresh = toString (builtins.floor (mode.refresh + 0.5));
  width = toString mode.width;
  height = toString mode.height;

  # Per-title wrapper for running a game under gamescope from inside the niri
  # session. Paste
  #
  #     gamescope-run -- %command%
  #
  # into a title's Properties -> Launch Options; Steam has no global field for
  # this, so it is once per game. Everything that differs per machine is baked
  # in here, so the string never has to change.
  #
  # Kept deliberately plain: per-title extras go after the wrapper name, e.g.
  # `gamescope-run --force-grab-cursor -- %command%` for a shooter that lets the
  # pointer escape, or `-w 1920 -h 1080 -F fsr` to render below native and
  # upscale. --force-grab-cursor is NOT on by default because it pins the mouse
  # to relative mode, which is wrong for anything with a visible cursor.
  #
  # `gamescope` is left unqualified on purpose: programs.gamescope.capSysNice
  # below installs a cap_sys_nice copy at /run/wrappers/bin, which comes first
  # on PATH and is the only one that can honour --rt. Hardcoding
  # ${pkgs.gamescope} would silently pick the capability-less one.
  gamescope-run = pkgs.writeShellScriptBin "gamescope-run" ''
    # Split our own argv at the first `--`: what comes before it is extra
    # gamescope flags for this one title, what comes after is the game.
    gs_extra=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
      gs_extra+=("$1")
      shift
    done
    if [ "$#" -gt 0 ]; then shift; fi

    exec gamescope \
      -W ${width} -H ${height} -r ${refresh} \
      -f \
      --rt \
      --mangoapp \
      "''${gs_extra[@]}" \
      -- gamemoderun "$@"
  '';
in {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    # Proton-GE covers titles the stock Proton doesn't.
    extraCompatPackages = [pkgs.proton-ge-bin];

    # A "Steam" entry in the greeter's session list, next to "Niri". Picking it
    # runs `gamescope --steam <args> -- steam -tenfoot -pipewire-dmabuf`:
    # console mode, with gamescope driving KMS directly instead of nesting
    # inside a compositor. Note this is a SEPARATE session, not something that
    # changes how games launch from Steam inside niri — for that, see the
    # gamescope-run wrapper above.
    #
    # Because gamescope owns the display here, -O/-W/-H/-r pick the connector
    # and the DRM mode outright: the big panel at the highest rate it does.
    gamescopeSession = {
      enable = true;
      args = [
        "-O"
        local.gameOutput.name
        "-W"
        width
        "-H"
        height
        "-r"
        refresh
        "--rt"
        "--mangoapp"
        # Both panels report "Variable refresh rate: supported, disabled" to
        # niri, so `--adaptive-sync` would work here — left off because VRR on
        # panels this cheap tends to flicker in the low-framerate range. One
        # line to try it.
      ];
    };
  };

  # The compositor Steam's session and gamescope-run both drive.
  programs.gamescope = {
    enable = true;
    # cap_sys_nice on the binary, so --rt above is more than a no-op warning.
    capSysNice = true;
    # gamescope-wsi, the Vulkan WSI layer. Without it gamescope cannot see a
    # Vulkan game's present timings, which is what --framerate-limit and HDR
    # hang off; it is also what stops the frame limiter from adding a frame of
    # latency. 32-bit copy included, for the older titles.
    enableWsi = true;
  };

  # CPU governor + niceness tweaks while a game is running. gamescope-run pipes
  # every title through `gamemoderun`, so this is on for anything launched that
  # way without a second launch-option to remember.
  programs.gamemode.enable = true;

  # Legcord 1.2.4 registered its `legcord://` scheme with `corsEnabled: false`,
  # which blocked shelter's fetch of legcord://plugins/*/plugin.json from the
  # https://discord.com origin, so none of the bundled shelter plugins installed
  # — `legcord-screenshare` among them, which is what hands the picked PipeWire
  # source back to the main process. We patched the flag here.
  #
  # 1.3.0 ships `corsEnabled: true` itself, so the patch is gone: `--replace-fail`
  # started failing the build precisely because there was nothing left to fix.
  # (Screencasting itself — niri's Mutter ScreenCast API + xdg-desktop-portal-gnome,
  # see ./niri.nix — was never part of this.)

  environment.systemPackages = with pkgs; [
    gamescope-run # `gamescope-run -- %command%`, see above
    # programs.gamescope with capSysNice puts the binary in /run/wrappers/bin
    # and nothing in the system profile. Keep the plain package too: it is what
    # supplies `gamescopectl`, and it is the fallback for any context whose PATH
    # predates /run/wrappers/bin (a session started outside a login shell).
    gamescope
    lutris # launcher for non-Steam / Wine titles
    heroic # Epic + GOG + Amazon launcher
    mangohud # in-game FPS/temp overlay, and the mangoapp gamescope uses
    legcord # lightweight Discord client
  ];

  # Note: 32-bit graphics libraries (needed by Steam) come from
  # hardware.graphics.enable32Bit in ./desktop.nix.
}
