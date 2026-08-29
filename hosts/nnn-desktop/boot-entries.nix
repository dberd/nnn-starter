# Boot menu entries that exist only on nnn-desktop.
#
# These used to sit in modules/nixos/boot.nix, which every host imports through
# modules/nixos/default.nix. Everything below is about the disks physically in
# THIS machine — ten frozen generations on the old ADATA, and a Windows install
# addressed by its GPT partition GUID — so on any other host it would be a menu
# full of entries that resolve to nothing. The generic half of the bootloader
# (limine itself, plymouth, the quiet boot) stayed behind in the module.
#
# Boot layout on this machine. Kernel names shift when a USB stick comes and
# goes — the GUIDs are what the entries below actually resolve:
#   nvme0n1p1  guid 1126122a-…   ESP of NixOS, this limine — first in BootOrder
#   sdb1       guid 7bffd8d6-…   ESP of the old NixOS on the ADATA
#   sda1       guid 1fef5bef-…   ESP of Windows 10
#
# The 1 TB NVMe used to hold CachyOS and its own limine; both are gone, and so
# is the chainload entry that pointed at them (docs/migrate-to-nvme.md).
{lib, ...}: let
  # ---------------------------------------------------------------------------
  # Frozen boot entries for the old NixOS that still lives on the ADATA (sdb2).
  #
  # It used to be reached by chainloading the ADATA's own limine, which meant a
  # second boot menu on top of this one. Limine cannot read btrfs, so the only
  # reason that second limine had to exist was to hand out a kernel from a FAT
  # partition. Copying that kernel here removes the need: the ADATA's kernel and
  # initrd now sit in /boot/adata-legacy on this ESP, and the generations below
  # are ordinary `protocol: linux` entries in *this* menu.
  #
  #   sudo mkdir -p /boot/adata-legacy
  #   sudo cp /mnt/adata-esp/limine/kernels/* /boot/adata-legacy/
  #
  # They deliberately do NOT go in /boot/limine: limine-install.py walks that
  # directory and deletes every file it did not write itself, so anything put
  # there would vanish on the next `nixos-rebuild switch`.
  #
  # All ten generations share one kernel (6.18.37) and differ only in `init=`.
  # Nothing regenerates this list — the old system is never rebuilt again — so
  # the store paths are pinned by hand. They resolve on sdb2, and its fstab
  # mounts by `by-partlabel/nixos` and `by-partlabel/ESP`, which are unique to
  # the ADATA (the NVMe uses `nixos-root`/`nixos-esp`). Picking one of these
  # therefore really does boot the old disk, not this one.
  #
  # When the ADATA is finally wiped for games, delete this block, the
  # `adataEntries` reference below, and /boot/adata-legacy.
  # ---------------------------------------------------------------------------
  adata = {
    kernel = "l8ccis497ymkh2m479l6j8q9ivlp8xkr-linux-6.18.37-bzImage";
    kernelHash = "7721fbda5df6dacd74a7a12cf7d3c450b2a386344d821f9b10311e32f282497db41389f39dd173696ff8176171e6b42f29ec1623a33a51cab77ba6a6ae3d25ff";
    initrd = "d6c6ir0nh1qs1cbss4wnxd2ca7122n67-initrd-linux-6.18.37-initrd";
    initrdHash = "78a351d22858800e66dbe7efb3be1f68b777ec3c1251db824fc705b717e16aad908e52b5dac5ad362efc01afdbb4a381f1ccf11d37372885ae87512636392487";
    label = "NixOS Zokor 26.11.20260629.b5aa0fb (Linux 6.18.37)";
    # Everything after `init=`. The vt.default_* palette is the old stylix
    # theme (kanagawa) — kept verbatim so those generations look as they did.
    kernelParams = "quiet root=fstab splash loglevel=0 lsm=landlock,yama,bpf vt.default_red=0x02,0x95,0xaa,0x7e,0xa1,0x9d,0x89,0xf1,0xb8,0x95,0xaa,0x7e,0xa1,0x9d,0x89,0xfe vt.default_grn=0x1c,0x8e,0x8a,0x93,0x8e,0x92,0x94,0xe0,0x99,0x8e,0x8a,0x93,0x8e,0x92,0x94,0xf6 vt.default_blu=0x3a,0x7d,0x53,0x8e,0x6d,0x7e,0x8e,0xbc,0x68,0x7d,0x53,0x8e,0x6d,0x7e,0x8e,0xcf";
  };

  # Newest first, mirroring how the NixOS module orders its own generations.
  # These are the ten the ADATA's own limine kept (it also ran maxGenerations =
  # 10). Profiles 1-52 still exist in /nix/var/nix/profiles on sdb2, but their
  # kernels were never copied to a FAT partition, so they cannot be listed here
  # without digging them back out of that disk's store. Generation 62 is simply
  # not there: system-62-link does not exist on the ADATA either.
  adataGenerations = [
    {
      gen = 63;
      date = "2026-08-25 18:45:59";
      toplevel = "v65ddqd1rmdfjp7fnyh4lrc0zb90fqcp-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 61;
      date = "2026-08-25 17:30:36";
      toplevel = "pabg429v443nr2y3aj1ck4ywlisghxhf-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 60;
      date = "2026-08-24 20:38:19";
      toplevel = "7s664lg552sbns0apjqrpc52gy4pb0il-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 59;
      date = "2026-08-23 22:13:53";
      toplevel = "68py3qnrzjizvrylaqyxf32lpqpxjnr5-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 58;
      date = "2026-08-23 21:11:39";
      toplevel = "fig8g17qbpq774md2fmiwikpr3ya1ksh-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 57;
      date = "2026-08-23 20:42:12";
      toplevel = "dnncdzrz16lz2f2h07d599m5240c1fav-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 56;
      date = "2026-08-23 20:23:27";
      toplevel = "77nsd79y13my0fnhjvc7zr68can8d3v2-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 55;
      date = "2026-08-23 20:13:28";
      toplevel = "lhxadb2hsqfxghjva71ip31mg9zm4g5d-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 54;
      date = "2026-08-23 20:09:11";
      toplevel = "sr5sj775w7sdcyv7r6pnyhiyarr28isx-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
    {
      gen = 53;
      date = "2026-08-23 19:24:56";
      toplevel = "h9gcscp6hkgx6b1vxg6n3ay295i71h0d-nixos-system-nnn-desktop-26.11.20260629.b5aa0fb";
    }
  ];

  # One `//`-prefixed sub-entry per generation, shaped like the ones the NixOS
  # module emits for this host. `boot()` is the volume limine itself booted
  # from, i.e. this ESP.
  adataEntries =
    lib.concatMapStrings (g: ''
      //Generation ${toString g.gen}
          protocol: linux
          comment: ${adata.label}, built on ${g.date}
          kernel_path: boot():/adata-legacy/${adata.kernel}#${adata.kernelHash}
          cmdline: init=/nix/store/${g.toplevel}/init ${adata.kernelParams}
          module_path: boot():/adata-legacy/${adata.initrd}#${adata.initrdHash}
    '')
    adataGenerations;
in {
  # `protocol: efi` (aliases: uefi, efi_chainload) is the current spelling for
  # chainloading — older docs say `chainload`, which today's limine rejects.
  # `guid()` resolves either a filesystem UUID or a GPT partition GUID; the
  # partition GUID used here is unambiguous.
  #
  # The Windows path is CASE SENSITIVE. Limine's own FAT driver compares long
  # file names with strcmp (case_insensitive_fopen is only ever set while it
  # hunts for its own config), so `/EFI/MICROSOFT/BOOT/BOOTMGFW.EFI` — which
  # is what the UEFI firmware's own boot entry uses, because *its* FAT driver
  # is case-insensitive — silently failed to resolve and Windows never
  # booted. `Microsoft` is 9 characters, so it has no 8.3 short name to fall
  # back on either. The spelling below is what is actually on disk.
  boot.loader.limine.extraEntries = ''
    /NixOS (ADATA, old disk)
        comment: the pre-move system on sdb2 — see the adataGenerations block in hosts/nnn-desktop/boot-entries.nix
    ${adataEntries}
    /Windows 10
        protocol: efi
        path: guid(1fef5bef-7f01-4f77-a93d-a61b09e5af04):/EFI/Microsoft/Boot/bootmgfw.efi
  '';
}
