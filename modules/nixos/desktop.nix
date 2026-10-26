{
  inputs,
  pkgs,
  ...
}: {
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
  #
  # `package` is pinned rather than left at nixpkgs' current mesa, and this one
  # option is the whole fix for X11 apps on this machine: /run/opengl-driver is
  # what every GL client dlopens at runtime, so pointing it at mesa 26.2.1
  # restores the GLX client that 26.2.4 broke. See the long note on the
  # `nixpkgs-mesa` input in flake.nix for the bisect and for when to drop it.
  #
  # Nothing else moves: apps still link the current nixpkgs' libglvnd and only
  # the vendor library behind it comes from the pin — the combination this
  # machine has been running all along, and verified again against the new
  # Xwayland 24.1.14 before being written down. The pinned mesa is built
  # against glibc 2.42 while the system is on 2.44, which is the harmless
  # direction of that skew (a library built against an older glibc runs under a
  # newer one; the reverse is what cost niri its GPU — see modules/nixos/niri.nix).
  #
  # package32 matters for Steam and anything else 32-bit: leaving it on the
  # broken mesa would fix X11 only for 64-bit clients.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    package = inputs.nixpkgs-mesa.legacyPackages.${pkgs.stdenv.hostPlatform.system}.mesa;
    package32 = inputs.nixpkgs-mesa.legacyPackages.${pkgs.stdenv.hostPlatform.system}.pkgsi686Linux.mesa;
  };

  # Bluetooth + a few desktop conveniences.
  #
  # Deliberately no `services.blueman.enable`: blueman autostarts a tray applet
  # that duplicated Noctalia's own bluetooth widget in the bar. Noctalia talks
  # to BlueZ over D-Bus directly and does not reference blueman anywhere, so the
  # applet was pure duplication. bluetoothd itself comes from the line below.
  hardware.bluetooth.enable = true;
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
