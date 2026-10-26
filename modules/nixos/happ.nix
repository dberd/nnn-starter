# Happ Desktop — GUI on top of real Xray-core, plus `happd`, a root daemon that
# runs Happ's bundled sing-box for TUN mode.
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

    nativeBuildInputs = with pkgs; [ dpkg autoPatchelfHook qt6.wrapQtAppsHook ];

    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libglvnd
      fontconfig
      freetype
      libx11
      libxcb
      xcb-util-cursor
      libgpg-error
      e2fsprogs
      qt6.qtbase
      qt6.qtwayland
    ];

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

  # 1. Выносим обёртку в отдельную переменную
  happ-wrapped = pkgs.writeShellScriptBin "happ" ''
    # Указываем, где искать разделяемые библиотеки (включая libxcb-cursor)
    export LD_LIBRARY_PATH="/opt/happ/lib:${pkgs.xcb-util-cursor}/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    
    # Указываем, где искать плагины Qt
    export QT_PLUGIN_PATH="/opt/happ/lib/plugins"
    export QT_QPA_PLATFORM_PLUGIN_PATH="/opt/happ/lib/plugins/platforms"
    
    # Принудительно используем XCB (X11/XWayland)
    export QT_QPA_PLATFORM=xcb

    exec /opt/happ/bin/Happ "$@"
  '';

  # 2. Теперь desktop-файл ссылается на обёртку, а не на сырой бинарник
  desktopItem = pkgs.makeDesktopItem {
    name = "happ";
    desktopName = "Happ";
    exec = "${happ-wrapped}/bin/happ %u"; # <-- Исправлено
    icon = "happ";
    categories = ["Network"];
    mimeTypes = ["application/x-happ" "x-scheme-handler/happ"];
  };
in {
  environment.systemPackages = [
    happ # icons + mime only
    desktopItem
    happ-wrapped # <-- Добавляем обёртку в PATH
  ];

  systemd.services.happd = {
    description = "Happ Process Control Daemon";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    restartTriggers = [happ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = install;
      ExecStart = "/opt/happ/bin/happd";
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