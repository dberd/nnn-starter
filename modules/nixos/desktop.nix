{pkgs, ...}: {
  # Polkit + a keyring so apps can request privileges and store secrets. The
  # authentication agent that shows the password prompt comes from niri-flake
  # (niri-flake-polkit.service), so none is declared here.
  security.polkit.enable = true;

  # Let wheel mount disks without an authentication prompt. udisks classes
  # internal drives under filesystem-mount-system, which defaults to
  # auth_admin_keep — and the prompt never actually appears here, so Nautilus
  # just reports "not authorized" for the NVMe and the Windows partition.
  #
  # This is not a loosening of the security model: wheelNeedsPassword is already
  # false (see users.nix), so anything running as this user can become root
  # without authenticating anyway. Asking for a password to mount a disk while
  # `sudo mount` needs none is friction, not protection.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id.indexOf("org.freedesktop.udisks2.filesystem-mount") === 0
          && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;

  # Hardware-accelerated graphics (needed by niri / OpenGL apps).
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Bluetooth + a few desktop conveniences.
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  services.upower.enable = true;
  programs.gnome-disks.enable = true;
  services.gvfs.enable = true; # trash + mounting for file managers.

  # Read/write NTFS. Without this the Windows partition on the second disk
  # cannot be mounted at all — udisks reports the drive but there is no
  # mount.ntfs helper for it, so authorization is beside the point.
  boot.supportedFilesystems = ["ntfs"];

  # A handful of GUI essentials live at the system level so they're always
  # present regardless of which user logs in.
  environment.systemPackages = with pkgs; [
    brightnessctl
    playerctl
    wl-clipboard
    grim
    slurp
    libnotify
    xdg-utils
  ];
}
