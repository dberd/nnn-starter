# Declarative partitioning for this host. Importing this only generates
# `fileSystems`; nothing is written to disk until disko is invoked explicitly:
#
#   nix build ~/nixos-config#nixosConfigurations.nnn-desktop.config.system.build.diskoScript \
#     -o /tmp/disko-nvme
#   sudo /tmp/disko-nvme                 # DESTROYS the target disk
#
# Building the script from this flake rather than running `nix run
# github:nix-community/disko` pins the CLI to the same revision as the module
# in flake.lock — see docs/migrate-to-nvme.md for the whole procedure.
#
# The device is addressed by stable id on purpose. Kernel names are not stable:
# during the first install the NixOS disk moved from /dev/sda to /dev/sdb, and
# /dev/sda became the Windows disk — a config naming /dev/sda would have wiped
# Windows the moment disko was run in anger.
{...}: {
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7283A9CB50";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          # Partition labels are unique across the machine on purpose. Disko
          # derives `fileSystems.*.device` from them, so /etc/fstab mounts
          # /dev/disk/by-partlabel/nixos-root — and the ADATA, which stays
          # plugged in as the fallback system, still carries the old plain
          # "ESP" and "nixos". Two partitions sharing a label make
          # by-partlabel ambiguous: udev points the symlink at whichever
          # device it saw last, and the wrong root gets mounted at boot.
          label = "nixos-esp";
          start = "1M";
          # 2 GiB. The old 1 GiB ESP sat at 8% with ten generations of limine,
          # but an ESP cannot be grown later without moving what follows it.
          #
          # Check `df -h /boot` right after running disko: the partition came
          # out 2 GiB but mkfs.vfat laid a 1 GiB filesystem inside it, and the
          # shortfall only bites once ten generations have piled up
          # (docs/migrate-to-nvme.md, section 6).
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
        nixos = {
          label = "nixos-root"; # as above: unique while the old disk is around
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = ["-f" "-L" "nixos"];
            # Subvolume names and mount options match what the ADATA install
            # has been running with, so the move changes nothing above the
            # filesystem layer.
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
  };
}
