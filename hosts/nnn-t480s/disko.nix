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
    # PLACEHOLDER — replace with this laptop's own id before running disko.
    # Read it off the machine with `ls -l /dev/disk/by-id/`; see
    # docs/install-t480s.md step 1.
    #
    # Addressed by stable id rather than /dev/sda or /dev/nvme0n1 on purpose:
    # kernel names depend on probe order, and a live USB stick in the port
    # during the install is enough to shift them.
    device = "/dev/disk/by-id/REPLACE-ME-nvme-…";
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
      # PLACEHOLDER — must be >= RAM or hibernation cannot write the image, and
      # `systemctl hibernate` fails at the point you most wanted it to work.
      # The T480s has 8 GiB soldered plus one SODIMM slot, so this is 8, 16 or
      # 24 GiB of RAM; size this at RAM + 2 GiB and confirm with `free -g`
      # during the install.
      swap = {
        size = "18G";
        content = {
          type = "swap";
          # Emits boot.resumeDevice = /dev/t480s/swap. Without it the machine
          # suspends fine and then boots from scratch instead of resuming.
          resumeDevice = true;
          # Lower priority than zram (modules/nixos/hardware/intel-laptop.nix),
          # which the kernel gives a high priority by default — ordinary paging
          # goes to compressed RAM, and this volume is here for the hibernation
          # image and for the overflow zram cannot hold.
          priority = 100;
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
