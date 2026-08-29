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
| Compositor   | [niri](https://github.com/YaLTeR/niri) (scrollable-tiling Wayland) via [niri-flake](https://github.com/sodiboo/niri-flake) |
| Shell/UI     | [Noctalia](https://github.com/noctalia-dev/noctalia-shell) **v5** (bar, launcher, notifications, lock, control center) |
| Theming      | [Stylix](https://github.com/nix-community/stylix) with the **Kanagawa** palette — one scheme themes everything |
| Terminal     | [Ghostty](https://ghostty.org) |
| Shell + prompt | Zsh + [Starship](https://starship.rs) (autosuggestions, syntax highlighting, fzf, zoxide) |
| Editor (GUI) | [Zed](https://zed.dev) — themed via Stylix; default handler for text/source files |
| Editor (terminal) | Neovim, preconfigured (LSP, treesitter, telescope, completion); the `$EDITOR` |
| Browser      | [Zen](https://zen-browser.app) (beta channel, via the community flake) |
| File manager | [Nautilus](https://apps.gnome.org/Nautilus/) (GNOME Files) |
| Font         | Maple Mono NF |
| Login        | greetd + tuigreet → niri session |

### Modern command-line toolset
`lsd` · `fzf` · `bat` · `btop` · `ripgrep` · `fd` · `zoxide` · `eza` · `yazi` ·
`dust` · `duf` · `procs` · `bandwhich` · `gping` · `zellij` ·
`tealdeer` · `jq` · `yq` · `lazygit` · `delta` · `gh` · `direnv` + `nix-direnv` ·
`nh` · `nom` · `claude` ([Claude Code](https://github.com/anthropics/claude-code)).
Old names are aliased to the new tools (`ls`→`lsd`, `cat`→`bat`,
`cd`→`zoxide`, `top`→`btop`, …).

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
modules/nixos/         # system: boot, audio, niri, noctalia, stylix, users…
modules/home/          # user: fish, ghostty, neovim, niri keybinds, cli tools…
themes/kanagawa.yaml   # vendored base16 palette (Stylix source of truth)
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
| `Print` | Screenshot |
| `Mod`+`Shift`+`/` | Hotkey overlay (full list) |
| `Mod`+`Shift`+`E` | Quit niri |

## Reskin it

Everything is driven by one base16 file. Swap the palette and rebuild:

```nix
# modules/nixos/stylix.nix
stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
```

…or edit `themes/kanagawa.yaml` directly.

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
`niri-stable` from `niri.cachix.org` for the same reason.

The two caches are trusted in [`modules/nixos/default.nix`](modules/nixos/default.nix)
so your machine pulls binaries too. Neither input may `follows` our `nixpkgs` —
that would rebuild them against a different nixpkgs and miss the cache.
