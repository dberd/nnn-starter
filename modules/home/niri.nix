{
  config,
  local,
  pkgs,
  ...
}: {
  programs.niri.settings = {
    # Stylix's niri target sets border/focus-ring colors and the cursor, so we
    # only describe behaviour here.

    prefer-no-csd = true;

    # niri shows the hotkey overlay on every startup by default; this is the
    # switch for that, not the Mod+Shift+Slash binding further down.
    hotkey-overlay.skip-at-startup = true;

    # X11 apps (Steam, older games) need an X server. niri can spawn
    # xwayland-satellite and export DISPLAY for them, but only when told where
    # the binary is — the default leaves it unset, which is why Steam reported
    # "unable to open a connection to X".
    xwayland-satellite.path = "${pkgs.xwayland-satellite-stable}/bin/xwayland-satellite";

    # The HDMI monitor (MSI MP241X, DDC display 1) comes up at 90% brightness
    # on its own — that's the panel's own remembered state, not anything niri
    # or Noctalia sets, so nothing here overrides it without an explicit push.
    spawn-at-startup = [
      {
        command = ["${pkgs.ddcutil}/bin/ddcutil" "setvcp" "10" "100" "--display" "1"];
      }
    ];

    input = {
      keyboard.xkb = {
        layout = "us,ru";
        options = "grp:alt_shift_toggle"; # Alt+Shift switches US <-> Russian
      };
      # One layout shared by every window, rather than per-window.
      keyboard.track-layout = "global";
      touchpad = {
        tap = true;
        natural-scroll = true;
        dwt = true; # disable-while-typing
      };
      mouse = {
        accel-profile = "flat";
        # Traditional wheel direction. Natural scrolling stays on for the
        # touchpad only — a wheel and a touchpad want opposite conventions.
        natural-scroll = false;
      };
      # Focus follows clicks, not the pointer.
      focus-follows-mouse.enable = false;
      # Move the pointer to whatever gains focus. niri has no per-bind version
      # of this, so it also applies to Mod+Left/Right within one monitor — the
      # price of having the cursor follow Ctrl+Mod+Left/Right across monitors.
      warp-mouse-to-focus.enable = true;
    };

    # Per-output mode/scale/position, declared in hosts/<host>/local.nix.
    # (Upstream had a single `monitorScale` scalar; this desktop has two panels
    # at different resolutions AND different scales, so it has to be per-output.)
    # Run `niri msg outputs` to see the names and current values.
    outputs = local.monitors;

    layout = {
      gaps = 12;
      center-focused-column = "never";
      preset-column-widths = [
        {proportion = 1.0 / 3.0;}
        {proportion = 1.0 / 2.0;}
        {proportion = 2.0 / 3.0;}
      ];
      default-column-width.proportion = 1.0 / 2.0;
      # Stylix disables the focus-ring and themes the border instead, then we
      # disable that border below — so re-enable the ring explicitly here or
      # nothing gets drawn. Thin outline on the focused window; transparent on
      # the rest so only the selected one is marked.
      #
      # The colour comes from Stylix's palette rather than a literal, so it
      # tracks stylix.image along with everything else Stylix paints. Note this
      # is settled at BUILD time: niri reads a static KDL out of the store and
      # knows nothing about Noctalia, so switching wallpaper or colour scheme in
      # the Noctalia GUI moves its own surfaces immediately but leaves this
      # where it is until the next rebuild. Making it live needs Noctalia's
      # `niri` template, which works through `include "noctalia.kdl"` — a
      # directive niri-stable 25.08 does not have (verified: "unexpected node
      # `include`"; niri-unstable parses it fine).
      focus-ring = with config.lib.stylix.colors.withHashtag; {
        enable = true;
        width = 2;
        active.color = base0D;
        inactive.color = "#00000000";
      };
      border.enable = false;

      # Workspaces paint no background of their own, so the single wallpaper
      # sitting in the backdrop (see layer-rules below) shows through on every
      # workspace and in the overview alike. niri defaults this to an opaque
      # grey, which would cover that backdrop everywhere except the overview.
      background-color = "transparent";
    };

    # noctalia is started as a systemd user service bound to the niri session
    # (see modules/home/noctalia.nix), so no spawn-at-startup needed.

    # Subtle, fast animations — omarchy-style polish without distraction.
    animations.slowdown = 0.7;

    # The third piece of niri's own stationary-wallpaper recipe, and the one
    # that was still showing: with a transparent workspace background, niri's
    # overview shadow no longer falls on an opaque workspace but straight onto
    # the wallpaper, drawing a translucent bordered pane around every workspace.
    overview.workspace-shadow.enable = false;

    # Move Noctalia's wallpaper into niri's overview backdrop, so one wallpaper
    # sits behind everything instead of a copy inside each workspace thumbnail.
    # Same mechanism DankMaterialShell used for its "dms:blurwallpaper".
    #
    # Only works together with the transparent workspace background above: a
    # surface moved into the backdrop stops painting inside the workspace, so
    # with niri's opaque default every workspace is flat grey and the wallpaper
    # shows up in the overview only.
    #
    # Noctalia's other background surface, "noctalia-backdrop", is deliberately
    # not matched here — it is switched off entirely in noctalia.nix, see there.
    layer-rules = [
      {
        matches = [{namespace = "^noctalia-wallpaper$";}];
        place-within-backdrop = true;
      }
    ];

    # Per-window behaviour. A rule applies when ANY entry in `matches` matches
    # (or there are none) AND NO entry in `excludes` does. Both `app-id` and
    # `title` are regular expressions, not literals — hence the escaped dots and
    # the ^…$ anchors below, without which "steam" would also catch "steamwebhelper".
    #
    # Find the two fields with `niri msg windows` on a running window. Beyond the
    # ones used here, a rule can also set open-maximized, open-on-workspace,
    # default-column-width, block-out-from and more.
    #
    # niri already floats dialogs and fixed-size windows on its own, so this list
    # is only for the cases it gets wrong. Deliberately still short — workspace
    # pinning for messengers and music is yours to fill in.
    window-rules = [
      # Steam's main window is worth the whole screen; everything else it opens
      # (Friends, the overlay, download toasts) is a small companion window that
      # should not take a column in the scrolling layout.
      {
        matches = [
          {
            app-id = "^steam$";
            title = "^Steam$";
          }
        ];
        open-fullscreen = true;
      }
      {
        matches = [{app-id = "^steam$";}];
        excludes = [{title = "^Steam$";}];
        open-floating = true;
      }

      # Picture-in-Picture is a video overlay, not a document: floating, and
      # small enough to sit in a corner rather than claim half a monitor.
      {
        matches = [
          {
            app-id = "^zen-beta$";
            title = "^Picture-in-Picture$";
          }
        ];
        open-floating = true;
        default-column-width.fixed = 480;
      }
    ];

    # niri-flake's canonical attribute form: `action.<name> = <args>`. No-arg
    # actions take `{ }`; spawn takes a string or a list of argv strings.
    binds = {
      # Launchers
      "Mod+Return".action.spawn = "ghostty";
      "Mod+T".action.spawn = "ghostty"; # same terminal, second muscle memory
      # Noctalia v5 IPC: `noctalia msg <command>` (the old `ipc call` form and
      # the `noctalia-shell` binary are gone). The launcher is a named panel.
      "Mod+Space".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "launcher"
      ];
      "Mod+B".action.spawn = "zen-beta"; # browser
      "Mod+E".action.spawn = "nautilus"; # file manager

      # Window management
      "Mod+Q".action.close-window = {};
      "Mod+F".action.maximize-column = {};
      "Mod+Shift+F".action.fullscreen-window = {};
      "Mod+W".action.toggle-column-tabbed-display = {};
      # Moved off Mod+V, which now opens the clipboard (see below).
      "Mod+Shift+T".action.toggle-window-floating = {};
      "Mod+D".action.toggle-overview = {};

      # Noctalia panels. Valid ids, per `noctalia msg panel-toggle <bad-id>`:
      # clipboard, control-center, launcher, polkit, session, setup-wizard,
      # test, tray-drawer, wallpaper. The power menu is `session`.
      "Mod+V".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "clipboard"
      ];
      "Mod+Alt+L".action.spawn = ["noctalia" "msg" "session" "lock"];
      "Mod+Y".action.spawn = ["noctalia" "msg" "panel-toggle" "wallpaper"];
      "Mod+Comma".action.spawn = ["noctalia" "msg" "panel-toggle" "control-center"];
      "Mod+X".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "session"
      ];

      # Focus
      "Mod+H".action.focus-column-left = {};
      "Mod+L".action.focus-column-right = {};
      "Mod+J".action.focus-window-down = {};
      "Mod+K".action.focus-window-up = {};

      # Arrows mirror hjkl: movement stays *inside* the workspace. Switching
      # workspaces is Mod+1..5 further down, not Mod+Up/Down.
      "Mod+Left".action.focus-column-left = {};
      "Mod+Right".action.focus-column-right = {};
      "Mod+Up".action.focus-window-up = {};
      "Mod+Down".action.focus-window-down = {};

      # Ctrl moves focus across monitors (the pointer follows — see
      # warp-mouse-to-focus above).
      "Ctrl+Mod+Left".action.focus-monitor-left = {};
      "Ctrl+Mod+Right".action.focus-monitor-right = {};
      "Mod+Ctrl+H".action.focus-monitor-left = {};
      "Mod+Ctrl+L".action.focus-monitor-right = {};
      "Mod+Ctrl+J".action.focus-monitor-down = {};
      "Mod+Ctrl+K".action.focus-monitor-up = {};

      # Toggle between the two most recent windows. This is NOT the full
      # switcher with previews — that lives in niri's `recent-windows` block,
      # which niri-flake's settings module doesn't expose. Mod+Tab still opens
      # the built-in switcher, since niri binds it by default.
      "Alt+Tab".action.focus-window-previous = {};

      # Move — inside the workspace
      "Mod+Shift+H".action.move-column-left = {};
      "Mod+Shift+L".action.move-column-right = {};
      "Mod+Shift+J".action.move-window-down = {};
      "Mod+Shift+K".action.move-window-up = {};
      "Mod+Shift+Left".action.move-column-left = {};
      "Mod+Shift+Right".action.move-column-right = {};
      "Mod+Shift+Down".action.move-window-down = {};
      "Mod+Shift+Up".action.move-window-up = {};

      # Move — to another monitor, following the physical layout
      "Mod+Ctrl+Shift+Left".action.move-window-to-monitor-left = {};
      "Mod+Ctrl+Shift+Right".action.move-window-to-monitor-right = {};
      "Mod+Ctrl+Shift+Up".action.move-window-to-monitor-up = {};
      "Mod+Ctrl+Shift+Down".action.move-window-to-monitor-down = {};
      "Mod+Ctrl+Shift+H".action.move-column-to-monitor-left = {};
      "Mod+Ctrl+Shift+L".action.move-column-to-monitor-right = {};
      "Mod+Ctrl+Shift+J".action.move-column-to-monitor-down = {};
      "Mod+Ctrl+Shift+K".action.move-column-to-monitor-up = {};

      # Column and window arrangement — the pieces of niri's scrolling layout
      # that were missing here but present in the DankMaterialShell set.
      "Mod+BracketLeft".action.consume-or-expel-window-left = {};
      "Mod+BracketRight".action.consume-or-expel-window-right = {};
      "Mod+Period".action.expel-window-from-column = {};
      "Mod+C".action.center-column = {};
      "Mod+Ctrl+C".action.center-visible-columns = {};
      "Mod+Home".action.focus-column-first = {};
      "Mod+End".action.focus-column-last = {};
      "Mod+Ctrl+Home".action.move-column-to-first = {};
      "Mod+Ctrl+End".action.move-column-to-last = {};
      "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = {};

      # Workspace navigation on i/u, as in that set: Mod moves focus, Ctrl takes
      # the column along, Shift moves the whole workspace.
      "Mod+I".action.focus-workspace-up = {};
      "Mod+U".action.focus-workspace-down = {};
      "Mod+Ctrl+I".action.move-column-to-workspace-up = {};
      "Mod+Ctrl+U".action.move-column-to-workspace-down = {};
      "Mod+Shift+I".action.move-workspace-up = {};
      "Mod+Shift+U".action.move-workspace-down = {};

      # Mouse wheel: workspaces plain, columns with Shift, carry the column with
      # Ctrl. The cooldown stops one flick from skipping several.
      "Mod+WheelScrollUp" = {
        action.focus-workspace-up = {};
        cooldown-ms = 150;
      };
      "Mod+WheelScrollDown" = {
        action.focus-workspace-down = {};
        cooldown-ms = 150;
      };
      "Mod+Shift+WheelScrollUp".action.focus-column-left = {};
      "Mod+Shift+WheelScrollDown".action.focus-column-right = {};
      "Mod+Ctrl+WheelScrollUp" = {
        action.move-column-to-workspace-up = {};
        cooldown-ms = 150;
      };
      "Mod+Ctrl+WheelScrollDown" = {
        action.move-column-to-workspace-down = {};
        cooldown-ms = 150;
      };

      # Sizing
      "Mod+R".action.switch-preset-column-width = {};
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+Shift+Minus".action.set-window-height = "-10%";
      "Mod+Shift+Equal".action.set-window-height = "+10%";
      "Mod+Ctrl+R".action.reset-window-height = {};
      "Mod+Ctrl+F".action.expand-column-to-available-width = {};

      # Workspaces
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+9".action.focus-workspace = 9;
      "Mod+8".action.focus-workspace = 8;
      "Mod+7".action.focus-workspace = 7;
      "Mod+6".action.focus-workspace = 6;
      "Mod+Shift+1".action.move-column-to-workspace = 1;
      "Mod+Shift+2".action.move-column-to-workspace = 2;
      "Mod+Shift+3".action.move-column-to-workspace = 3;
      "Mod+Shift+4".action.move-column-to-workspace = 4;
      "Mod+Shift+5".action.move-column-to-workspace = 5;
      "Mod+Shift+9".action.move-column-to-workspace = 9;
      "Mod+Shift+8".action.move-column-to-workspace = 8;
      "Mod+Shift+7".action.move-column-to-workspace = 7;
      "Mod+Shift+6".action.move-column-to-workspace = 6;

      # Screenshots
      "Print".action.screenshot = {};
      "Mod+Print".action.screenshot-window = {};
      "Ctrl+Print".action.screenshot-screen = {};

      # Help + session
      "Mod+Shift+Slash".action.show-hotkey-overlay = {};
      "Mod+Shift+E".action.quit = {};
      # Media keys go through Noctalia rather than wpctl/brightnessctl directly:
      # it draws the on-screen indicator, and its brightness commands drive
      # external monitors over DDC/CI — brightnessctl only ever controlled a
      # laptop panel, which this machine does not have.
      "XF86AudioRaiseVolume".action.spawn = ["noctalia" "msg" "volume-up"];
      "XF86AudioLowerVolume".action.spawn = ["noctalia" "msg" "volume-down"];
      "XF86AudioMute".action.spawn = ["noctalia" "msg" "volume-mute"];
      "XF86AudioMicMute".action.spawn = ["noctalia" "msg" "mic-mute"];
      "XF86AudioPlay".action.spawn = ["noctalia" "msg" "media" "toggle"];
      "XF86AudioNext".action.spawn = ["noctalia" "msg" "media" "next"];
      "XF86AudioPrev".action.spawn = ["noctalia" "msg" "media" "previous"];
      "XF86MonBrightnessUp".action.spawn = ["noctalia" "msg" "brightness-up"];
      "XF86MonBrightnessDown".action.spawn = ["noctalia" "msg" "brightness-down"];
    };
  };
}
