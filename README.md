# nnn-starter

<p align="center">
  <img src="screenshot.png" alt="Screenshot of the NNN desktop — Niri + Noctalia on NixOS" width="100%">
</p>

> Three letters, zero compromise — now with batteries included.

An opinionated [omarchy](https://omarchy.org)-style NixOS starter for the [**NNN
stack**](https://the-nnn-stack.github.io/): **N**ixOS + **N**iri + **N**octalia. Clone it, set two placeholders,
run one command, and get a cohesive, themed, developer-ready Wayland desktop.

## What you get

| Layer        | Choice |
|--------------|--------|
| Compositor   | [niri](https://github.com/YaLTeR/niri) (scrollable-tiling Wayland) via [niri-flake](https://github.com/sodiboo/niri-flake), with [MangoWC](https://github.com/mangowm/mango) offered as a second session |
| Shell/UI     | [Noctalia](https://github.com/noctalia-dev/noctalia-shell) **v5** (bar, launcher, notifications, lock, control center) |
| Theming      | Noctalia's runtime templates for most apps, [Stylix](https://github.com/nix-community/stylix) for the rest — see [docs/theming.md](docs/theming.md) |
| Terminal     | [Ghostty](https://ghostty.org) |
| Shell + prompt | Zsh + [Starship](https://starship.rs) (autosuggestions, syntax highlighting, fzf, zoxide) |
| Editor (GUI) | [Zed](https://zed.dev) — themed via Stylix; default handler for text/source files |
| Editor (terminal) | Neovim, preconfigured (LSP, treesitter, telescope, completion); the `$EDITOR` |
| Browser      | [Zen](https://zen-browser.app) (beta channel, via the community flake) |
| File manager | [Nautilus](https://apps.gnome.org/Nautilus/) (GNOME Files) |
| Font         | Maple Mono NF |
| Login        | greetd + [noctalia-greeter](https://github.com/noctalia-dev/noctalia-greeter) → niri (default) or mango session |

### Modern command-line toolset
`lsd` · `fzf` · `bat` · `btop` · `ripgrep` · `fd` · `zoxide` · `eza` · `yazi` ·
`dust` · `duf` · `procs` · `bandwhich` · `gping` · `zellij` ·
`tealdeer` · `jq` · `yq` · `lazygit` · `delta` · `gh` · `direnv` + `nix-direnv` ·
`nh` · `nom` · `fastfetch` ·
`claude` ([Claude Code](https://github.com/anthropics/claude-code)) ·
`opencode` ([opencode](https://opencode.ai)).
Old names are aliased to the new tools (`ls`→`lsd`, `cat`→`bat`,
`cd`→`zoxide`, `top`→`btop`, …). Both agentic CLIs are wrapped so their
traffic goes through the proxy tunnel and is refused when it is down — see
[docs/proxy.md](docs/proxy.md).

## Quick start

```sh
# 1. Get the repo onto your machine (or into the live NixOS installer).
git clone https://github.com/<you>/nnn-starter ~/nnn-starter
cd ~/nnn-starter

# 2. Generate real hardware config for THIS machine.
sudo nixos-generate-config --show-hardware-config > hosts/<host>/hardware-configuration.nix

# 3. Put your identity in hosts/<host>/local.nix (see Placeholders below).

# 4. Build & switch. This fork has two hosts, so the target is named:
sudo nixos-rebuild switch --flake .#nnn-desktop     # or .#nnn-t480s
```

After the first build, rebuild with `nh os switch` (aliased to `rebuild`) or
`update` (which also bumps `flake.lock`).

## Placeholders to edit

Everything machine-local lives in one file per host —
`hosts/<host>/local.nix`. Upstream keeps it at the repo root and marks it
`skip-worktree`; this fork tracks it instead, because with more than one machine
the values have to be reproducible on each of them.

| What | Where |
|------|-------|
| **Username, hostname, full name** | `hosts/<host>/local.nix` |
| **Git identity** (name, email) | `hosts/<host>/local.nix` |
| **Timezone** | `hosts/<host>/local.nix` |
| **Monitors** — name, mode, scale, position | `monitors` in `hosts/<host>/local.nix` |
| **Disk layout** | `hosts/<host>/disko.nix` |
| **Hardware** | `hosts/<host>/hardware-configuration.nix` (generated, step 2 above) |
| **Locale / keyboard layout** | [`hosts/common/default.nix`](hosts/common/default.nix) |

`monitors` is the single source of truth for outputs: niri takes its `outputs`
from it, Noctalia derives its per-monitor wallpapers and lock-screen boxes from
it, and `flake.nix` picks the largest panel out of it for gamescope. Add or swap
a monitor there and the rest follows.

Real secrets never go in these files — see `modules/nixos/secrets.nix`.

## Layout

```
flake.nix              # inputs + mkHost -> nixosConfigurations.{nnn-desktop,nnn-t480s}
hosts/common/          # shared: locale, keyboard layout, stateVersion
hosts/<host>/          # per machine: local.nix, hardware-configuration.nix, disko.nix
modules/nixos/         # system: boot, audio, niri, mango, noctalia, stylix, users…
modules/home/          # user: fish, ghostty, neovim, niri/mango keybinds, cli tools…
themes/kanagawa.yaml   # vendored base16 palette (Stylix source of truth)
docs/                  # theming, proxy/VPN, dev environment, per-host installs
```

## Key bindings (niri)

| Keys | Action |
|------|--------|
| `Mod`+`Return` | Terminal (ghostty) |
| `Mod`+`Space` | Noctalia launcher |
| `Mod`+`B` | Browser (Zen) |
| `Mod`+`E` | File manager (Nautilus) |
| `Mod`+`Q` | Close window |
| `Mod`+`F` / `Mod`+`Shift`+`F` | Maximize column / fullscreen |
| `Mod`+`H`/`J`/`K`/`L` | Focus left/down/up/right |
| `Mod`+`Shift`+`H`/`J`/`K`/`L` | Move window |
| `Mod`+`1`…`5` | Switch workspace |
| `Mod`+`R` | Cycle column width |
| `Mod`+`Shift`+`N` | Notes panel (Noctalia plugin) |
| `Print` | Screenshot |
| `Mod`+`Shift`+`/` | Hotkey overlay (full list) |
| `Mod`+`Shift`+`E` | Quit niri |

## Second session: MangoWC

niri is the default and nothing here depends on replacing it. `mango` is
installed alongside it as a second wayland session, so the greeter lists both
and switching is a logout — pick **Mango** instead of **Niri** at the login
screen. `session.default` in `hosts/<host>/default.nix` still says `niri`.

Noctalia itself needs no changes to follow: its unit is
`WantedBy=graphical-session.target` rather than `niri.service`, and Noctalia v5
talks to mango natively — workspaces and keyboard layout come over `mango-ipc`.

**The session config is a port of niri's, laid over upstream's text.**
[`modules/home/mango.nix`](modules/home/mango.nix) reads mango's own
`assets/config.conf` out of the locked flake input and keeps it verbatim, so
everything this config has no opinion about — effects defaults, mouse bindings,
gestures, scratchpad, dwindle knobs — moves with the flake instead of being
restated here. Three edits to that text, then one local block appended after it:

- every `bind…=` line is dropped and niri's table supplied below, because
  keeping both sets would mean two ways to do everything (`mousebind`,
  `axisbind` and `gesturebind` are deliberately left alone),
- the nine tags move from master-stack to the `scroller` layout,
- stock's *plain* middle click is unbound from `togglemaximizescreen` — a
  matched mousebind is swallowed, so it cost middle-click-to-open-a-link and
  middle-click paste everywhere.

The local block adds monitor geometry and scaling from `hosts/<host>/local.nix`
(without it DP-2 comes up at scale 1), `xkb_rules_layout=us,ru` routed through
Noctalia rather than an xkb-level toggle, a polkit agent in `autostart.sh`
(niri-flake's unit is `WantedBy=niri.service`, so nothing would answer a
`pkexec` prompt here), and the bind table.

**So the keys are niri's, not mango's** — `Mod`+`Return`, `Mod`+`Q`,
`Mod`+`H`/`J`/`K`/`L`, `Mod`+`1`…`9`, `Mod`+`Shift`+`/` for a cheat sheet that
stands in for niri's hotkey overlay. Eleven niri binds have no mango counterpart
and are absent rather than rehomed onto something that half works; the list and
the reason for each is in the file. `Mod`+`F` is the one that behaves
differently by design: it toggles the column between half and full width instead
of calling `togglemaximizescreen`, which pins the geometry and makes `Mod`+`R`
misbehave. `Mod`+`Shift`+`F` is still real fullscreen.

Colour is the other inversion worth knowing. niri's focus ring comes from Stylix
and therefore only follows a palette change at the next rebuild; mango's borders
come from Noctalia's `mango` template through `source=~/.config/mango/noctalia.conf`,
so they follow it live. There is no `stylix.targets.mango` at all.

Things that differ from the niri session regardless of config:

| | niri | mango |
|---|---|---|
| Layout | scrollable columns | dwl tags, each on the `scroller` layout |
| Workspaces | dynamic | nine fixed tags, compacted (`tag_gather`) |
| Wallpaper | one copy in niri's overview backdrop (`place-within-backdrop`) | ordinary background layer — mango has no backdrop |
| XWayland | `xwayland-satellite` | built in |
| Screencast portal | `xdg-desktop-portal-gnome` | `xdg-desktop-portal-wlr` |

[`modules/nixos/mango.nix`](modules/nixos/mango.nix) stays thin — the flake's own
module handles the portals and the session entry. The one thing it adds is a
screencast output chooser, because `xdg-desktop-portal-wlr` otherwise shells out
to wofi/rofi/bemenu/mew/fuzzel and fails with `wlroots: no output found`.

The generated `config.conf` is validated at build time with `mango -c … -p`, so
a bad bind or an unknown key fails the rebuild rather than the login.

For ideas not taken yet — scratchpads, per-tag rules, `force_tiled_state`, and
the handful of configs worth reading for either compositor — see
[docs/compositor-configs.md](docs/compositor-configs.md).

## Reskin it

Most of the desktop reskins **without a rebuild**: pick a wallpaper or a scheme
in Noctalia's control centre and the bar, GTK, the terminal, mango's borders,
bat, btop, lazygit, yazi, fzf, cava and the rest follow immediately. That is
Noctalia rendering its templates at runtime into real files.

The remainder is Stylix, which writes into `/nix/store` at build time and so
only catches up on the next rebuild: fonts, the cursor, Qt/Kvantum, niri's
focus ring and Zen's `userChrome`. Both derive from the same picture
(`stylix.image`), so they agree until something is changed at runtime.

To move the build-time half, swap the palette and rebuild:

```nix
# modules/nixos/stylix.nix
stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
```

…or edit `themes/kanagawa.yaml` directly.

**[docs/theming.md](docs/theming.md)** has the full ownership table, the rule
that decides which side can own a given app, and how to add another one.

## Per-project dev environments

This starter deliberately keeps language toolchains **out** of the global
system. Use direnv + flakes per project instead:

```sh
# in a project repo
echo "use flake" > .envrc && direnv allow
```

```nix
# that project's flake.nix devShell, e.g.
devShells.default = pkgs.mkShell { packages = [ pkgs.nodejs pkgs.cargo ]; };
```

## Verifying changes

You can develop this on **macOS**, but a NixOS system can't be *built* there
without a Linux builder — these all work locally as pure evaluation/lint:

```sh
nix flake check                                              # evaluate everything
nix flake show                                               # list outputs
nix fmt                                                      # format (alejandra)
nix run nixpkgs#statix -- check . && nix run nixpkgs#deadnix # lint
nix eval .#nixosConfigurations.nnn-desktop.config.system.build.toplevel.drvPath
```

On a NixOS box (or with a remote/`linux-builder`) you can smoke-test in a VM:

```sh
nixos-rebuild build-vm --flake .#nnn-desktop
./result/bin/run-nnn-desktop-vm
```

### CI

[`.github/workflows/check.yml`](.github/workflows/check.yml) runs on every push
and PR:

- **eval** — `nix flake check --no-build` evaluates the whole config (the fast,
  reliable signal: catches option typos and niri schema errors).
- **lint** — `alejandra --check`, `statix`, `deadnix`.
- **build** — realises the full system closure, once per host (matrix); runs on `main` / manual
  dispatch. niri and noctalia are pulled prebuilt from their cachix caches
  (`niri.cachix.org`, `noctalia.cachix.org`), so it finishes in minutes instead
  of compiling C++/Rust from source. Delete the job if you don't want it.

> **Commit a `flake.lock`.** Generate it once on a machine with Nix
> (`nix flake lock`) and commit it, so CI and your machines resolve identical
> inputs. Until then, each run pins the latest upstream automatically.

## Notes / next steps

Upstream lists these as not included. This fork has since done all three:

- Secrets: [sops-nix](https://github.com/Mic92/sops-nix) — `modules/nixos/secrets.nix`,
  with a per-host age key at `/var/lib/sops-nix/key.txt` as the one thing that cannot
  live here. One key per machine, so a lost laptop can be dropped from `.sops.yaml`
  and `sops updatekeys` re-run without touching the other host.
- Declarative disks: [disko](https://github.com/nix-community/disko) — one
  `hosts/*/disko.nix` per machine. The desktop is plain btrfs; the laptop is LUKS →
  LVM → btrfs with a swap volume sized for hibernation.
- Multi-host: `hosts/` is one folder per machine, and there are two —
  **`nnn-desktop`** (AMD, two monitors, games) and **`nnn-t480s`** (ThinkPad T480s,
  encrypted, no games). Build either with `--flake .#<host>`; adding a third is a
  `hosts/<name>/` directory and one line in `flake.nix`. Installing the laptop is
  written up in [docs/install-t480s.md](docs/install-t480s.md).

### Binary caches (no source builds)

niri and noctalia would otherwise compile from source (noctalia's C++ tree alone
is ~an hour). To avoid that, the flake pins **noctalia to its `cachix` branch**
— upstream force-pushes there only after a commit's package is built and pushed
to `noctalia.cachix.org`, so `inputs.noctalia.packages.<sys>.default` is always a
cache hit. It still tracks the **v5 line** (`main`), just slightly behind; the
old series lives on `legacy-v4`. niri uses niri-flake's prebuilt
`niri-unstable` from `niri.cachix.org` for the same reason — **unstable**, not
`niri-stable`, because Noctalia themes niri through an `include` directive that
the 25.08 release does not parse (see [`modules/nixos/niri.nix`](modules/nixos/niri.nix)).

The two caches are trusted in [`modules/nixos/default.nix`](modules/nixos/default.nix)
so your machine pulls binaries too. Neither input may `follows` our `nixpkgs` —
that would rebuild them against a different nixpkgs and miss the cache.

The one exception is **mango**: it has no cache of its own, so it *does* follow
our `nixpkgs` (there is nothing to miss) and compiles from source — wlroots +
scenefx + the compositor, a few minutes, once per input bump. Only the second
session pays for it.
