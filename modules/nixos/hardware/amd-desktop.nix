# Hardware defaults for an AMD desktop (Ryzen 7 5700X + Radeon RX 7700/7800 XT,
# Navi 32 / RDNA3). Counterpart to ./intel-laptop.nix — a host imports exactly
# one of the two.
{pkgs, ...}: {
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
  ];

  # Firmware updates via LVFS.
  services.fwupd.enable = true;

  # Compressed RAM swap. With 16 GiB the default (50% of RAM) is a good trade;
  # note this is too small to hibernate, which would need a disk swap >= RAM.
  zramSwap.enable = true;
}
