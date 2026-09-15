# Configs in the wild: mango and niri

A reading list, not a shopping list. Nothing here has been adopted; each entry
says what is actually worth taking and why.

## MangoWC

There is no awesome-list for mango. The index is the wiki plus the Discord.

**[DreamMaoMao/mango-config](https://github.com/DreamMaoMao/mango-config)** —
the reference config, by mango's original author, linked from the upstream
README. The borrowable part is the *structure*, not the settings: `config.conf`
is split into `bind.conf`, `rule.conf`, `tag.conf`, `monitor.conf`, `env.conf`
and pulled together with `source=`. That maps directly onto what
`modules/home/mango.nix` already does for `noctalia.conf`, and would let the
generated file separate upstream's text from ours without the string
substitutions at the top of that file. Also ships `mangobar` and helper scripts,
neither of which is relevant here.

**[mangowm/mango](https://github.com/mangowm/mango)** ·
[docs](https://mangowm.github.io/) ·
[wiki](https://github.com/mangowm/mango/wiki) — the documentation is the best
reference by a distance, and `docs/window-management/rules.md` in particular
lists a lot of `windowrule` fields this config does not use. The same tree is
already in the store as the locked flake input, so it can be read offline.

**[codeberg.org/ClemTheAlien/nixos_config](https://codeberg.org/ClemTheAlien/nixos_config)**
— the one NixOS peer running mango, and actively maintained. Worth diffing
against `modules/home/mango.nix` for how someone else divides settings between
the flake module's structured `settings` option and raw text.

**[wiki.nixos.org/wiki/Mango](https://wiki.nixos.org/wiki/Mango)** — a worked
`wayland.windowManager.mango` example using the structured `settings` option.
Useful as a sanity check on option names, since this config deliberately goes
through `extraConfig` instead.

Smaller, still readable:
[codeberg.org/armin/mango-config](https://codeberg.org/armin/mango-config) (Nord,
single file, aimed at ex-dwm users) ·
[bautitobal/mango](https://github.com/bautitobal/mango) (Hyprland-ish feel;
layout switching, floating rules, scratchpads, gestures).

### Features upstream has that this config does not use

All confirmed present in the locked input and absent here:

- **`force_tiled_state`** — makes a client believe it is tiled so it honours the
  dimensions it is given. Directly relevant to the VSCodium mis-layout noted in
  `modules/home/mango.nix`.
- **Named scratchpads** — `isnamedscratchpad`, `single_scratchpad`,
  `toggle_scratchpad`. Stock binds one on `Alt+z`; the bind filter drops it and
  nothing re-adds it.
- **Per-tag `tagrule`** — `nmaster`, `mfact`, `no_render_border`,
  `open_as_floating`, `no_hide`, binding a tag to a monitor. This config only
  uses `tagrule` to set the layout, identically for all nine.
- **Per-window visual rules** — `noblur`, `isnoshadow`, `isnoradius`,
  `isnoanimation`, `focused_opacity` / `unfocused_opacity`, per-window
  open/close animations. Only the global knobs are set.
- **`layerrule`** — stock has two for rofi; nothing here targets Noctalia's
  layers.
- **Key modes** (`keymode=` on any bind) and **`switchbind`** (lid switch).
- **`gesturebind`** — the eight stock gestures survive the bind filter and are
  live, but nothing is customised and `gesture_live=1` drag previews are off.
- Other layouts — `circle_layout` is set to `scroller,tile,monocle`, so
  `dwindle`, `vertical_scroller`, `grid` and `center_tile` are unreachable.
- Overview tuning — `hotarea_size` / `enable_hotarea` (a hot corner, stock off),
  `overcircle_center_ratio`.

## niri

The project moved from `YaLTeR/niri` to the **`niri-wm/niri`** org, and the wiki
is now generated from `docs/wiki/` in the repo. The old "Configs in the Wild"
page did not survive the move.

**[TryDkg/TryDkg-s-dotfiles](https://github.com/TryDkg/TryDkg-s-dotfiles)** —
niri + Noctalia, the closest match to this stack. The config is split into
per-topic files (`animation.kdl`, `input.kdl`, `keybinds.kdl`, `layout.kdl`,
`rules.kdl`, `steam.kdl`, `noctalia.kdl`); the Steam and gaming rules are worth
comparing against the gamescope/Steam rules in `modules/home/niri.nix`.

**[tonybanters/niri-btw](https://github.com/tonybanters/niri-btw)** — Noctalia
as the bar, well documented, with a [walkthrough](https://tonybtw.com/tutorial/niri/).
Good for keybind ideas.

**[youngcoder45/Noctalia-Niri-Dotfiles](https://github.com/youngcoder45/Noctalia-Niri-Dotfiles)**
— a minimal single-file `config.kdl` + Noctalia, useful as a diffable reference
for the Noctalia-specific niri settings.

**[docs.noctalia.dev/noctalia/compositor-settings/niri](https://docs.noctalia.dev/noctalia/compositor-settings/niri/)**
— Noctalia's own required/recommended settings for niri. The mango equivalent is
already cited in `modules/home/mango.nix`; this one is worth re-checking against
the layer-rules and backdrop setup in `modules/home/niri.nix`.

Browsable indexes: [niri-dotfiles](https://github.com/topics/niri-dotfiles) and
[niri-rice](https://github.com/topics/niri-rice) on GitHub topics.
