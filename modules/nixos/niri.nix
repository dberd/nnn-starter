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
  #
  # `niri-unstable`, not `niri-stable`, and the reason is the config parser:
  # Noctalia themes niri through `include "noctalia.kdl"`, and both pieces that
  # make that takeable landed after the 25.08 release —
  #
  #   include            niri 25.11   (25.08: "unexpected node `include`")
  #   include optional=  niri 26.04   lets `niri validate` pass at BUILD time,
  #                                   when noctalia.kdl does not exist yet
  #
  # (An absolute include path, which ../home/niri.nix builds from
  # `xdg.configHome`, is needed for a third reason that is not a version one: a
  # relative include resolves against the file it sits in, and that file is in
  # /nix/store rather than ~/.config/niri.)
  #
  # Both channels are cached in niri.cachix.org, so this is a download, not a
  # build. The cost is that unstable moves: a `nix flake update niri` can bring
  # a config-schema change. That fails loudly rather than silently — the home
  # module runs `niri validate` against THIS package at build time — so a bad
  # bump breaks the rebuild, never the running session.
  programs.niri.package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;

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
  programs.noctalia-greeter.enable = true;
  services.greetd.settings.default_session.user = "greeter";

  # Brightness keys are handled by brightnessctl (installed in desktop.nix),
  # which talks to logind and needs no extra privileges in a session.
}
