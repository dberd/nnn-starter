# Hardware defaults for an AMD desktop (Ryzen 7 5700X + Radeon RX 7700/7800 XT,
# Navi 32 / RDNA3). Counterpart to ./intel-laptop.nix — a host imports exactly
# one of the two.
{
  pkgs,
  username,
  ...
}: {
  # Load amdgpu in the initrd so KMS (and therefore plymouth) comes up on the
  # real driver instead of flickering through simpledrm first.
  boot.initrd.kernelModules = ["amdgpu"];

  hardware.cpu.amd.updateMicrocode = true;
  # amdgpu needs its firmware blobs; the generated hardware-configuration.nix
  # normally sets this too, but state it here so the module is self-contained.
  hardware.enableRedistributableFirmware = true;

  # VA-API on RDNA3 is provided by mesa itself (radeonsi), which comes with
  # hardware.graphics.enable in ../desktop.nix — no extra driver package is
  # needed, unlike the Intel side. Pin the driver name so libva doesn't probe.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  # Deliberately NOT installing amdvlk: RADV (in mesa) is faster and better
  # maintained, and having both makes Vulkan loader ICD selection ambiguous.
  environment.systemPackages = with pkgs; [
    libva-utils # `vainfo` — check decode/encode profiles
    radeontop # GPU utilization
    ddcutil # DDC/CI — brightness on external monitors (see hardware.i2c below)
  ];

  # Brightness on external monitors goes over DDC/CI, which needs the i2c-dev
  # module, the /dev/i2c-* nodes and group, and udev rules — hardware.i2c sets
  # up all three. Without it Noctalia reports "brightness control unavailable",
  # since there is no backlight device on a desktop for it to fall back to.
  hardware.i2c.enable = true;
  users.users.${username}.extraGroups = ["i2c"];

  # Firmware updates via LVFS.
  services.fwupd.enable = true;

  # Compressed RAM swap, sized at 100% of RAM. That figure is a cap, not a
  # reservation: zstd gets ~3.5:1 on Electron and browser heaps, so a full
  # 16 GiB zram costs roughly 4-5 GiB of real RAM. Still far too small to
  # hibernate, which would need a disk swap >= RAM.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  # Without the two killers below this box livelocks instead of OOM-killing:
  # zram is the only swap, so once it fills there is no non-RAM tier left and
  # the kernel spins in reclaim indefinitely. That is how it froze hard on
  # 2026-08-27 — the journal stops mid-sentence and dmesg has no OOM entry at
  # all, because nothing was ever killed.
  #
  # earlyoom polls MemAvailable and SIGTERMs the largest process before that
  # point. It fires only when the memory AND swap thresholds are both crossed,
  # so both swap thresholds are pinned at 100 to keep that half permanently
  # true: zram lives in RAM and is therefore already accounted for in
  # MemAvailable, and a large zram would otherwise keep "free swap" high enough
  # to veto every kill. The SIGKILL threshold has to be set explicitly — left
  # unset it defaults to half of the SIGTERM one, i.e. 50%, which would let a
  # half-empty zram block the hard kill in exactly the situation this guards.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 8; # SIGTERM below ~1.2 GiB available
    freeMemKillThreshold = 4; # SIGKILL below ~620 MiB
    freeSwapThreshold = 100;
    freeSwapKillThreshold = 100;
  };

  # systemd-oomd already runs, but monitors nothing: slices ship with
  # ManagedOOMMemoryPressure=auto, which means "ignore this cgroup". Switch the
  # user slices to kill for a PSI-based second line of defence under earlyoom.
  systemd.oomd.enableUserSlices = true;

  # Begin reclaim earlier. The default 10 (0.1% of RAM) is far too late to react
  # at desktop allocation rates, leaving no slack to swap into before a stall.
  boot.kernel.sysctl."vm.watermark_scale_factor" = 200;
}
