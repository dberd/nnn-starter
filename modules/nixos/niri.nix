{
  pkgs,
  inputs,
  ...
}: {
  # Enable niri from niri-flake. The module pulls in systemd units, polkit,
  # the screencast portal and sane session defaults.
  programs.niri.enable = true;
  # Use niri-flake's own prebuilt package (built against its nixpkgs) so it
  # comes from niri.cachix.org instead of compiling from source. This is the
  # exact build the niri-flake settings schema targets.
  programs.niri.package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-stable;

  # Wayland portals. Per niri's own recommendations: the gnome backend is
  # REQUIRED for screencasting, gtk is the general-purpose fallback, and
  # gnome-keyring (enabled in ./desktop.nix) provides the Secret portal.
  #
  # Every interface we care about is pinned explicitly rather than left to the
  # order of `default`, so a backend gaining/losing an implementation upstream
  # can't silently move a dialog somewhere else.
  xdg.portal = {
    enable = true;
    # Route xdg-open through the portal so sandboxed/Electron apps honour the
    # same default-application choices as everything else.
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config.niri = {
      default = [
        "gnome"
        "gtk"
      ];
      "org.freedesktop.impl.portal.ScreenCast" = ["gnome"];
      "org.freedesktop.impl.portal.Screenshot" = ["gnome"];
      # xdg-desktop-portal-gnome >= 47 uses Nautilus as its file chooser, which
      # is what we want (nautilus is installed in modules/home/apps.nix). Set
      # this to "gtk" instead to get the plain GTK file dialog back.
      "org.freedesktop.impl.portal.FileChooser" = ["gnome"];
      "org.freedesktop.impl.portal.Secret" = ["gnome-keyring"];
    };
  };

  # Electron/Chromium apps (vscodium, element, logseq, legcord, throne) run as
  # native Wayland clients instead of XWayland.
  #
  # NOTE: do NOT set GDK_BACKEND globally — that breaks the screencast portal.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Minimal graphical login: tuigreet drops you straight into a niri session.
  # Flip `services.greetd.settings.default_session.user` to your username and
  # set `initial_session` instead of `default_session` to autologin.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
      user = "greeter";
    };
  };

  # Brightness keys are handled by brightnessctl (installed in desktop.nix),
  # which talks to logind and needs no extra privileges in a session.
}
