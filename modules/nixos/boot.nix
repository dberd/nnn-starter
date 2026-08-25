{...}: {
  # Limine on UEFI, installed to THIS host's own ESP (/boot = sda1). It is
  # deliberately self-contained: the CachyOS limine on the 1 TB NVMe stays the
  # firmware's first boot entry for now and is never written to by NixOS.
  #
  # Boot layout on this machine:
  #   nvme0n1p1  guid 981dda21-…  ESP of CachyOS, its own limine — FIRST in BootOrder
  #   sda1       guid 7bffd8d6-…  ESP of NixOS, this limine
  #   sdb1       guid 1fef5bef-…  ESP of Windows 10
  #
  # When the NVMe eventually gets wiped, this becomes the only bootloader: drop
  # the CachyOS entry below, put its NVRAM entry first, and the Windows entry
  # here already covers the rest.
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    # Editing entries at the menu allows `init=/bin/sh`, i.e. trivial root.
    enableEditor = false;
    # Keep the generation list (and therefore /boot usage) bounded.
    maxGenerations = 10;

    # Chainload the other two systems. `protocol: efi` (aliases: uefi,
    # efi_chainload) is the current spelling — older docs say `chainload`, which
    # today's limine rejects. `guid()` resolves either a filesystem UUID or a
    # GPT partition GUID; the partition GUIDs used here are unambiguous.
    #
    # Chainloading CachyOS's *bootloader* rather than its kernel means kernel
    # updates over there never require a change in this file.
    extraEntries = ''
      /CachyOS (NVMe)
          comment: chainloads the limine on the CachyOS ESP
          protocol: efi
          path: guid(981dda21-1797-4914-bda8-f62c5d5e6d7c):/EFI/LIMINE/LIMINE_X64.EFI

      /Windows 10
          protocol: efi
          path: guid(1fef5bef-7f01-4f77-a93d-a61b09e5af04):/EFI/MICROSOFT/BOOT/BOOTMGFW.EFI
    '';
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # Quiet, graphical boot to match the omarchy-style polish.
  boot.plymouth.enable = true;
  boot.kernelParams = ["quiet"];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
}
