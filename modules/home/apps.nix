{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.zen-browser.homeModules.beta
    inputs.helium-browser.homeModules.default
  ];

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
    # Zen (below) is the daily driver. Helium (below, Blink) is the second
    # main browser rather than a fallback — librewolf held that "second
    # Firefox-family browser" slot and was dropped 23.08 for never being
    # configured. ungoogled-chromium is kept separately, specifically for
    # testing (a plain, un-skinned Blink with no profile/extensions of its
    # own to interfere).
    ungoogled-chromium

    # ── Communication ───────────────────────────────────────────────────────
    telegram-desktop
    element-desktop
    thunderbird

    # ── Documents / notes / media ───────────────────────────────────────────
    onlyoffice-desktopeditors
    # No dedicated notes app: the vaults are plain markdown in git
    # (github.com/dberd/{EFKO,LongBoiPersonal}), edited in VSCodium. That is why
    # TriliumNext was dropped — it keeps notes in its own database rather than in
    # files, so nothing outside Trilium could read them.
    pinta # simple raster image editor
    spotify # official client (unfree)
    spotify-player # TUI client; needs a Premium account to stream

    # ── Editors / transfer / misc ───────────────────────────────────────────
    vscodium # default GUI editor, see modules/home/mime.nix
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

    # Zen's own sync account still lists ten add-ons; the profile itself lost
    # every one of them on 21.08.2026 — weave/addonsreconciler.json flipped the
    # lot to installed=false that morning, and extensions/ has held nothing but
    # uBlock since. The previous version of this block declared "exactly one
    # add-on" because that is what the profile honestly contained by then.
    #
    # Five of the ten are packaged, so Nix reinstates them below (alongside
    # uBlock, which never went anywhere) and keeps them current.
    # Absent from firefox-addons and still to be reinstalled by hand (or by
    # turning add-on sync back on): Browsec VPN, AudD Music Recognition,
    # YouTube Anti Translate, Postman Interceptor, Email Sent Dark Souls style.
    #
    # Only presence is Nix's business — filter lists, vaults and allowlists stay
    # profile state, exactly like logins and history.
    # DuckDuckGo everywhere, including private windows. `force` is not optional:
    # Zen replaces the search-config symlink on every launch, so without it the
    # setting is undone the first time the browser starts. The cost is that this
    # file becomes ours outright — any engine or keyword shortcut added by hand
    # in the UI is replaced, not merged. "ddg" is an engine id, not a name; the
    # full table is engineNameToId in home-manager's
    # modules/programs/firefox/profiles/search.nix.
    profiles.default.search = {
      force = true;
      default = "ddg";
      privateDefault = "ddg";
      order = ["ddg" "google"];
    };

    profiles.default.extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
      ublock-origin
      sponsorblock
      bitwarden
      privacy-badger
      return-youtube-dislikes
      pwas-for-firefox
    ];
  };

  # Paint Zen's chrome + about:/newtab pages with the same Kanagawa base16
  # palette Stylix uses everywhere else. The target writes userChrome.css and
  # userContent.css into the named profile and flips on the
  # `toolkit.legacyUserProfileCustomizations.stylesheets` pref for us.
  stylix.targets.zen-browser.profileNames = ["default"];

  # Helium — Blink-based second main browser. Not in nixpkgs (upstream ships
  # only a .deb); the community flake wraps that same .deb, same trust level
  # as zen-browser above.
  programs.helium.enable = true;

  # ЕКП Диалог — the corporate web app, found on the CachyOS disk (23.08,
  # ~/.local/share/applications/chrome-hdfohkpjjbepbloichpkklcenleblnjo-Default.desktop)
  # and reproduced exactly: same flags, same isolated profile dir. The
  # disable-features pair lifts Chromium's Local Network Access checks —
  # dialog.efko.ru pulls from a private-network address, which a stock
  # Chromium blocks outright — not anything proxy-related. Previously
  # approximated with ungoogled-chromium; now that real Helium exists there's
  # no need to approximate.
  xdg.desktopEntries.ekp-dialog = {
    name = "ЕКП Диалог";
    genericName = "Corporate web app";
    exec = "${config.programs.helium.package}/bin/helium --user-data-dir=${config.home.homeDirectory}/.local/share/helium-ekp-dialog --disable-features=LocalNetworkAccessChecks,LocalNetworkAccessChecksWebSockets --app=https://dialog.efko.ru";
    icon = "web-browser";
    terminal = false;
    type = "Application";
    categories = ["Network"];
    # Noctalia's launcher search matched the transliterated "ekp" but not the
    # actual Cyrillic "екп" against the uppercase "ЕКП" in Name — looks like
    # its fuzzy match lowercases ASCII only. Keywords sidesteps it rather than
    # depending on a fix upstream.
    settings.Keywords = "ekp;dialog;efko;екп;диалог;";
  };
}
