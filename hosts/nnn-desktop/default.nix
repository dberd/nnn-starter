# nnn-desktop — AMD Ryzen 7 5700X + Radeon RX 7700/7800 XT (Navi 32), 16 GiB,
# two external monitors, UEFI, NixOS on /dev/sda (btrfs subvolumes).
{local, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/amd-desktop.nix
    ../../modules/nixos/gaming.nix # desktop only; the laptop never imports this
  ];

  networking.hostName = local.hostName;
  time.timeZone = local.timeZone;

  # btrfs mount options. nixos-generate-config only emits `subvol=`, dropping
  # everything else the filesystem was mounted with, so they are restated here
  # instead of in the generated hardware-configuration.nix — that file gets
  # overwritten whenever it is regenerated, this one doesn't.
  # `options` is a list type, so these merge with the `subvol=` entries.
  #
  # /var/log and /nix don't need `neededForBoot`: nixpkgs' pathsNeededForBoot
  # already covers both.
  fileSystems = let
    btrfs = ["compress=zstd:1" "noatime" "ssd" "discard=async"];
  in {
    "/".options = btrfs;
    "/home".options = btrfs;
    "/nix".options = btrfs;
    "/var/log".options = btrfs;
    "/.snapshots".options = btrfs;
  };
}
