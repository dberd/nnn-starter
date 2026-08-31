# Declarative partitioning for nnn-t480s. Importing this only generates
# `fileSystems` and `swapDevices`; nothing is written to disk until disko is
# invoked explicitly:
#
#   nix build ~/nixos-config#nixosConfigurations.nnn-t480s.config.system.build.diskoScript \
#     -o /tmp/disko-t480s
#   sudo /tmp/disko-t480s                # DESTROYS the target disk
#
# Building the script from this flake rather than running `nix run
# github:nix-community/disko` pins the CLI to the same revision as the module in
# flake.lock. The whole procedure is docs/install-t480s.md.
#
# This machine has no other operating system on it — NixOS took the disk whole —
# so there is nothing here to preserve and no second ESP to be careful around.
#
# Layout, and why:
#
#   ESP        2 GiB   plain vfat, /boot
#   luks       rest    → LVM vg "t480s" → lv swap + lv root (btrfs)
#
# The ESP has to stay unencrypted: the firmware reads it. Everything else,
# including swap, is inside one LUKS container. Swap being inside it is the
# point — a hibernation image is a byte-for-byte copy of RAM, so leaving it on
# an unencrypted partition would hand over every key the running system held.
#
# LVM inside LUKS, rather than a swapfile on btrfs, is what keeps hibernation
# boring. A btrfs swapfile needs `btrfs inspect-internal map-swapfile -r` and a
# hand-maintained `resume_offset=` kernel parameter, recomputed every time the
# file is recreated. A logical volume is a stable block device: `resumeDevice`
# below makes disko emit boot.resumeDevice and there is no offset to track.
# A second LUKS container for swap would have worked too, at the price of a
# second passphrase prompt at every boot.
{...}: {
  disko.devices.disk.main = {
    type = "disk";
    # This laptop's own NVMe, read off the machine during the install.
    #
    # Addressed by stable id rather than /dev/sda or /dev/nvme0n1 on purpose:
    # kernel names depend on probe order, and a live USB stick in the port
    # during the install is enough to shift them.
    device = "/dev/disk/by-id/nvme-eui.001b444a44c22b33";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          # Unique across every machine here, same reasoning as the desktop's:
          # disko derives fileSystems.*.device from the label, so a duplicate
          # would make /dev/disk/by-partlabel ambiguous if the two disks ever
          # met in one box.
          label = "t480s-esp";
          start = "1M";
          # 2 GiB. Ten limine generations fit in well under a quarter of that,
          # but an ESP cannot be grown later without moving what follows it.
          # Check `df -h /boot` right after disko runs: mkfs.vfat has been seen
          # to lay a smaller filesystem than the partition it was given.
          end = "2049M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            # Force FAT32. mkfs.vfat picks the FAT width from the partition size
            # and has been seen to lay a filesystem smaller than the partition
            # it was given (see the ESP comment in hosts/nnn-desktop/disko.nix).
            # The T480s' ESP came out corrupt on its very first boot — fsck.vfat
            # reported clusters out of range — and had to be reformatted and the
            # bootloader reinstalled. The cause was never proven, so this is a
            # cheap hedge rather than a known fix: an ESP should be FAT32 in any
            # case, and saying so removes one variable.
            extraArgs = ["-F" "32"];
            mountpoint = "/boot";
            mountOptions = ["fmask=0022" "dmask=0022"];
          };
        };

        luks = {
          label = "t480s-luks";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # No keyFile and no passwordFile: disko prompts for the passphrase
            # once while partitioning, and systemd-cryptsetup prompts for it at
            # every boot. There is nothing to leave lying around on the stick.
            #
            # initrdUnlock defaults to true, which is what emits the
            # boot.initrd.luks.devices entry that unlocks this before the root
            # filesystem — and therefore before resume.
            settings = {
              # TRIM passes through to the SSD. This is a deliberate, standard
              # trade: it lets an attacker with repeated physical access see
              # which blocks are unused, i.e. roughly how full the disk is.
              # Worth it to keep the drive from degrading.
              allowDiscards = true;
              # Skip the encryption workqueues. On a modern SSD they are pure
              # latency; the kernel's own dm-crypt documentation recommends
              # bypassing them for flash.
              bypassWorkqueues = true;
            };
            content = {
              type = "lvm_pv";
              vg = "t480s";
            };
          };
        };
      };
    };
  };

  disko.devices.lvm_vg.t480s = {
    type = "lvm_vg";
    lvs = {
      # 16 GiB of RAM on this machine, so 18G: the hibernation image has to fit,
      # and swap smaller than RAM makes `systemctl hibernate` fail at exactly
      # the moment it was wanted. Confirmed on the machine with `free -g`.
      swap = {
        size = "18G";
        content = {
          type = "swap";
          # Emits boot.resumeDevice = /dev/t480s/swap. Without it the machine
          # suspends fine and then boots from scratch instead of resuming.
          resumeDevice = true;
          # BELOW zram, which modules/nixos/hardware/intel-laptop.nix enables and
          # NixOS gives priority 5. In Linux a HIGHER number means "use this one
          # first", so the 100 that used to sit here did the opposite of what its
          # comment claimed: ordinary paging went to the SSD while the compressed
          # RAM that exists to absorb it sat idle. `swapon --show` on the running
          # laptop is what caught it. Hibernation is unaffected either way — it
          # writes to boot.resumeDevice, not to whatever has the highest priority
          # — but the SSD wear was real.
          priority = 1;
          discardPolicy = "pages";
        };
      };

      root = {
        size = "100%FREE";
        content = {
          type = "btrfs";
          extraArgs = ["-f" "-L" "nixos"];
          # Same subvolume names and mount options as nnn-desktop, so anything
          # written about snapshots or rollbacks applies to both machines.
          subvolumes = let
            opts = ["compress=zstd:1" "noatime" "ssd" "discard=async"];
          in {
            "@" = {
              mountpoint = "/";
              mountOptions = opts;
            };
            "@home" = {
              mountpoint = "/home";
              mountOptions = opts;
            };
            "@nix" = {
              mountpoint = "/nix";
              mountOptions = opts;
            };
            "@log" = {
              mountpoint = "/var/log";
              mountOptions = opts;
            };
            "@snapshots" = {
              mountpoint = "/.snapshots";
              mountOptions = opts;
            };
          };
        };
      };
    };
  };
}
