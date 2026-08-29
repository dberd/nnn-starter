# The generic half of the bootloader — everything that is true on every host.
# Entries for other operating systems on the same machine are per-host and live
# in hosts/<name>/boot-entries.nix (nnn-desktop has one; nnn-t480s does not,
# because it boots nothing but itself).
{...}: {
  # Limine on UEFI, installed to THIS host's own ESP (/boot). It is deliberately
  # self-contained: it never writes to anyone else's ESP.
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    # Editing entries at the menu allows `init=/bin/sh`, i.e. trivial root.
    enableEditor = false;
    # Keep the generation list (and therefore /boot usage) bounded.
    maxGenerations = 10;

    # No `remember_last_entry: yes` here on purpose. In limine's menu.c the
    # last booted entry (EFI variable LimineLastBootedEntry) is read *after*
    # default_entry and overrides it — which is exactly what we do not want:
    # the menu must always land on the newest generation, not on whatever was
    # picked last time. The NixOS module emits `default_entry: 2`, and with the
    # profile branch expanded that index is the topmost entry in the list.
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # Quiet, graphical boot to match the omarchy-style polish.
  boot.plymouth.enable = true;
  boot.kernelParams = ["quiet"];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
}
