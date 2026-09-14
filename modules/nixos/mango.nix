{pkgs, ...}: {
  # MangoWC as a SECOND wayland session next to niri (./niri.nix), not a
  # replacement. Both show up in the greeter; `session.default` in
  # hosts/<host>/default.nix still points at niri, so this costs nothing until
  # it is picked by hand.
  #
  # Deliberately thin. The flake's own NixOS module (inputs.mango.nixosModules.mango,
  # wired in flake.nix) already does everything that would otherwise be written
  # out here:
  #
  #   * environment.systemPackages += mango  — which is also where `mmsg` comes
  #     from; it is built by the same meson project, not a separate package, and
  #     Noctalia's theme post-hook shells out to it.
  #   * services.displayManager.sessionPackages += mango, i.e. the
  #     wayland-sessions/mango.desktop entry the greeter lists (addLoginEntry,
  #     default true).
  #   * xdg.portal.config.mango — gtk by default, wlr for ScreenCast/Screenshot,
  #     gnome-keyring for Secret. This does NOT disturb the config.niri block in
  #     ./niri.nix: xdg.portal.config is keyed by XDG_CURRENT_DESKTOP, so the two
  #     sessions pick different backends from the same portal set. extraPortals
  #     is a list and merges, so xdg-desktop-portal-wlr joins gnome+gtk rather
  #     than replacing them.
  #   * programs.xwayland.enable — mango speaks XWayland itself, so unlike niri
  #     it needs no xwayland-satellite.
  #   * security.polkit.enable, services.graphical-desktop.enable.
  #
  # It also sets disabledModules = ["programs/wayland/mango.nix"], so nixpkgs'
  # own (module-only, no home-manager side) copy stays out of the way.
  programs.mango.enable = true;

  # Screen sharing. The flake's module points ScreenCast/Screenshot at
  # xdg-desktop-portal-wlr and mango does implement both capture protocols
  # (wlr-screencopy-v1 and ext-image-copy-capture-v1), but that is only half of
  # it: with two monitors the portal has to ASK which one to share, and its
  # default chooser shells out to whichever of wofi/rofi/bemenu/mew/fuzzel it
  # can find. This config installs none of them, so every share attempt died as
  #
  #   /bin/sh: line 1: wofi: command not found          (…and the other four)
  #   [ERROR] - wlroots: no output found
  #
  # and Zen's "Share screen" simply offered nothing. slurp is already here for
  # screenshots (./desktop.nix), and in `simple` mode the portal just wants a
  # command that prints an output name — which `slurp -o` does, by clicking the
  # monitor. -r keeps the selection snapped to whole outputs.
  #
  # Global rather than per-desktop because xdg.portal.wlr has no per-session
  # split; it is inert under niri, where screencasting goes to the gnome
  # backend instead (./niri.nix).
  xdg.portal.wlr.settings.screencast = {
    chooser_type = "simple";
    chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
  };

  # NOT set here: programs.mango.package. Its default is the flake's own build,
  # which is the one hm-modules.nix validates config.conf against (`mango -c … -p`
  # at build time). Pointing this at pkgs.mango from nixpkgs would validate
  # against one binary and run another.
  #
  # Note there is no mango.cachix.org: this compiles wlroots_0_20 + scenefx +
  # mango from source on the first rebuild that touches it.
}
