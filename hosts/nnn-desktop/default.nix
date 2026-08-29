# nnn-desktop — AMD Ryzen 7 5700X + Radeon RX 7700/7800 XT (Navi 32), 16 GiB,
# two external monitors, UEFI, NixOS on the Kingston NVMe (btrfs subvolumes, see
# disko.nix). The ADATA still holds the previous system and stays bootable as a
# fallback — see docs/migrate-to-nvme.md and the limine entries in
# ./boot-entries.nix.
{local, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./boot-entries.nix # limine entries for the ADATA and Windows — this box only
    ../../modules/nixos/hardware/amd-desktop.nix
    ../../modules/nixos/gaming.nix # desktop only; the laptop never imports this
  ];

  networking.hostName = local.hostName;
  time.timeZone = local.timeZone;

  # Login screen geometry. The greeter runs its own tiny wlroots compositor and
  # has no way to know the layout, so it is stated here — this is what keeps the
  # 2560x1440 panel from being cropped, and it mirrors local.monitors.
  #
  # Everything else (palette, wallpaper, font) comes over from the shell:
  # Auto-Sync is on (see shell.greeter_sync in modules/home/noctalia.nix), and
  # Settings -> Security -> Noctalia Greeter -> Sync Now pushes it by hand.
  #
  # Sync writes /var/lib/noctalia-greeter/sync.toml. Keys set here live in
  # greeter.toml, which is a /nix/store symlink Sync never touches — and which
  # wins over sync.toml for every key it carries. So do NOT add an `appearance`
  # section below: a complete palette here makes Sync a no-op.
  programs.noctalia-greeter.settings = {
    session.default = "niri";
    output = {
      # Primary monitor — the greeter draws here rather than on whichever output
      # the compositor happens to pick first.
      name = "DP-2";
      layout = "HDMI-A-2:0,0; DP-2:1920,0";
      scales = "HDMI-A-2:1; DP-2:1.2";
    };
  };
}
