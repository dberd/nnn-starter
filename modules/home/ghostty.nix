{
  config,
  lib,
  pkgs,
  ...
}: let
  c = config.lib.stylix.colors.withHashtag;

  # A stand-in for the theme file Noctalia writes at runtime, used only until it
  # has run once. See the activation script at the bottom for why it exists —
  # without it a fresh machine gets no desktop at all.
  #
  # The base16 -> ANSI mapping is the conventional one, so the seed and the file
  # Noctalia later writes describe the same palette.
  seedTheme = pkgs.writeText "ghostty-noctalia-seed" ''
    palette = 0=${c.base00}
    palette = 1=${c.base08}
    palette = 2=${c.base0B}
    palette = 3=${c.base0A}
    palette = 4=${c.base0D}
    palette = 5=${c.base0E}
    palette = 6=${c.base0C}
    palette = 7=${c.base05}
    palette = 8=${c.base03}
    palette = 9=${c.base08}
    palette = 10=${c.base0B}
    palette = 11=${c.base0A}
    palette = 12=${c.base0D}
    palette = 13=${c.base0E}
    palette = 14=${c.base0C}
    palette = 15=${c.base07}
    background = ${c.base00}
    foreground = ${c.base05}
    cursor-color = ${c.base05}
    selection-background = ${c.base02}
    selection-foreground = ${c.base05}
  '';
in {
  # Colour comes from Noctalia, not Stylix: it templates ghostty from the live
  # palette (see theme.templates in modules/home/noctalia.nix), so the terminal
  # follows a theme switch at runtime. Stylix writes into the store at build
  # time and cannot.
  #
  # Noctalia's apply.sh wants to append `theme = noctalia` to this config, but
  # the file is a store symlink it cannot edit — so the line is set here and the
  # script finds it already correct.
  stylix.targets.ghostty.enable = false;

  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;

    # Font still comes from Stylix; colour comes from Noctalia's template.
    settings = {
      # Set by us now that Stylix no longer writes this file.
      theme = "noctalia";
      # Fully opaque: the 0.95 Stylix used made the desktop show through, which
      # read as the terminal blurring when it lost focus.
      background-opacity = 1.0;

      window-padding-x = 12;
      window-padding-y = 12;
      window-decoration = false;
      cursor-style = "block";
      cursor-style-blink = false;
      mouse-hide-while-typing = true;
      copy-on-select = "clipboard";
      confirm-close-surface = false;
      window-inherit-working-directory = true;

      # Every default bind with a letter in it is matched by the codepoint the
      # key produces, so on the ru layout ctrl+shift+v arrives as ctrl+shift+м
      # and matches nothing — paste, copy and the rest all die there.
      #
      # W3C physical key codes match the key by position regardless of layout,
      # and ghostty gives them priority over codepoints, so re-binding the same
      # actions to key_* fixes ru without changing anything on us. The defaults
      # stay in place underneath; these simply win.
      keybind = [
        "ctrl+shift+key_c=copy_to_clipboard:mixed"
        "ctrl+shift+key_v=paste_from_clipboard"
        "ctrl+shift+key_a=select_all"
        "ctrl+shift+key_n=new_window"
        "ctrl+shift+key_t=new_tab"
        "ctrl+shift+key_w=close_tab:this"
        "ctrl+shift+key_q=quit"
        "ctrl+shift+key_o=new_split:right"
        "ctrl+shift+key_e=new_split:down"
        "ctrl+shift+key_f=start_search"
        "ctrl+shift+key_i=inspector:toggle"
        "ctrl+shift+key_p=toggle_command_palette"
        "ctrl+shift+key_j=write_screen_file:paste,plain"
        "super+ctrl+shift+key_j=write_screen_file:copy,plain"
        "ctrl+alt+shift+key_j=write_screen_file:open,plain"
      ];
    };
  };

  # Make ghostty the terminal GLib reaches for when an app asks for one, i.e.
  # any .desktop with Terminal=true and Nautilus' "Run as Program" on scripts.
  # GLib does not read a setting for this — it walks a hardcoded list of binary
  # names (xdg-terminal-exec, kgx, gnome-terminal, mate-terminal,
  # xfce4-terminal, io.elementary.terminal, tilix, konsole, xterm and a few
  # relics) and takes the first one on PATH. ghostty is not on that list and
  # none of the others are installed, so every such launch failed outright with
  # "Unable to find terminal required for application".
  #
  # xdg-terminal-exec is first in that list and is the spec-blessed indirection:
  # it resolves the terminal from xdg-terminals.list, which we point at ghostty.
  # Installing it fixes the whole class of launches rather than this one script.
  # Unrelated to nautilus-open-any-terminal in modules/home/apps.nix — that
  # extension has its own dconf setting and does not go through GLib.
  xdg.terminal-exec = {
    enable = true;
    settings.default = ["com.mitchellh.ghostty.desktop"];
  };

  # Seed the theme file Noctalia owns, but only if it is not there yet.
  #
  # `theme = "noctalia"` above names ~/.config/ghostty/themes/noctalia, which
  # the RUNNING shell writes from its live palette. On a machine that has never
  # run Noctalia the file does not exist — and home-manager validates the
  # ghostty config with `ghostty +validate-config` as an onChange hook, so
  # activation fails at the onFilesChange step and every step after it is
  # skipped. One of those steps writes ~/.config/niri/config.kdl, so niri comes
  # up with no configuration and refuses to start.
  #
  # That is exactly how the T480s' first boot went: a missing terminal theme
  # presented as a dead compositor, with nothing pointing at the real cause.
  #
  # The file has to be a real copy rather than home.file, which would make it a
  # /nix/store symlink that Noctalia cannot overwrite. `-e` rather than `-f` so
  # a symlink left by an older generation counts as present and is not clobbered.
  home.activation.ghosttyThemeSeed = lib.hm.dag.entryBefore ["onFilesChange"] ''
    theme="${config.xdg.configHome}/ghostty/themes/noctalia"
    if [ ! -e "$theme" ]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$theme")"
      $DRY_RUN_CMD install -m644 ${seedTheme} "$theme"
    fi
  '';
}
