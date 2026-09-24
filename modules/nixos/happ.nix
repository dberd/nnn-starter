# Happ Desktop — GUI on top of real Xray-core, plus `happd`, a root daemon that
# runs Happ's bundled sing-box for TUN mode.
#
# Why Happ and not Throne: the vpn entry node is VLESS+REALITY, and Throne's
# ThroneCore is sing-box, whose REALITY client fails against it with
# "reality verification failed" (docs/proxy.md §6). Happ speaks VLESS through
# Xray-core itself and only uses sing-box for the TUN device.
#
# How it is laid out, and why it lives in /opt instead of the store:
#
#   The .deb is unpacked and autoPatchelf'ed into the store as usual. But the
#   GUI resolves its own directory with QCoreApplication::applicationDirPath()
#   (i.e. /proc/self/exe, symlinks resolved) and writes runtime geo files into
#   <that dir>/core/routing. A store path is read-only, so the tree is copied to
#   /opt/happ — the path upstream's own happd.service and .desktop hardcode —
#   and run from there. The copy is refreshed only when the store path changes.
#
#   happd is started by systemd (not by the GUI's pkexec fallback): the GUI
#   looks for an installed daemon, talks to it over /tmp/happd.sock, and the
#   daemon launches sing-box as root. That keeps NixOS' read-only /usr and
#   /usr/share/polkit-1 out of the picture.
{
  lib,
  pkgs,
  ...
}: let
  version = "4.3.0";

  happ = pkgs.stdenv.mkDerivation {
    pname = "happ-desktop";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/Happ-proxy/happ-desktop/releases/download/${version}/Happ.linux.x64.deb";
      hash = "sha256-QchsDK8YGQvOWKf2A/1GbJ4/v+8rhfg3Y1oEU0Aa/7o=";
    };

    nativeBuildInputs = with pkgs; [dpkg autoPatchelfHook];

    # What the bundled binaries and Qt libs NEED but the .deb does not ship
    # (computed from readelf over every dynamic ELF in 4.3.0). Qt, ICU, glib,
    # krb5, dbus, xkbcommon etc. come bundled in opt/happ/lib.
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib # libstdc++, libgcc_s
      zlib
      libglvnd # libEGL, libGL, libGLX, libOpenGL
      fontconfig
      freetype
      xorg.libX11 # libX11, libX11-xcb
      xorg.libxcb
      libgpg-error
      e2fsprogs # libcom_err (for the bundled krb5)
    ];

    # Pulled in only by the wl-shell/ivi-shell Wayland plugins, which niri and
    # mango never select (they use xdg-shell).
    autoPatchelfIgnoreMissingDeps = ["libQt6WlShellIntegration.so.6"];

    runtimeDependencies = [pkgs.openssl.out];

    dontConfigure = true;
    dontBuild = true;
    unpackPhase = "dpkg-deb -x $src .";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share
      cp -a opt/happ $out/happ
      cp -a usr/share/icons usr/share/mime $out/share/
      runHook postInstall
    '';

    meta = {
      description = "Happ — Xray-core proxy client";
      homepage = "https://www.happ.su";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  };

  # Copy the store tree to /opt/happ when (and only when) it changed.
  # core/routing is excluded from --delete: it holds the geo files Happ
  # downloaded at runtime, and wiping them on every rebuild would force a
  # re-download.
  install = pkgs.writeShellScript "happ-install" ''
    set -eu
    src=${happ}/happ
    dst=/opt/happ
    [ "$(cat "$dst/.nix-src" 2>/dev/null || true)" = "$src" ] && exit 0
    mkdir -p "$dst"
    ${pkgs.rsync}/bin/rsync -a --delete --chmod=Du+w,Fu+w \
      --exclude=/bin/core/routing/ --exclude=/.nix-src \
      "$src"/ "$dst"/
    echo "$src" > "$dst/.nix-src"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "happ";
    desktopName = "Happ";
    exec = "/opt/happ/bin/Happ %u";
    icon = "happ";
    categories = ["Network"];
    mimeTypes = ["application/x-happ" "x-scheme-handler/happ"];
  };
in {
  environment.systemPackages = [
    happ # icons + mime only; the binaries run from /opt/happ
    desktopItem
    (pkgs.writeShellScriptBin "happ" ''exec /opt/happ/bin/Happ "$@"'')
  ];

  systemd.services.happd = {
    description = "Happ Process Control Daemon";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    # A rebuild with a new version restarts the daemon, and ExecStartPre then
    # refreshes /opt/happ before the new happd comes up.
    restartTriggers = [happ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = install;
      ExecStart = "/opt/happ/bin/happd";
      # `always`: happd exits 0 on purpose when a newer client connects, so
      # systemd re-execs it (upstream unit, same reason).
      Restart = "always";
      RestartSec = "5s";
      TimeoutStopSec = "10s";
      KillMode = "mixed";
      StateDirectory = "happd"; # /var/lib/happd/state.db
    };
  };

  systemd.tmpfiles.rules = [
    # Written by the GUI, which runs as the user, not root.
    "d /opt/happ/bin/core/routing 2775 root users -"
    # happd shells out to /bin/rm, and the GUI's no-daemon fallback to
    # /usr/bin/pkexec; neither path exists on NixOS by default.
    "L+ /bin/rm - - - - ${pkgs.coreutils}/bin/rm"
    "L+ /usr/bin/pkexec - - - - /run/wrappers/bin/pkexec"
  ];
}
