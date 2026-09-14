{
  config,
  local,
  lib,
  pkgs,
  ...
}: let
  # Colours come from Stylix, the same source niri's focus-ring uses. Mango
  # wants 0xRRGGBBAA; `config.lib.stylix.colors.<baseNN>` is bare "rrggbb"
  # (the `withHashtag` variant used in ./niri.nix would prepend a "#" that
  # mango's parser does not take).
  #
  # These are the BUILD-time palette, and they are deliberately the fallback
  # rather than the final word: the `mango` template in ./noctalia.nix rewrites
  # the same keys into ~/.config/mango/noctalia.conf at runtime, which the
  # `source=` line at the bottom of this file pulls in afterwards. Last
  # assignment wins in mango, so a palette switch in the Noctalia GUI moves
  # these without a rebuild — the thing niri-stable cannot do.
  c = n: "0x${config.lib.stylix.colors.${n}}ff";

  # Per-output geometry out of hosts/<host>/local.nix — the same attrset that
  # feeds programs.niri.settings.outputs, so a monitor swap still only has to be
  # described once. `name` is a regex in mango, hence the ^…$ anchors.
  #
  # Nix renders floats as "74.968000" / "1.200000"; mango parses those with
  # strtof and is happy. `focus-at-startup` from the niri side has no monitorrule
  # counterpart and is dropped.
  monitorrule =
    lib.mapAttrsToList (
      name: m:
        lib.concatStringsSep "," [
          "name:^${name}$"
          "width:${toString m.mode.width}"
          "height:${toString m.mode.height}"
          "refresh:${toString m.mode.refresh}"
          "x:${toString m.position.x}"
          "y:${toString m.position.y}"
          "scale:${toString m.scale}"
        ]
    )
    local.monitors;

  # Tag binds, 1..9. mango's tags are not niri's dynamic workspaces: `view`
  # switches to a tag, `tag` throws the focused window at one. The trailing 0
  # is the "don't also focus that tag" argument.
  tagBinds =
    lib.concatMap (n: [
      "SUPER,${toString n},view,${toString n},0"
      "SUPER+SHIFT,${toString n},tag,${toString n},0"
    ])
    (lib.range 1 9);

  noctalia = "${pkgs.noctalia}/bin/noctalia";

  # niri had a hotkey overlay built in (Mod+Shift+Slash). mango has none, and
  # `mmsg` cannot list binds either — the only authoritative record is
  # config.conf itself. So rather than hand-maintain a second copy that would
  # drift, this reads the generated file back at RUNTIME and formats it. It
  # therefore also picks up anything sourced from noctalia.conf, and it cannot
  # disagree with what the compositor actually has bound.
  #
  # The sed strips /nix/store/<hash>- prefixes (with or without a trailing
  # /bin/) so spawn lines read as `noctalia msg …` rather than 60 characters of
  # hash. Non-`bind` directives keep their kind in the first column, because
  # otherwise an axisbind's UP/DOWN reads as the arrow keys rather than a wheel.
  keysCheatsheet = pkgs.writeShellScript "mango-keys" ''
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/mango/config.conf"
    {
      printf '\n  MANGO KEYBINDINGS\n  %s\n\n' "$conf"
      ${pkgs.gawk}/bin/awk '
        /^[[:space:]]*(bind|bindl|bindr|bindc|bindp|binds|mousebind|axisbind|gesturebind)[[:space:]]*=/ {
          kind = $0
          sub(/[[:space:]]*=.*$/, "", kind)
          sub(/^[[:space:]]+/, "", kind)
          val = substr($0, index($0, "=") + 1)
          sub(/^[[:space:]]+/, "", val)
          sub(/[[:space:]]+$/, "", val)
          n = split(val, f, ",")
          mods = f[1]; key = f[2]
          dispatch = (n >= 3 ? f[3] : "")
          args = ""
          for (i = 4; i <= n; i++) args = args (i > 4 ? "," : "") f[i]
          gsub(/\+/, " + ", mods)
          combo = (tolower(mods) == "none" ? "" : mods " + ") key
          tag = (kind == "bind" ? "" : "[" kind "] ")
          printf "  %-30s %-22s %s\n", tag combo, dispatch, args
        }
      ' "$conf" | ${pkgs.gnused}/bin/sed -E 's#/nix/store/[a-z0-9]{32}-[^ ]*/bin/##g; s#/nix/store/[a-z0-9]{32}-##g'
      printf '\n'
    } | ${pkgs.less}/bin/less -R
  '';

  # Its own app-id so the window rule below can float it at a readable size.
  # --gtk-single-instance=false matters: ghostty otherwise hands the command to
  # the already-running instance, which ignores --class and opens a normal tab.
  keysClass = "com.mango.Keys";
