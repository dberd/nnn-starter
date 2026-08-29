# nnn-t480s — ThinkPad T480s, Intel Kaby Lake R, internal panel only, UEFI.
# NixOS is the only system on the disk (see ./disko.nix), so there are no
# chainload entries and no ./boot-entries.nix counterpart to the desktop's.
#
# What this host does NOT import is as deliberate as what it does:
# ../../modules/nixos/gaming.nix stays on the desktop.
{
  inputs,
  local,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/hardware/intel-laptop.nix
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t480s
  ];

  networking.hostName = local.hostName;
  time.timeZone = local.timeZone;

  # systemd in stage 1. With LUKS this is what puts the passphrase prompt on the
  # plymouth splash instead of behind it, and it is also what makes resume from
  # the encrypted swap work in the right order: unlock, then look for the image.
  boot.initrd.systemd.enable = true;

  # Kaby Lake R is Gen9. nixos-hardware's Intel GPU module installs BOTH VA-API
  # drivers when it is not told which one to use, and the old i965 one would
  # then be sitting next to iHD for libva to pick between — while
  # modules/nixos/hardware/intel-laptop.nix has already pinned
  # LIBVA_DRIVER_NAME=iHD. Say it once here instead.
  hardware.intelgpu.vaapiDriver = "intel-media-driver";
  # Gen8–11 take the legacy compute runtime; the default targets Gen12+.
  hardware.intelgpu.computeRuntime = "legacy";

  # nixos-hardware turns on services.throttled for this model — the fix for the
  # firmware asking for a permanently reduced power limit (BD PROCHOT), which
  # the kernel otherwise honours until reboot. It writes the same MSRs thermald
  # does, so thermald (enabled generically in intel-laptop.nix) goes off here
  # rather than having the two fight over the package power limit.
  services.thermald.enable = false;

  # Charge thresholds. Holding a li-ion cell at 100% is what ages it; stopping
  # at 80% costs about an hour of runtime and buys years.
  #
  # NOT done through TLP, even though nixos-hardware's laptop profile offers it:
  # that profile only enables TLP when power-profiles-daemon is off, and PPD is
  # on here because Noctalia's recommendedServices turns it on — it is what the
  # shell's own power-profile widget talks to. The two daemons are mutually
  # exclusive, and the widget is worth more than TLP's extra knobs.
  #
  # Thresholds do not need either daemon: the thinkpad_acpi driver exposes them
  # as plain sysfs attributes. A udev rule rather than a oneshot service so the
  # values are reapplied when a battery is hot-plugged — BAT1 on the T480s is
  # the removable one, and it comes back with the driver's defaults.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT[01]", ATTR{charge_control_start_threshold}="75", ATTR{charge_control_end_threshold}="80"
  '';

  # Login screen geometry. The greeter runs its own tiny wlroots compositor and
  # cannot know the layout, so it is stated here and mirrors local.monitors.
  # Everything else (palette, wallpaper, font) arrives from the shell over
  # Auto-Sync — see the long comment in hosts/nnn-desktop/default.nix, and do
  # NOT add an `appearance` section here for the same reason.
  programs.noctalia-greeter.settings = {
    session.default = "niri";
    output = {
      name = "eDP-1";
      layout = "eDP-1:0,0";
      scales = "eDP-1:1";
    };
  };
}
