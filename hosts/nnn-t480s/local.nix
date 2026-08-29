# Machine-local settings for nnn-t480s (ThinkPad T480s).
#
# Same rules as the desktop's copy: tracked in git, no secrets. Real secrets
# (VPN credentials, ssh keys) come from sops — see modules/nixos/secrets.nix.
{
  # Login user and machine identity. The username matches nnn-desktop on
  # purpose: modules/home is shared verbatim, and several paths in it are
  # /home/${username}/… — a different name here would mean a different
  # workspace layout for no gain.
  username = "sundial";
  hostName = "nnn-t480s";
  # Shown as the account description — the greeter and Noctalia display it.
  fullName = "sundial";

  # Locale / location.
  timeZone = "Europe/Moscow";

  # Git identity (modules/home/git.nix). The work identity is applied per
  # directory via includeIf, see that module.
  gitUserName = "dberd";
  gitUserEmail = "dberd2001@gmail.com";

  # The internal panel, and the only output this machine has. flake.nix derives
  # `gameOutput` from this attrset; on a single-output host that resolves to
  # eDP-1, which keeps the gamescope window rule in modules/home/niri.nix valid
  # even though modules/nixos/gaming.nix is never imported here.
  #
  # PLACEHOLDER until the machine is in hand. The T480s shipped with several
  # panels (1920x1080 IPS is the common one, 2560x1440 on some SKUs), so read
  # the real values off `niri msg outputs` after the first boot and correct
  # them here — a wrong mode makes niri fall back to the panel's preferred one
  # silently, and a wrong scale is just the wrong text size.
  monitors."eDP-1" = {
    focus-at-startup = true;
    mode = {
      width = 1920;
      height = 1080;
      refresh = 60.0;
    };
    # 14" at 1920x1080 is ~157 dpi. 1.0 is readable; bump to 1.25 if it isn't.
    scale = 1.0;
    position = {
      x = 0;
      y = 0;
    };
  };
}
