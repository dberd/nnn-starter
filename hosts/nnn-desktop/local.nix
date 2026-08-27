# Machine-local settings for nnn-desktop.
#
# Unlike upstream nnn-starter, this file is NOT marked skip-worktree: this is a
# personal fork, and the values below have to be reproducible on the second host
# too. Real secrets (VPN credentials, ssh keys, tokens) never live here — see
# modules/nixos/vpn.nix for how those are handled.
let
  # Outputs for niri (modules/home/niri.nix). Values taken from `niri msg
  # outputs`: the two panels have different resolutions AND different scales,
  # so a single scalar monitorScale (as upstream has) can't express this.
  monitors = {
    "HDMI-A-2" = {
      # MSI MP241X. The panel does 75 Hz but advertises 60 as its preferred
      # mode, so niri picks 60 unless the rate is asked for by name — which is
      # why this sat at 60 for months. `niri msg outputs` lists both.
      mode = {
        width = 1920;
        height = 1080;
        refresh = 75.0;
      };
      scale = 1.0;
      position = {
        x = 0;
        y = 0;
      };
    };
    "DP-2" = {
      # Primary monitor: niri focuses it on startup, and the greeter is pinned
      # to it too (see programs.noctalia-greeter.settings.output in default.nix).
      focus-at-startup = true;
      # Philips PHL 245E1 — logical size 2133x1200 at scale 1.2
      mode = {
        width = 2560;
        height = 1440;
        refresh = 74.968;
      };
      scale = 1.2;
      position = {
        x = 1920;
        y = 0;
      };
    };
  };

  # Which of those panels is the biggest, by pixel count. Games belong there,
  # and two modules need to agree on the answer — modules/nixos/gaming.nix
  # points gamescope at it, modules/home/niri.nix pins gamescope's window to
  # it — so it is derived from `monitors` above rather than spelled out a
  # second time. Swap a monitor and both follow.
  names = builtins.attrNames monitors;
  pixels = name: monitors.${name}.mode.width * monitors.${name}.mode.height;
  largest =
    builtins.foldl'
    (
      best: name:
        if pixels name > pixels best
        then name
        else best
    )
    (builtins.head names)
    names;
in {
  # Login user and machine identity.
  username = "sundial";
  hostName = "nnn-desktop";
  # Shown as the account description — the greeter and Noctalia display it.
  fullName = "sundial";

  # Locale / location.
  timeZone = "Europe/Moscow";

  # Git identity (modules/home/git.nix). The work identity is applied per
  # directory via includeIf, see that module.
  gitUserName = "dberd";
  gitUserEmail = "dberd2001@gmail.com";

  inherit monitors;

  # The output games are sent to, plus the mode it runs at — see the `largest`
  # binding above for how it is picked.
  gameOutput = {
    name = largest;
    inherit (monitors.${largest}) mode;
  };
}
