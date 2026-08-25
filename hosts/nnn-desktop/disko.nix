# Declarative partitioning for this host, describing the layout the disk already
# has. Importing this only generates `fileSystems`; nothing is written to disk
# until disko is invoked explicitly:
#
#   sudo nix run github:nix-community/disko -- --mode disko \
#     --flake ~/nixos-config#nnn-desktop      # DESTROYS the target disk
#
# The device is addressed by stable id on purpose. Kernel names are not stable:
# during this install the NixOS disk moved from /dev/sda to /dev/sdb, and
# /dev/sda is now the Windows disk — a config naming /dev/sda would have wiped
# Windows the moment disko was run in anger.
{...}: {
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-ADATA_SU650_2K2020015098";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          # Match the label already on disk. Without this disko would derive
          # "disk-main-ESP", which does not exist here — and the system would
          # not find its filesystems at boot.
          label = "ESP";
          start = "1M";
          end = "1025M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["fmask=0022" "dmask=0022"];
          };
        };
        nixos = {
          label = "nixos"; # as above: the on-disk label, not disko's derived name
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = ["-f" "-L" "nixos"];
            # Subvolume names match what is on disk; the mount options are the
            # ones the filesystem is actually mounted with today.
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
