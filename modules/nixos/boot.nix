{...}: {
  # Limine on UEFI, installed to THIS host's own ESP (/boot). It is deliberately
  # self-contained: it never writes to anyone else's ESP.
  #
  # Boot layout on this machine:
  #   nvme0n1p1  guid …            ESP of NixOS, this limine — FIRST in BootOrder
  #   sda1       guid 7bffd8d6-…   ESP of the old NixOS on the ADATA
  #   sdb1       guid 1fef5bef-…   ESP of Windows 10
  #
  # The 1 TB NVMe used to hold CachyOS and its own limine; both are gone, and so
  # is the chainload entry that pointed at them (docs/migrate-to-nvme.md).
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    # Editing entries at the menu allows `init=/bin/sh`, i.e. trivial root.
    enableEditor = false;
    # Keep the generation list (and therefore /boot usage) bounded.
    maxGenerations = 10;

    # Prepended above the entries, where limine wants its global settings.
    # Landing back on whatever was booted last is the behaviour the CachyOS
    # menu had, and the one that makes the ADATA fallback comfortable to use:
    # picking it once does not mean picking it again on the next reboot.
    extraConfig = ''
      remember_last_entry: yes
    '';

    # Chainload the other two systems. `protocol: efi` (aliases: uefi,
    # efi_chainload) is the current spelling — older docs say `chainload`, which
    # today's limine rejects. `guid()` resolves either a filesystem UUID or a
    # GPT partition GUID; the partition GUIDs used here are unambiguous.
    #
    # Chainloading the other system's *bootloader* rather than its kernel means
    # its kernel updates never require a change in this file. Note the ADATA
    # entry points at BOOTX64.EFI: NixOS installs limine under that name, not
    # limine_x64.efi.
    extraEntries = ''
      /NixOS (ADATA, old disk)
          comment: the pre-move system, kept bootable while the NVMe proves itself
          protocol: efi
          path: guid(7bffd8d6-d1f6-4e83-a6f6-c9035367f86d):/EFI/limine/BOOTX64.EFI

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
