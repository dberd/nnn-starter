# Gaming stack. Imported ONLY from hosts/nnn-desktop — the ThinkPad
# deliberately gets none of this.
{
  local,
  pkgs,
  username,
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
  # in here, so the string never has to change. Per-title extras go before the
  # `--`, e.g. `gamescope-run --force-grab-cursor -F fsr -- %command%`.
  #
  # The store path is deliberate, and is NOT interchangeable with a bare
  # `gamescope` off PATH. A bare name resolves to /run/wrappers/bin/gamescope,
  # the cap_sys_nice wrapper that programs.gamescope.capSysNice installs below —
  # and Steam runs games inside a bubblewrap sandbox with no_new_privs set,
  # which is exactly the condition under which a file-capability binary refuses
  # to start:
  #
  #   failed to inherit capabilities: Operation not permitted
  #
  # The wrapper never gets as far as launching gamescope, Steam sees the process
  # exit within a second, and the game silently does not start. Verified both
  # ways under `steam-run`: the wrapper fails, this path works.
  #
  # --rt is gone for the same reason: realtime scheduling is what wanted the
  # capability, and the capability cannot survive the sandbox. It stays on the
  # gamescopeSession args below, which run outside any sandbox and can use it.
  gamescope-run = pkgs.writeShellScriptBin "gamescope-run" ''
    # Split our own argv at the first `--`: what comes before it is extra
    # gamescope flags for this one title, what comes after is the game.
    gs_extra=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
      gs_extra+=("$1")
      shift
    done
    if [ "$#" -gt 0 ]; then shift; fi

    # Steam launches everything with LD_PRELOAD pointing at both copies of its
    # overlay, ubuntu12_{32,64}/gameoverlayrenderer.so. Inherited by the GAME
    # that is fine and wanted — it is what Shift+Tab, Steam screenshots and
    # Steam Input hang off. Inherited by gamescope ITSELF it is the documented
    # cause of stutter that creeps in 25-40 minutes into a session and never
    # lets go (ArchWiki "Gamescope", Troubleshooting; the upstream Arch
    # gamescope-run strips it, this wrapper used not to). So gamescope and the
    # mangoapp it spawns start without it, and the original value is handed
    # back across the `--`.
    #
    # gamemoderun then does LD_PRELOAD="libgamemodeauto.so.0''${LD_PRELOAD:+:$LD_PRELOAD}"
    # on top, so the game ends up with exactly what a non-gamescope launch gives it.
    steam_preload="''${LD_PRELOAD-}"
    unset LD_PRELOAD

    if [ -n "$steam_preload" ]; then
      set -- env "LD_PRELOAD=$steam_preload" gamemoderun "$@"
    else
      set -- gamemoderun "$@"
    fi

    exec ${pkgs.gamescope}/bin/gamescope \
      -W ${width} -H ${height} -r ${refresh} \
      -f \
      --mangoapp \
      "''${gs_extra[@]}" \
      -- "$@"
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

  # programs.gamemode creates the `gamemode` group but puts nobody in it, and
  # gamemode.rules from the package grants the privileged helpers only to
  # `subject.isInGroup("gamemode")`. Without this membership every launch logs
  #
  #   pkexec: Error executing command as another user: Not authorized
  #     [COMMAND=.../libexec/cpugovctl set performance]
  #   gamemoded: ERROR: Failed to update cpu governor policy
  #   gamemoded: ERROR: Failed to update split_lock_mitigate
  #
  # and gamemoderun is decorative: the governor stays powersave and
  # kernel.split_lock_mitigate stays 1, which stalls any thread doing a
  # split-lock atomic — common in Unity titles under Proton.
  #
  # Set here rather than in ../users.nix because the group only exists on hosts
  # that import this module; the ThinkPad does not.
  users.users.${username}.extraGroups = ["gamemode"];

  # The 8BitDo Ultimate 2.4G arrives through its dongle as 2dc8:3106, and the
  # kernel's xpad driver claims it as an Xbox 360 pad — so both triggers are
  # published as 0..255 axes: LT is ABS_Z, RT is ABS_RZ.
  #
  # This pad's right trigger does not cover that range. Measured with evtest
  # across 15 full presses it tops out at 155-160, while the left one reaches
  # the end of the scale:
  #
  #   ABS_Z  (LT) -> 255   (100%)
  #   ABS_RZ (RT) -> ~156  (61%)
  #
  # A five-count spread over fifteen presses is a hard ceiling, not a soft
  # press. Titles that treat the trigger as a button never notice, but anything
  # gated on a value near the top of the range cannot be reached at all — full
  # sail on the ship in AC: Black Flag is the symptom that found this.
  #
  # xpad has no calibration of its own: its only parameters are dpad_to_buttons,
  # triggers_to_buttons, sticks_to_null and auto_poweroff, and none apply here
  # (triggers_to_buttons would discard the analog range outright, and it only
  # touches pads missing from xpad's device table anyway). The supported knob is
  # EVIOCSABS, which systemd drives from hwdb. EVDEV_ABS_05 is ABS_RZ; the
  # fields are min:max:res:fuzz:flat.
  #
  # The max is declared as the LOWEST peak measured rather than the highest, so
  # that every full press saturates: SDL and Wine both clamp to the declared
  # maximum, which puts all of the 155-160 readings on 100%. Wine reads the pad
  # through winebus' evdev backend and normalises against the same absinfo, so
  # this reaches Lutris titles too.
  #
  # ABS_Z is deliberately left alone — the left trigger is healthy, and
  # rescaling it would only make it saturate early.
  services.udev.extraHwdb = ''
    evdev:input:b0003v2DC8p3106*
      EVDEV_ABS_05=0:155:0:0:0
  '';

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
