{
  pkgs,
  inputs,
  ...
}: {
  imports = [inputs.zen-browser.homeModules.beta];

  # GUI desktop apps. Browsers and file managers live here rather than in the
  # CLI bundle.
  home.packages = with pkgs; [
    # Nautilus (GNOME Files): a sensible GTK file manager. Pairs with the gvfs
    # service enabled in modules/nixos/desktop.nix for trash + mounting, and is
    # also what the gnome xdg portal uses as the system file picker (see
    # modules/nixos/niri.nix).
    nautilus
    # "Open in Terminal" from Nautilus; pointed at ghostty via dconf below.
    nautilus-open-any-terminal
    # Archive handling for Nautilus' Extract/Compress menu items. gnome-autoar
    # (a nautilus dependency) drives libarchive; these add the GUI and the
    # formats libarchive alone doesn't cover.
    file-roller
    p7zip
    unzip
    unar # free RAR extractor — avoids the unfree `unrar`
    xz
    zstd

    # ── Browsers ────────────────────────────────────────────────────────────
    # Zen (below) stays the default; these are the alternates.
    librewolf
    ungoogled-chromium

    # ── Communication ───────────────────────────────────────────────────────
    telegram-desktop
    element-desktop
    thunderbird

    # ── Documents / notes / media ───────────────────────────────────────────
    onlyoffice-desktopeditors
    # Notes: TriliumNext. Replaces logseq, whose nixpkgs package is frozen on
    # the old file-based 0.10.x line and pinned to an EOL Electron (39.8.10).
    # Trilium's own sync server is free and packaged too — `services.trilium-server`
    # can host it declaratively once the second machine (T480s) exists.
    trilium-desktop
    pinta # simple raster image editor
    spotify # official client (unfree)
    spotify-player # TUI client; needs a Premium account to stream

    # ── Editors / transfer / misc ───────────────────────────────────────────
    vscodium # default GUI editor, see modules/home/zed.nix
    qbittorrent
    localsend # ports opened in modules/nixos/networking.nix
    cava # audio visualizer
  ];

  # Nautilus' "Open in Terminal" entry — the extension defaults to gnome-terminal.
  dconf.settings."com/github/stunkymonkey/nautilus-open-any-terminal" = {
    terminal = "ghostty";
  };

  # Folders open in Nautilus (the portal file picker relies on this too).
  xdg.mimeApps.defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";

  # The snx-rs package builds its GTK tray app (gtk4 + kstatusnotifieritem are
  # in its buildInputs) but ships no .desktop file — cargo doesn't install one
  # and nixpkgs' package.nix has no postInstall for it. Without this the VPN
  # client simply doesn't appear in the app list.
  xdg.desktopEntries.snx-rs-gui = {
    name = "SNX-RS VPN";
    genericName = "VPN Client";
    comment = "Check Point VPN client";
    exec = "snx-rs-gui";
    icon = "network-vpn";
    terminal = false;
    type = "Application";
    categories = ["Network" "Security"];
  };

  # Zen browser — Firefox-based, from the community flake (beta channel).
  # Managed through the flake's home-manager module (rather than just dropping
  # the package in home.packages) so that:
  #   1. `setAsDefaultBrowser` registers the xdg mime associations for
  #      http(s)/html and exports $BROWSER=zen-beta (used by gh, git, etc.).
  #   2. Stylix's zen-browser target can theme its profile (see below).
  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
  };

  # Paint Zen's chrome + about:/newtab pages with the same Kanagawa base16
  # palette Stylix uses everywhere else. The target writes userChrome.css and
  # userContent.css into the named profile and flips on the
  # `toolkit.legacyUserProfileCustomizations.stylesheets` pref for us.
  stylix.targets.zen-browser.profileNames = ["default"];
}
