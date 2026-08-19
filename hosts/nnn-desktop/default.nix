# nnn-desktop — AMD Ryzen 7 5700X + Radeon RX 7700/7800 XT (Navi 32), 16 GiB,
# two external monitors, UEFI, NixOS on the ADATA SSD (btrfs subvolumes, see disko.nix).
{local, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/hardware/amd-desktop.nix
    ../../modules/nixos/gaming.nix # desktop only; the laptop never imports this
  ];

  networking.hostName = local.hostName;
  time.timeZone = local.timeZone;

  # Login screen geometry. The greeter runs its own tiny wlroots compositor and
  # has no way to know the layout, so it is stated here — this is what keeps the
  # 2560x1440 panel from being cropped, and it mirrors local.monitors.
  #
  # Everything else (palette, wallpaper, font) can be pushed over from the shell
  # with Settings -> Security -> Noctalia Greeter -> Sync Now, or Auto-Sync.
  # Keys set here live in greeter.toml and always win over anything Sync writes.
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
