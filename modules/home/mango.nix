{
  config,
  inputs,
  local,
  lib,
  pkgs,
  ...
}: let
  # Upstream's own assets/config.conf, straight out of the locked input. It stays
  # the source of everything this file does not have an opinion about: effects
  # defaults, gestures, mouse bindings, scratchpad, dwindle knobs. Reading it
  # from the input rather than vendoring a copy means it moves with the flake.
  stock = builtins.readFile "${inputs.mango}/assets/config.conf";

  # …except the keybinds, which are replaced wholesale. Keeping both sets would
  # mean two ways to do everything and a cheat sheet nobody can read, so every
  # `bind…=` line is dropped here and the niri set is supplied below. Note the
  # filter deliberately does NOT touch mousebind/axisbind/gesturebind — those
  # are upstream's and fine.
  stockWithoutBinds =
    lib.concatStringsSep "\n"
    (lib.filter
      (l: builtins.match "^[[:space:]]*bind[a-z]*[[:space:]]*=.*" l == null)
      (lib.splitString "\n" stock));

  # Two edits to the stock text beyond the bind strip above.
  #
  # tagrule: nine tags moved from master-stack to the scrolling layout.
  #
  # mousebind: stock binds PLAIN middle click to `togglemaximizescreen`, and a
  # matched mousebind is swallowed — pointer.c returns true without calling
  # wlr_seat_pointer_notify_button, so the click never reaches the application.
  # That costs middle-click-to-open-a-link and middle-click paste everywhere,
  # to reach a state this config deliberately no longer uses (see Mod+F below).
  stockScroller =
    builtins.replaceStrings
    [
      "layout_name:tile"
      "mousebind=NONE,btn_middle,togglemaximizescreen,0\n"
    ]
    [
      "layout_name:scroller"
      ""
    ]
    stockWithoutBinds;

  # Per-output geometry from hosts/<host>/local.nix — the same attrset that
  # feeds programs.niri.settings.outputs, so a monitor swap is still described
  # once. Without this DP-2 comes up at scale 1 instead of 1.2 and the two
  # panels stack wherever mango guesses.
  #
  # `name` is a regex in mango, hence the ^…$ anchors. Nix renders floats as
  # "74.968000" / "1.200000", which mango parses with strtof.
  monitorrules =
    lib.concatMapStrings (s: "monitorrule=${s}\n")
    (lib.mapAttrsToList (
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
      local.monitors);

  noctalia = "${pkgs.noctalia}/bin/noctalia";
  mmsg = "${config.wayland.windowManager.mango.package}/bin/mmsg";

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

  # Mod+F as a real toggle. mango has no dispatcher for "full width, or back to
  # normal if already full": `set_proportion` takes an absolute proportion and
  # `switch_proportion_preset` only walks the list forwards. So this asks the
  # compositor what the focused window is currently at and picks the other end.
  #
  # Deliberately NOT `togglemaximizescreen`, which would be the obvious match —
  # see the note on the Mod+F bind below for why that state is avoided entirely.
  #
  # No focused tiled client (nothing focused, or a floating window, which has no
  # scroller proportion) means the field is absent and the script does nothing.
  widthToggle = pkgs.writeShellScript "mango-width-toggle" ''
    p=$(${mmsg} get focusing-client 2>/dev/null | ${pkgs.jq}/bin/jq -r '.scroller_proportion // empty')
    [ -n "$p" ] || exit 0
    if ${pkgs.gawk}/bin/awk -v p="$p" 'BEGIN { exit !(p >= 0.99) }'; then
      ${mmsg} dispatch set_proportion,0.5
    else
      ${mmsg} dispatch set_proportion,1.0
    fi
  '';

  # Its own app-id so the window rule below can float it at a readable size.
  # --gtk-single-instance=false matters: ghostty otherwise hands the command to
  # the already-running instance, which ignores --class and opens a normal tab.
  keysClass = "com.mango.Keys";

  # Tag binds, 1..9. mango's tags are not niri's dynamic workspaces: `view`
  # switches to a tag, `tag` throws the focused window at one. The trailing 0
  # is the "do not also follow the window" argument.
  tagBinds =
    lib.concatMap (n: [
      "SUPER,${toString n},view,${toString n},0"
      "SUPER+SHIFT,${toString n},tag,${toString n},0"
    ])
    (lib.range 1 9);

  # The niri bind table, ported. Eleven of niri's binds have no mango
  # counterpart and are deliberately absent rather than rehomed onto something
  # that only half does the job: tabbed columns (Mod+W), centre-column and
  # centre-visible-columns (Mod+C, Mod+Ctrl+C), first/last column and moving a
  # column there (Mod+Home/End, Mod+Ctrl+Home/End), floating↔tiling focus
  # (Mod+Shift+V), reordering workspaces (Mod+Shift+I/U), the ±10% width and
  # height nudges (Mod+Minus/Equal and their Shift pair — `set_proportion`
  # takes an absolute proportion only), reset-window-height (Mod+Ctrl+R), and
  # screenshot-window (Mod+Print — Noctalia has region and fullscreen, not a
  # per-window capture).
  binds =
    [
      # Launchers.
      "SUPER,Return,spawn,ghostty"
      "SUPER,T,spawn,ghostty"
      "SUPER,B,spawn,zen-beta"
      "SUPER,E,spawn,nautilus"

      # Noctalia panels. Identical keys to ./niri.nix — this half of the table
      # is IPC into the shell, so it ports across untouched.
      "SUPER,space,spawn,${noctalia} msg panel-toggle launcher"
      "SUPER,V,spawn,${noctalia} msg panel-toggle clipboard"
      "SUPER,Y,spawn,${noctalia} msg panel-toggle wallpaper"
      "SUPER,comma,spawn,${noctalia} msg panel-toggle control-center"
      "SUPER,X,spawn,${noctalia} msg panel-toggle session"

      # The notes plugin's panel. Plugin panels are addressed as
      # "<plugin-id>:<entry-id>", hence the slash and the colon. Shift is
      # required: plain SUPER+N is switch_layout further down.
      "SUPER+SHIFT,N,spawn,${noctalia} msg panel-toggle noctalia/notes:panel"
      "SUPER+ALT,L,spawn,${noctalia} msg session lock"

      # Layout toggle, routed through Noctalia rather than xkb so the OSD is
      # immediate — see the xkb_rules_layout note further down. Same physical
      # combo as niri's grp:alt_shift_toggle, same dispatcher underneath.
      "ALT,shift_l,spawn,${noctalia} msg keyboard-layout-cycle"

      # Window state.
      #
      # Mod+F toggles the focused column between full width and half, through a
      # small script (see widthToggle above) rather than a dispatcher, because
      # mango has no toggle for it: `set_proportion` is absolute and
      # `switch_proportion_preset` only walks forwards.
      #
      # It deliberately does NOT use `togglemaximizescreen`, the obvious-looking
      # match for niri's maximize-column. That sets a separate `ismaximizescreen`
      # flag, and while it is on mango refuses the mouse grab outright
      # (pointer.c:787) and skips exchange_client, exchange_stack_client,
      # resize_window, center_window and togglefloating — the window freezes.
      # Worse, switch_proportion_preset has NO such guard, so Mod+R on a
      # maximized window rewrote the stored proportion while the geometry stayed
      # pinned, and clients that lay out against their configured size
      # (VSCodium's panes) drew themselves wrong.
      #
      # Full width reaches near enough the same geometry, but NOT because the
      # two share any arithmetic — maximize-screen subtracts gappoh, a 1.0
      # column subtracts scroller_structs, and nothing in mango keeps them in
      # step. They agree only because scroller_structs is set to gappoh by hand
      # further down; read the note there before changing either. What this buys
      # over maximize-screen is that the window stays an ordinary tiled one,
      # draggable and resizable throughout.
      #
      # Mod+Shift+F is still the real thing: whole monitor, over the bar, no
      # border.
      "SUPER,Q,killclient"
      "SUPER,F,spawn,${widthToggle}"
      "SUPER+SHIFT,F,togglefullscreen"
      "SUPER+SHIFT,T,togglefloating"
      "SUPER,N,switch_layout"

      # Seeing what is open, four ways. In the overview itself left click
      # focuses a window and right click closes it.
      "SUPER,D,toggleoverview"
      "SUPER+SHIFT,D,toggleoverview,1"
      "SUPER,Tab,switcher,all_tag_next"
      "SUPER,grave,togglejump"

      # The cheat sheet, standing in for niri's hotkey overlay.
      "SUPER+SHIFT,slash,spawn,ghostty --gtk-single-instance=false --class=${keysClass} -e ${keysCheatsheet}"

      # Focus — hjkl and arrows alike, both stay inside the tag.
      "SUPER,H,focusdir,left"
      "SUPER,L,focusdir,right"
      "SUPER,J,focusdir,down"
      "SUPER,K,focusdir,up"
      "SUPER,Left,focusdir,left"
      "SUPER,Right,focusdir,right"
      "SUPER,Up,focusdir,up"
      "SUPER,Down,focusdir,down"
      "ALT,Tab,focuslast"

      # Ctrl crosses monitors. Worth knowing: with sloppyfocus off these are
      # the reliable way to change monitor, because a click on empty desktop
      # selects the monitor without moving keyboard focus (see below).
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
      "SUPER+SHIFT,Up,exchange_client,up"
      "SUPER+SHIFT,Down,exchange_client,down"

      # Move to another monitor. niri moved the whole column; `tagmon` moves
      # one window — the column is not a unit mango has.
      "SUPER+CTRL+SHIFT,Left,tagmon,left"
      "SUPER+CTRL+SHIFT,Right,tagmon,right"
      "SUPER+CTRL+SHIFT,Up,tagmon,up"
      "SUPER+CTRL+SHIFT,Down,tagmon,down"
      "SUPER+CTRL+SHIFT,H,tagmon,left"
      "SUPER+CTRL+SHIFT,L,tagmon,right"
      "SUPER+CTRL+SHIFT,J,tagmon,down"
      "SUPER+CTRL+SHIFT,K,tagmon,up"

      # Pulling a window into the focused column and pushing it back out —
      # niri's consume-or-expel.
      "SUPER,bracketleft,scroller_stack,left"
      "SUPER,bracketright,scroller_stack,right"
      "SUPER,period,scroller_stack,down"

      # Column width. 1/3, 1/2, 2/3, full — the last entry is what Mod+F jumps
      # straight to, so this is also the way back out of it. niri's Mod+Ctrl+F
      # (expand-column-to-available-width) is gone: with Mod+F no longer a
      # separate maximize state the two would have been the same key twice.
      "SUPER,R,switch_proportion_preset"

      # Tags, on niri's workspace keys.
      "SUPER,I,viewtoleft_have_client,0"
      "SUPER,U,viewtoright_have_client,0"
      "SUPER+CTRL,I,tagtoleft,0"
      "SUPER+CTRL,U,tagtoright,0"

      # Screenshots. niri had these built in; mango does not, so they go
      # through Noctalia — which also means they land in the directory and
      # under the filename pattern configured in ./noctalia.nix.
      "NONE,Print,spawn,${noctalia} msg screenshot-region"
      "CTRL,Print,spawn,${noctalia} msg screenshot-fullscreen"

      # Session. Reload moves off stock's SUPER+r so Mod+R can be the width
      # cycle, as in niri.
      "SUPER+SHIFT,R,reload_config"
      "SUPER+SHIFT,E,quit"

      # Media and brightness go through Noctalia rather than
      # wpctl/brightnessctl: it draws the OSD, and its brightness path drives
      # the external panels over DDC/CI.
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

  # niri's Mod+wheel family. Stock already binds plain SUPER to the tags, so
  # only the two modified pairs are added here.
  axisBinds = [
    "SUPER+SHIFT,UP,focusdir,left"
    "SUPER+SHIFT,DOWN,focusdir,right"
    "SUPER+CTRL,UP,tagtoleft,0"
    "SUPER+CTRL,DOWN,tagtoright,0"
  ];

  # Ported from window-rules in ./niri.nix, but only the four that were asked
  # for — the Nautilus, File Roller and Picture-in-Picture rules are not here,
  # which is also why the app rule below needs no exclusion and stays a single
  # alternation. Later rules override earlier ones for the same window
  # (mango's apply_rule_properties loop), and `title` matches through pcre2, so
  # the negative lookahead in the Steam pair is a real exclusion.
  windowRules = [
    # gamescope's nested window. gaming.nix already passes -f, so what this
    # adds is WHICH output it lands on: without it the game opens wherever
    # focus happened to be when Steam launched the title, usually the small
    # panel. Both app-id and title are literally "gamescope".
    "monitor:${local.gameOutput.name},isfullscreen:1,appid:^gamescope$"

    # Steam's main window takes the column; Friends, the overlay and download
    # toasts are companion windows that should not take one at all.
    "scroller_proportion:1.0,appid:^steam$,title:^Steam$"
    "isfloating:1,appid:^steam$,title:^(?!Steam$).*"

    # "One big document" apps get the full column. These app-ids are what the
    # windows actually report, not what their .desktop StartupWMClass claims —
    # VSCodium says "vscodium" there but "codium" on the window. Thunderbird is
    # the unverified one: its .desktop says "thunderbird", but check a live
    # window with `mmsg get all-clients` before trusting it.
    "scroller_proportion:1.0,appid:^(zen-beta|codium|DBeaver|thunderbird)$"

    # The cheat sheet: a sheet over the session, not a column.
    "isfloating:1,width:1000,height:720,appid:^${lib.escapeRegex keysClass}$"
  ];
in {
  # MangoWC as a second wayland session next to niri. The system half is
  # modules/nixos/mango.nix; this is the session itself.
  #
  # Shape of this file: upstream's config.conf with its keybinds stripped, then
  # one block of local settings and the niri bind table. Everything upstream
  # still decides is simply absent here, which is what keeps the diff readable.
  wayland.windowManager.mango = {
    enable = true;

    # Defines mango-session.target, which BindsTo graphical-session.target.
    # That is the whole reason Noctalia needs nothing of its own here: its unit
    # is WantedBy graphical-session.target, not niri.service.
    systemd.enable = true;

    # This option looks optional and is not. The module only writes
    # autostart.sh — and only adds the `exec-once` line that runs it — when
    # autostart_sh is non-empty, and that script is where it puts
    # `dbus-update-activation-environment --systemd …` and `systemctl --user
    # start mango-session.target`. Leave it empty and systemd.enable above
    # defines a target that nothing ever starts, so graphical-session.target
    # never comes up and Noctalia never launches.
    #
    # polkit: niri-flake ships niri-flake-polkit.service, but its [Install]
    # section is WantedBy=niri.service, so under mango nothing would answer a
    # pkexec prompt — including the one Noctalia's greeter sync uses.
    #
    # ddcutil: the HDMI panel (MSI MP241X, DDC display 1) comes up at 90% on
    # its own; this is the same push spawn-at-startup does in ./niri.nix.
    autostart_sh = ''
      ${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1 &
      ${pkgs.ddcutil}/bin/ddcutil setvcp 10 100 --display 1 &
    '';

    # Everything goes through extraConfig rather than `settings` so the stock
    # text stays verbatim and the local part stays visibly separate. It is all
    # still validated at build time — the module runs `mango -c … -p` over the
    # result, so a bad key or dispatcher fails the rebuild, not the login.
    #
    # Order is the mechanism: mango's parser overwrites scalars as it reads, so
    # anything below wins over the same key in the stock text above.
    extraConfig = ''
      ${stockScroller}

      # =====================================================================
      # Local settings. Everything above this line is upstream's.
      # =====================================================================

      ${monitorrules}
      # Stock sets `xkb_rules_layout=us`; this replaces it.
      #
      # NOT `xkb_rules_options=grp:alt_shift_toggle`, which is how ./niri.nix
      # does it, and that is deliberate. With an xkb-level toggle the group
      # changes inside the compositor and Noctalia only finds out by asking:
      # its MangoKeyboardBackend (src/compositors/mango/mango_keyboard_backend.cpp)
      # implements exactly `cycleLayout` and a one-shot `get keyboardlayout`,
      # and has no `setChangeCallback` and no poll fd. The adapter wires the
      # change callback only `if constexpr (requires { … setChangeCallback … })`
      # (compositor_platform.cpp:280), so for mango nothing is wired at all —
      # the niri and hyprland backends do have it, which is why the OSD is
      # instant there and laggy here.
      #
      # Turning the toggle into a bind that goes THROUGH Noctalia inverts that:
      # the shell performs the switch, so it knows at once and draws the OSD
      # without waiting to be asked. `keyboard-layout-cycle` calls the same
      # `switch_keyboard_layout` dispatcher underneath, so the behaviour is
      # identical — only the notification path changes.
      xkb_rules_layout=us,ru

      # ---- input ----------------------------------------------------------
      # niri has focus-follows-mouse off and a flat mouse curve.
      #
      # Known cost of sloppyfocus=0, and it is mango's behaviour rather than a
      # gap in this config: a click on EMPTY desktop selects that monitor
      # (pointer.c sets selected_monitor on button press) but does not move
      # keyboard focus, because client_focus() only runs when the click lands
      # on a window surface. The pointer-motion path that would fix it sits
      # behind `if (config.sloppyfocus)`. There is no setting for it — use
      # Mod+Ctrl+H/L, or click the window itself.
      sloppyfocus=0
      mouse_accel_profile=1
      trackpad_natural_scrolling=1

      # ---- layout ---------------------------------------------------------
      # niri drew a 2px focus ring; mango has one border that changes colour
      # with focus, so the ring width becomes the border width.
      borderpx=2

      # Tag transitions slide vertically, the way niri's workspaces do,
      # instead of stock's horizontal.
      tag_animation_direction=0
      # Keep the occupied tags contiguous: with windows on 1, 3 and 9 they are
      # compacted to 1, 2 and 3 and the current view follows. This is the other
      # half of making the bar read like niri's — `hide_when_empty` in
      # ./noctalia.nix stops empty tags being drawn, and this stops gaps opening
      # between the ones that are, so closing the last window on a middle tag
      # pulls the rest back instead of leaving a hole.
      #
      # Worth knowing: it MOVES windows, so Mod+3 goes to whatever is third now,
      # not to whatever was on tag 3 before the compaction.
      tag_gather=1


      # Upstream calls this "width reserved on sides when window ratio is 1" —
      # a peek strip so the neighbouring column stays visible at full width.
      # It is also, and this is the part the name hides, THE ONLY SOURCE OF A
      # LEFT/RIGHT MARGIN for a tiled scroller column. gappoh is never consulted
      # on the scroll axis at all (scroll.c:353):
      #
      #   max_client_width = m->w.width - 2*scroller_structs - gappih
      #   target_geom.x    = m->w.x + scroller_structs            (scroll.c:482)
      #
      # so at the stock 20 a 1.0 column sits 20px from one edge and 25px from
      # the other, and at 0 it goes edge to edge — which is what Mod+F and the
      # `scroller_proportion:1.0` window rules below were doing. gappoh only
      # reaches a window through togglemaximizescreen (scroll.c:472), which this
      # config deliberately does not use.
      #
      # Set to gappoh, so the two agree: a lone window centres with ~12px each
      # side (n_heads == 1 forces the centring branch, scroll.c:446) and a
      # focused full-width column among others gets 10px on the side it is
      # aligned to and 15px on the other. The 5px difference is gappih and is
      # structural — stock's 20 produces 20/25 the same way.
      scroller_structs=10
      scroller_default_proportion=0.5
      scroller_proportion_preset=0.333333,0.5,0.666667,1.0

      # Three zeroes together are niri's `center-focused-column = "never"`:
      # columns hug the strip instead of being pulled to the middle. Their
      # priority order is overspread > focus_center > prefer_center, so the
      # higher ones have to be off for the lower ones to mean anything.
      scroller_prefer_overspread=0
      scroller_focus_center=0
      scroller_prefer_center=0

      # NOT set: scroller_ignore_proportion_single. niri centres a lone column
      # (always-center-single-column) and mango can too, at 0 — but in that
      # mode set_proportion and switch_proportion_preset return early while one
      # window is on the tag (bind.c:912, bind.c:956), so Mod+R would silently
      # do nothing. Keeping the default trades the centring for working width.
      circle_layout=scroller,tile,monocle

      # ---- effects --------------------------------------------------------
      # The two zeroes are the point, and come from Noctalia's own mango page:
      # mango's SceneFX blur and shadows on LAYER surfaces ignore surface
      # opacity, so a translucent Noctalia bar or panel gets blurred and
      # shadowed as if it were opaque. Windows keep both; the shell draws its
      # own. layer_animations is off for the same reason — the panels already
      # animate themselves.
      blur=1
      blur_layer=0
      blur_optimized=1
      blur_params_num_passes=2
      blur_params_radius=5
      shadows=1
      layer_shadows=0
      shadow_only_floating=0
      shadows_size=4
      shadows_blur=12
      layer_animations=0

      # ---- window rules ---------------------------------------------------
      ${lib.concatMapStrings (r: "windowrule=${r}\n") windowRules}
      # ---- binds ----------------------------------------------------------
      ${lib.concatMapStrings (b: "bind=${b}\n") binds}
      ${lib.concatMapStrings (a: "axisbind=${a}\n") axisBinds}
      # Live palette from Noctalia's `mango` template (see theme.templates in
      # ./noctalia.nix), last so it wins over anything above.
      #
      # It must be spelled `source=` and not `source-optional=`: the template's
      # apply.sh only appends an include line when
      # `grep '^[[:space:]]*source[[:space:]]*=.*noctalia\.conf'` finds
      # nothing, and appending is exactly what must not happen — home-manager
      # makes config.conf a read-only /nix/store symlink, so the write would
      # fail the hook before it reaches `mmsg dispatch reload_config`.
      # `source-optional=` does not match that regex.
      source=~/.config/mango/noctalia.conf
    '';
  };

  # Seed the file the `source=` above points at, so a fresh machine has it
  # before Noctalia's template ever runs. Not managed by xdg.configFile on
  # purpose: Noctalia rewrites this file on every palette change and cannot
  # write through a store symlink. Same shape as seedWallpapers in
  # ./noctalia.nix. A missing target is not fatal either way — verified that
  # `mango -c … -p` still exits 0 — but it logs a red line at every start.
  home.activation.seedMangoNoctaliaConf = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run mkdir -p "$HOME/.config/mango"
    [ -e "$HOME/.config/mango/noctalia.conf" ] || run touch "$HOME/.config/mango/noctalia.conf"
  '';
}
