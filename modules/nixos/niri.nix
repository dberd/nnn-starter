{pkgs, ...}: {
  # Enable niri from niri-flake. The module pulls in systemd units, polkit,
  # the screencast portal and sane session defaults.
  programs.niri.enable = true;
  # niri from OUR nixpkgs, not from niri-flake's package set, and the reason is
  # glibc. niri-flake deliberately does not follow our nixpkgs so that its
  # prebuilt packages stay byte-identical to niri.cachix.org — but a compositor
  # dlopens the system's Mesa out of /run/opengl-driver/lib, and that Mesa is
  # built against OUR glibc. When the two nixpkgs drift apart far enough, the
  # load fails:
  #
  #   MESA-LOADER: failed to open dri: …/glibc-2.42-67/lib/libm.so.6:
  #     version `GLIBC_2.43' not found (required by …/mesa-26.2.4/libgallium.so)
  #   WARN niri::backend::tty: error adding primary node device
  #
  # which is how the 2026-10-14 update produced a session with no GPU at all:
  # niri fell back to llvmpipe, stopped advertising a dmabuf main device, and
  # every client — Noctalia included — went software too. A cache hit is not
  # worth a desktop rendered on the CPU.
  #
  # nixpkgs' own niri is 26.4.0, the same version niri-flake's `niri-unstable`
  # was pinned to, and it carries both pieces this config needs from the config
  # parser:
  #
  #   include            niri 25.11   (25.08: "unexpected node `include`")
  #   include optional=  niri 26.04   lets `niri validate` pass at BUILD time,
  #                                   when noctalia.kdl does not exist yet
  #
  # (Noctalia themes niri through `include "noctalia.kdl"`; see ../home/niri.nix
  # for the third, non-version reason that include path is absolute.)
  #
  # It is also an ordinary cache.nixos.org hit, so nothing is compiled either.
  # niri-flake stays for its module and settings schema — only the package
  # changes. If its schema ever emits a node this release rejects, the rebuild
  # fails loudly: the home module runs `niri validate` against THIS package at
  # build time. The fallback then is `pkgs.niri-unstable` — the flake's own
  # source built against our nixpkgs through its overlay, correct glibc, at the
  # price of a from-source Rust build.
  programs.niri.package = pkgs.niri;

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

  # Electron/Chromium apps (vscodium, element, vesktop) run as
  # native Wayland clients instead of XWayland.
  #
  # NOTE: do NOT set GDK_BACKEND globally — that breaks the screencast portal.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Login screen: noctalia-greeter instead of tuigreet. tuigreet draws into the
  # console framebuffer and knows nothing about monitor layout or per-output
  # scaling, which is why the 2560x1440 panel came out cropped. This one gets
  # that geometry declaratively (see hosts/nnn-desktop/default.nix) and shares
  # Noctalia's visual language, so login, lock screen and desktop match.
  #
  # Its module sets services.greetd.enable and the session command itself, both
  # with mkDefault — so do NOT set `command` here, a plain assignment would
  # override it and put tuigreet back.
  services.displayManager.noctalia-greeter.enable = true;
  services.greetd.settings.default_session.user = "greeter";

  # Brightness keys are handled by brightnessctl (installed in desktop.nix),
  # which talks to logind and needs no extra privileges in a session.
}