in {
  # MangoWC as a second session next to niri. The system half is
  # modules/nixos/mango.nix; this is the part that shapes the session itself.
  #
  # Read this against ./niri.nix — it is a port of that file, not an independent
  # config, and the two are meant to feel the same under the fingers. Where a
  # niri concept has no mango counterpart the bind is dropped rather than
  # rehomed, and said so below.
  wayland.windowManager.mango = {
    enable = true;

    # Writes ~/.config/mango/autostart.sh and, crucially,
    # dbus-update-activation-environment + `systemctl --user start
    # mango-session.target`, which BindsTo graphical-session.target. That is the
    # whole reason Noctalia needs no changes: its unit is WantedBy
    # graphical-session.target, not niri.service, so it comes up here by itself.
    systemd.enable = true;

    settings = {
      inherit monitorrule;

      # ---- input ------------------------------------------------------------
      # Same two layouts and the same Alt+Shift toggle as niri. Note mango
      # matches binds by KEYCODE, not keysym, so the whole set below keeps
      # working while the Russian layout is active.
      xkb_rules_layout = "us,ru";
      xkb_rules_options = "grp:alt_shift_toggle";

      # niri: focus-follows-mouse.enable = false, warp-mouse-to-focus = true.
      sloppyfocus = 0;
      warpcursor = 1;

      # niri: touchpad tap/natural-scroll/dwt on, mouse flat accel and a
      # conventional wheel direction. accel_profile 1 is flat.
      tap_to_click = 1;
      tap_and_drag = 1;
      trackpad_natural_scrolling = 1;
      trackpad_disable_while_typing = 1;
      mouse_natural_scrolling = 0;
      mouse_accel_profile = 1;

      # ---- layout -----------------------------------------------------------
      # niri's `gaps = 12`, inner and outer alike.
      gappih = 12;
      gappiv = 12;
      gappoh = 12;
      gappov = 12;

      # niri draws a 2px focus ring and no border; mango has one border that
      # changes colour with focus, so the ring width becomes the border width
      # and the unfocused colour goes to a muted base rather than transparent
      # (mango paints the border either way).
      borderpx = 2;
      focuscolor = c "base0D";
      bordercolor = c "base03";
      rootcolor = c "base00";
      urgentcolor = c "base08";
      border_radius = 6;

      # Nine tags to match the nine Mod+<n> binds below.
      tag_num = 9;
      smartgaps = 0;

      # Closest thing to the niri habit: `scroller` is mango's column layout.
      # Every tag starts there; Mod+N cycles to tile/grid/monocle per tag.
      tagrule = map (n: "id:${toString n},layout_name:scroller") (lib.range 1 9);
      scroller_default_proportion = 0.5;
      scroller_proportion_preset = "0.33,0.5,0.67";

      # Zero, not the stock 20. Upstream describes this as "width reserved on
      # sides when window ratio is 1" — a peek strip so the neighbouring column
      # stays visible even at full width. niri has no such thing: a column at
      # 100% covers the working area exactly, and so does mango's own Mod+F
      # (togglemaximizescreen fills mon.w minus gappoh/gappov and nothing else).
      #
      # Leaving it at 20 is why the windows carrying `scroller_proportion:1.0`
      # below came up ~14px short on each side of what Mod+F produces: the
      # scroller sizes columns against `m.w.width - 2*scroller_structs - gappih`
      # rather than against the full working area.
      scroller_structs = 0;

      # ---- effects ----------------------------------------------------------
      # Straight out of Noctalia's own mango page. The two zeroes are the point:
      # mango's SceneFX blur and shadows on LAYER surfaces ignore surface
      # opacity, so a translucent Noctalia bar or panel gets blurred/shadowed as
      # if it were opaque. Windows keep both; the shell draws its own.
      blur = 1;
      blur_layer = 0;
      blur_optimized = 1;
      blur_params_num_passes = 2;
      blur_params_radius = 5;
      shadows = 1;
      layer_shadows = 0;
      shadow_only_floating = 0;
      shadows_size = 4;
      shadows_blur = 12;

      # Windows animate; layer surfaces do not (same reason as layer_shadows).
      # niri's equivalent was `animations.slowdown = 0.7` — a single multiplier
      # over its own defaults — so these durations are the same intent spelled
      # out per phase: quick enough not to be waited on, slow enough to show
      # where a window came from. Types are slide/zoom/fade/none, and every
      # phase also takes its own `animation_curve_*` bezier if the feel needs
      # tuning rather than the timing.
      animations = 1;
      layer_animations = 0;
      animation_type_open = "zoom";
      animation_type_close = "fade";
      zoom_initial_ratio = 0.8;
      animation_duration_open = 250;
      animation_duration_close = 200;
      animation_duration_move = 300;
      animation_duration_tag = 250;

      # ---- overview (Mod+D) -------------------------------------------------
      # Gaps inside the overview grid, independent of the normal layout gaps
      # above. Left at defaults otherwise: `enable_hotarea` (trigger by shoving
      # the cursor into a screen corner, `hotarea_corner` picks which) stays off
      # because sloppyfocus is off too — this desktop does not act on the
      # pointer merely being somewhere.
      overviewgappi = 8;
      overviewgappo = 24;

      # ---- window rules -----------------------------------------------------
      # Ported from window-rules in ./niri.nix, and like niri's, LATER RULES
      # OVERRIDE EARLIER ONES for the same window (verified in mango's
      # apply_rule_properties loop) — which is what lets the broad rule come
      # first and the exception second, rather than needing niri's `excludes`.
      #
      # The one niri concept with no direct spelling is `open-maximized`, which
      # in a scrolling layout means "this column takes the full width". mango's
      # scroller has exactly that as a per-window property, so those rules
      # survive as `scroller_proportion:1.0` instead of disappearing.
      windowrule = [
        # Steam's main window gets the full column; everything else it opens
        # (Friends, the overlay, download toasts) is a companion window that
        # should not take a column at all. Where niri used matches+excludes,
        # here the title is a PCRE negative lookahead — mango matches with
        # pcre2, so this is a real exclusion and not an approximation.
        "scroller_proportion:1.0,appid:^steam$,title:^Steam$"
        "isfloating:1,appid:^steam$,title:^(?!Steam$).*"

        # gamescope's nested window. gaming.nix already passes -f, so what this
        # adds is WHICH output it lands on: without it the game opens wherever
        # focus happened to be when Steam launched the title, which is usually
        # the small panel. Both app-id and title are literally "gamescope".
        "monitor:${local.gameOutput.name},isfullscreen:1,appid:^gamescope$"

        # Browser, editor and DB client are "one big document" apps: full column
        # rather than the half-width default. app-ids are what the windows
        # actually report, not what their .desktop StartupWMClass claims —
        # VSCodium says "vscodium" there but "codium" on the window, and DBeaver
        # arrives through XWayland keeping its capital B.
        "scroller_proportion:1.0,appid:^(zen-beta|codium|DBeaver)$"

        # …except Picture-in-Picture, which matches the zen-beta rule above and
        # is a video overlay, not a document. Second, so it wins.
        "isfloating:1,width:480,height:270,appid:^zen-beta$,title:^Picture-in-Picture$"

        # Nautilus is a file manager, not a document: a window you summon on top
        # of what you were doing and dismiss again, like Finder. This first rule
        # is the baseline every Nautilus window starts from — 480x710, which is
        # what the auxiliary toplevels (the D-Bus Properties sheet among them)
        # keep, since they carry no title of their own and GTK names them after
        # the app id.
        "isfloating:1,width:480,height:710,appid:^org\\.gnome\\.Nautilus$"

        # The file manager window proper — anything with a real title, i.e. a
        # folder name. 1200x760 fits inside both outputs with room for the bar.
        "isfloating:1,width:1200,height:760,appid:^org\\.gnome\\.Nautilus$,title:^(?!org\\.gnome\\.Nautilus$).*"

        # File Roller is what a double-click on an archive opens (xdg-mime hands
        # it zip/tar/7z/gzip, see ./apps.nix). Same floating treatment one size
        # down: an archive listing is a column of names, not a two-pane browser.
        "isfloating:1,width:900,height:600,appid:^org\\.gnome\\.FileRoller$"

        # The keybinding cheat sheet (Mod+Shift+Slash). Floating and fixed-size
        # so it reads as a sheet over the session rather than stealing a column.
        "isfloating:1,width:1000,height:720,appid:^${lib.escapeRegex keysClass}$"
      ];

      # ---- binds ------------------------------------------------------------
      bind =
        [
          # Launchers — identical to niri.
          "SUPER,Return,spawn,ghostty"
          "SUPER,T,spawn,ghostty"
          "SUPER,B,spawn,zen-beta"
          "SUPER,E,spawn,nautilus"

          # Noctalia panels. Same ids and same keys as ./niri.nix; this is the
          # half of the config that ports over untouched, because it is IPC into
          # the shell rather than anything the compositor knows about.
          "SUPER,space,spawn,${noctalia} msg panel-toggle launcher"
          "SUPER,V,spawn,${noctalia} msg panel-toggle clipboard"
          "SUPER,Y,spawn,${noctalia} msg panel-toggle wallpaper"
          "SUPER,comma,spawn,${noctalia} msg panel-toggle control-center"
          "SUPER,X,spawn,${noctalia} msg panel-toggle session"
          "SUPER+ALT,L,spawn,${noctalia} msg session lock"

          # Window management. niri's Mod+W (tabbed column) has no mango
          # counterpart and is not rebound.
          "SUPER,Q,killclient"
          "SUPER,F,togglemaximizescreen"
          "SUPER+SHIFT,F,togglefullscreen"
          "SUPER+SHIFT,T,togglefloating"
          "SUPER,N,switch_layout"

          # Seeing what is open, three ways — niri had one (the overview) plus
          # its own Mod+Tab switcher, and this keeps both plus the jump labels.
          #   Mod+D        overview of every tag on this monitor
          #   Mod+Shift+D  overview of the current tagset only
          #   Mod+Tab      thumbnail switcher, all tags on this monitor;
          #                releasing Mod selects. all_next/all_prev would widen
          #                it to every monitor, next/prev narrow it to one tag.
          #   Mod+grave    jump labels — a letter is drawn on each window and
          #                pressing it focuses that one.
          # In the overview itself: left click focuses a window, right click
          # closes it.
          "SUPER,D,toggleoverview"
          "SUPER+SHIFT,D,toggleoverview,1"
          "SUPER,Tab,switcher,all_tag_next"
          "SUPER,grave,togglejump"

          # The cheat sheet this file generates — mango has no hotkey overlay of
          # its own, so Mod+Shift+Slash keeps the niri muscle memory pointed at
          # a formatted dump of config.conf instead.
          "SUPER+SHIFT,slash,spawn,ghostty --gtk-single-instance=false --class=${keysClass} -e ${keysCheatsheet}"

          # Focus, hjkl and arrows alike — both stay inside the tag.
          "SUPER,H,focusdir,left"
          "SUPER,L,focusdir,right"
          "SUPER,J,focusdir,down"
          "SUPER,K,focusdir,up"
          "SUPER,Left,focusdir,left"
          "SUPER,Right,focusdir,right"
          "SUPER,Up,focusdir,up"
          "SUPER,Down,focusdir,down"
          "ALT,Tab,focuslast"

          # Ctrl crosses monitors.
          "SUPER+CTRL,Left,focusmon,left"
          "SUPER+CTRL,Right,focusmon,right"
          "SUPER+CTRL,H,focusmon,left"
          "SUPER+CTRL,L,focusmon,right"
          "SUPER+CTRL,J,focusmon,down"
          "SUPER+CTRL,K,focusmon,up"

          # Move within the tag.
          "SUPER+SHIFT,H,exchange_client,left"
          "SUPER+SHIFT,L,exchange_client,right"
          "SUPER+SHIFT,J,exchange_client,down"
          "SUPER+SHIFT,K,exchange_client,up"
          "SUPER+SHIFT,Left,exchange_client,left"
          "SUPER+SHIFT,Right,exchange_client,right"
          "SUPER+SHIFT,Down,exchange_client,down"
          "SUPER+SHIFT,Up,exchange_client,up"

          # Move to another monitor.
          "SUPER+CTRL+SHIFT,Left,tagmon,left"
          "SUPER+CTRL+SHIFT,Right,tagmon,right"
          "SUPER+CTRL+SHIFT,H,tagmon,left"
          "SUPER+CTRL+SHIFT,L,tagmon,right"

          # Sizing. niri's preset column widths become the scroller presets.
          "SUPER,R,switch_proportion_preset"
          "SUPER,minus,setmfact,-0.05"
          "SUPER,equal,setmfact,+0.05"
          "SUPER+CTRL,F,set_proportion,1.0"

          # Tag navigation on i/u, mirroring niri's workspace up/down.
          "SUPER,I,viewtoleft_have_client,0"
          "SUPER,U,viewtoright_have_client,0"
          "SUPER+CTRL,I,tagtoleft,0"
          "SUPER+CTRL,U,tagtoright,0"

          # Gaps.
          "SUPER+SHIFT,equal,incgaps,1"
          "SUPER+SHIFT,minus,incgaps,-1"

          # Screenshots. niri had these built in; mango does not, so they go
          # through Noctalia — which also means they land in the directory and
          # under the filename pattern configured in ./noctalia.nix.
          "NONE,Print,spawn,${noctalia} msg screenshot-region"
          "CTRL,Print,spawn,${noctalia} msg screenshot-fullscreen"

          # Session.
          "SUPER,P,reload_config"
          "SUPER+SHIFT,E,quit"

          # Media and brightness go through Noctalia rather than
          # wpctl/brightnessctl: it draws the OSD, and its brightness path
          # drives the external panels over DDC/CI.
          "NONE,XF86AudioRaiseVolume,spawn,${noctalia} msg volume-up"
          "NONE,XF86AudioLowerVolume,spawn,${noctalia} msg volume-down"
          "NONE,XF86AudioMute,spawn,${noctalia} msg volume-mute"
          "NONE,XF86AudioMicMute,spawn,${noctalia} msg mic-mute"
          "NONE,XF86AudioPlay,spawn,${noctalia} msg media toggle"
          "NONE,XF86AudioNext,spawn,${noctalia} msg media next"
          "NONE,XF86AudioPrev,spawn,${noctalia} msg media previous"
          "NONE,XF86MonBrightnessUp,spawn,${noctalia} msg brightness-up"
          "NONE,XF86MonBrightnessDown,spawn,${noctalia} msg brightness-down"
        ]
        ++ tagBinds;

      # Dragging floating windows with the pointer. mango ships NO mousebind
      # defaults — without these three, a floating window can only be moved and
      # resized from the keyboard, which is why Nautilus and the PiP window
      # appeared to be nailed down. `curmove`/`curresize` mean "act on whatever
      # is under the cursor"; the modifier is Super so the drag never competes
      # with what the application itself does with a plain click.
      mousebind = [
        "SUPER,btn_left,moveresize,curmove"
        "SUPER,btn_right,moveresize,curresize"
        "SUPER,btn_middle,togglefloating"
      ];

      # …and the same drag on a TILED window, which is niri's Mod+drag. mango
      # picks a tiled window up either way — it floats it mid-drag — but without
      # this it has nowhere to put it back, so on release `apply_window_snap`
      # runs and the window simply stays floating. With it on, the drop target
      # is highlighted while dragging and releasing re-inserts the window there.
      #
      # Caveat worth knowing: a window that is fullscreen or in Mod+F
      # maximize-screen state refuses to be grabbed at all (mango bails before
      # it ever looks at the mouse binding). Mod+F it back to normal first.
      drag_tile_to_tile = 1;
      # Shrink the window to a 300x300 puck while it is being dragged, so the
      # drop target underneath stays visible. mango's default, restated because
      # it only takes effect together with the line above.
      drag_tile_small = 1;

      # Snap floating windows to screen edges and to each other while dragging.
      # Off by default in mango; with the pointer now able to move them, it is
      # what makes dropping one against an edge land cleanly.
      enable_floating_snap = 1;
      snap_distance = 20;

      # niri's Mod+wheel over workspaces.
      axisbind = [
        "SUPER,UP,viewtoleft_have_client"
        "SUPER,DOWN,viewtoright_have_client"
      ];
    };

    # exec-once'd by the module. Two things niri got from elsewhere and mango
    # does not:
    #
    #   ddcutil   — the HDMI panel (MSI MP241X, DDC display 1) comes up at 90%
    #               on its own; this is the same push spawn-at-startup does in
    #               ./niri.nix.
    #   polkit    — niri-flake ships niri-flake-polkit.service, but its
    #               [Install] section is WantedBy=niri.service, so under mango
    #               nothing would answer a pkexec prompt. Same agent binary,
    #               started by hand. (Noctalia has its own agent behind
    #               shell.polkit_agent, deliberately left off in ./noctalia.nix
    #               because that setting is shared with the niri session, where
    #               it would be the second agent.)
    autostart_sh = ''
      ${pkgs.ddcutil}/bin/ddcutil setvcp 10 100 --display 1 &
      ${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1 &
    '';

    # Appended after `settings`, so it wins — which is the point: this is the
    # live palette from Noctalia's `mango` template (see theme.templates in
    # ./noctalia.nix) overriding the build-time Stylix colours above.
    #
    # Two things worth knowing about this one line:
    #
    #  * It must be spelled `source=` and not `source-optional=`. Noctalia's
    #    apply.sh only appends an include line when
    #    `grep '^[[:space:]]*source[[:space:]]*=.*noctalia\.conf'` finds nothing
    #    — and appending is exactly what must not happen here, because
    #    home-manager makes config.conf a read-only /nix/store symlink and the
    #    write would fail the hook before it reaches `mmsg dispatch
    #    reload_config`. `source-optional=` does not match that regex.
    #  * The home.activation below seeds the file so the reference resolves.
    #    Even unseeded this is not fatal — verified against both the nightly
    #    the flake builds and nixpkgs' 0.16.1: a missing `source=` target logs a
    #    red "Failed to open config file", but `mango -c … -p` still exits 0, so
    #    neither the build-time validation the module runs nor the compositor
    #    itself falls over. Do not go chasing that line in the build log.
    extraConfig = ''
      source=~/.config/mango/noctalia.conf
    '';
  };

  # Seed the file the `source=` above points at, so a fresh machine has it
  # before Noctalia's template ever runs. Not managed by xdg.configFile on
  # purpose: Noctalia rewrites this file on every palette change and cannot
  # write through a store symlink. Same shape as seedWallpapers in ./noctalia.nix.
  home.activation.seedMangoNoctaliaConf = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run mkdir -p "$HOME/.config/mango"
    [ -e "$HOME/.config/mango/noctalia.conf" ] || run touch "$HOME/.config/mango/noctalia.conf"
  '';
}
