{pkgs, ...}: {
  # Polkit + a keyring so apps can request privileges and store secrets.
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;

  # …and an agent to actually show the password prompt. security.polkit.enable
  # only starts the daemon; without an authentication agent every privileged
  # GUI action fails *silently*. That was why other disks looked unreachable:
  # udisks2 is running (services.gvfs pulls it in), but mounting an internal
  # drive needs org.freedesktop.udisks2.filesystem-mount-system, and there was
  # nobody to ask. niri's own docs list an agent as required.
  #
  # GTK agent rather than the KDE one: Nautilus, gvfs and gnome-keyring are
  # already here, and Stylix themes GTK, so it matches the rest.
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome authentication agent";
    wantedBy = ["graphical-session.target"];
    after = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

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
