# Theming: who owns which file

Two systems can colour an application here, and they must never both own the
same file.

**Stylix** derives a base16 palette from `stylix.image` and writes the results
into `/nix/store` at build time. Everything it touches is correct the moment the
system is built, and frozen until the next rebuild.

**Noctalia** derives a Material palette from the same wallpaper and renders its
*templates* at runtime, into real files in `$XDG_CONFIG_HOME`. Everything it
touches follows a palette or wallpaper switch made in the control centre,
immediately, with no rebuild.

Both read the same picture (`themes/wallpapers/wallhaven-1pw769_2560x1440.png`),
so they agree on day one. They stop agreeing the moment anything is changed at
runtime — which is the whole reason to move an app from one to the other.

## The rule that decides it

Most Noctalia templates ship an `apply.sh` that mutates the application's own
config file, typically:

```sh
if ! cmp -s "$config_file" "$tmp"; then
    cat "$tmp" >"$config_file"
fi
```

Home-manager writes leaf config files as symlinks into read-only `/nix/store`.
That write fails — and usually the script never even gets that far, because
several of these hooks `touch` the file first:

```console
$ touch ~/.config/bat/config
touch: cannot touch '/home/sundial/.config/bat/config': Permission denied
```

Every hook runs under `set -euo pipefail`, so it aborts there, silently as far
as the desktop is concerned.

> **A Noctalia template can own an application only if home-manager does not
> write that application's config file.**

Usually arranging that is just turning the Stylix target off, because most
home-manager modules write nothing when their settings are empty —
`xdg.configFile."bat/config" = mkIf (cfg.config != {})`, and likewise for
btop — and Stylix was the only thing filling them in. Where that is not
enough, the module itself has to go.

The exceptions are the hooks that *append* instead of overwriting. Those work
against a store symlink as long as the line they want is already in it:
ghostty's wants `theme = noctalia`, mango's wants a `source=` line, and both are
set declaratively so the hook finds its work already done. The GTK hook is the
only one that actively replaces a read-only symlink with a real file.

## Current ownership

### Noctalia — follows a palette switch live

| id | file it owns | what had to be arranged |
|---|---|---|
| `ghostty` | `~/.config/ghostty/themes/noctalia` | `theme = "noctalia"` set in `ghostty.nix`, so the append-hook no-ops; the theme file is seeded at activation |
| `gtk3`, `gtk4` | `~/.config/gtk-*/gtk.css` | `stylix.targets.gtk` off (`gtk.nix`) |
| `mango` | `~/.config/mango/noctalia.conf` | `source=` line already in `config.conf`; there is no `stylix.targets.mango` at all |
| `cava` | `~/.config/cava/config` | stays a raw package in `apps.nix` |
| `btop` | `~/.config/btop/btop.conf` | `stylix.targets.btop` off (`cli.nix`) |
| `bat` | `~/.config/bat/config` | `stylix.targets.bat` off **and** `programs.ghostty.installBatSyntax = false` |
| `lazygit` | `~/.config/lazygit/config.yml` | `programs.lazygit` dropped entirely — it writes `config.yml` unconditionally |
| `yazi` | `~/.config/yazi/theme.toml` | stays a raw package in `cli.nix` |
| `fastfetch` | `~/.config/fastfetch/config.jsonc` | raw package + an activation **seed**, see below |
| `fzf` | `~/.config/fzf/themes/noctalia.fish` | `stylix.targets.fzf` off; sourced in `fish.nix` |
| `zellij` | `~/.config/zellij/themes/noctalia.kdl` | `stylix.targets.zellij` off; `settings.theme = "noctalia"` selects it. **New sessions only** — see below |
| `neovim` | `~/.config/nvim/lua/matugen.lua` | `base16-nvim` added; `initLua` carries the exact `pcall(require, 'matugen')` the hook greps for, so its append is skipped. **Repaints a running editor** — the module installs a SIGUSR1 handler and the hook signals nvim |
| `opencode` | `~/.config/opencode/themes/matugen.json` | `stylix.targets.opencode` off; `tui.theme = "matugen"` |
| `obs` | `~/.config/obs-studio/themes/matugen.obt` | nothing — pick it once in OBS's UI |
| `heroiclauncher` | `~/.config/heroic/themes/matugen.css` | nothing — pick it once in Heroic's UI |
| `ungoogled-chromium` | `~/.cache/noctalia/ungoogled-chromium/theme/` | `stylix.targets.chromium` off **at the NixOS level** (see below); then one **Load unpacked** at `chrome://extensions` |
| `zen-browser` | `~/.cache/noctalia/zen-browser/*.css`, plus an `@import` in the profile | `stylix.targets.zen-browser` off, which releases the profile's `chrome/user{Chrome,Content}.css` and `user.js`. Costs the reader-mode custom colours — see below |

### Stylix — needs a rebuild to follow

| what | why it cannot move |
|---|---|
| fonts | Noctalia has no font templating at all |
| cursor theme | same |
| Qt / Kvantum | the `qt` template has **no `post_hook`**, so the `qt{5,6}ct/colors/noctalia.conf` it writes is never selected; and there is no Kvantum template in either catalogue |
| niri focus ring | the `niri` template needs `include "noctalia.kdl"`, which niri-stable 25.08 rejects: `unexpected node 'include'` |
| starship, fish | hand-written against palette names |

`papirus-icons` is in neither column: its hook reads `/usr/share/icons/$variant`,
which does not exist on NixOS, so it skips every variant and does nothing.
Making it work would need a template of our own — see below.

## Gotchas worth remembering

**Template ids are not validated.** `noctalia config validate` accepts a
misspelled builtin *or* community id without a word; the only symptom is a theme
that never appears. `btop` in particular is a *builtin* template even though
most of this list is community. Check new ids against the live catalogue:

```sh
jq -r '.[].name' ~/.local/state/noctalia/community-templates/catalog.json | sort
```

**Community templates come from the network**, not from the Noctalia package —
they are fetched from `api.noctalia.dev` and cached in
`~/.local/state/noctalia/community-templates`. On a machine that has never had
network since install, only the builtin ones work.

**fastfetch's hook refuses to create its config**, and insists the file be
strict JSON — it `jq`-merges into it and says so loudly if it finds the comments
or trailing commas that `.jsonc` otherwise allows. Hence the seed in `cli.nix`,
written with `builtins.toJSON` and installed as a real writable file only when
absent. Editing the Nix source will **not** reach a machine that already has the
file; delete it and rebuild, or edit it in place.

**zellij does not repaint a running session.** It watches `config.kdl`, and what
a palette switch changes is `themes/noctalia.kdl`. The template ships a
`touch config.kdl` post_hook for exactly this, commented out upstream — and it
could not work here anyway, since `config.kdl` is a home-manager store symlink.
New sessions get the new palette immediately; an open one needs restarting.
It is also the one app here whose Stylix target was *already* doing nothing:
`stylix.targets.zellij` writes `themes/stylix.kdl` but never sets `theme`, so
nothing ever selected it and zellij had been running unthemed all along.

**Zen keeps its chrome, loses its reader mode.** The Stylix target set seven
prefs on the profile. Three named fonts that `fonts.nix` already makes
fontconfig resolve to, so dropping them changes nothing; one was
`toolkit.legacyUserProfileCustomizations.stylesheets`, which the hook writes into
`user.js` itself. The other five were `reader.custom_colors.*`, and those are
simply gone — reader mode falls back to Zen's built-in light/dark/sepia. They
cannot be kept: anything left in `profiles.<n>.settings` makes home-manager write
`user.js` as a store symlink, and the hook's `touch` on it fails before it does
anything else. Note also that the hook finds profiles by looking for `prefs.js`
two levels under `~/.config/zen`, so it is inert until Zen has been run once, and
that its two template entries share one `apply.sh` with the `hook_async = false`
meant to serialise them unimplemented in this version — a race can leave a
duplicate `@import`, which the next apply cleans up.

**Stylix targets exist in two scopes, and they are different lists.** Most are
home-manager targets, reachable as `stylix.targets.<name>` from a module under
`modules/home/`. A few are NixOS targets and can only be switched off from
`modules/nixos/stylix.nix` — `chromium` is one, and checking only the
home-manager scope will tell you it does not exist. To see the NixOS list:

```sh
nix eval .#nixosConfigurations.nnn-desktop.config.stylix.targets --apply 'builtins.attrNames'
```

That one cost an hour. Stylix's chromium target turns `programs.chromium` on
purely to write `{"BrowserThemeColor": "<base00>"}` into
`/etc/chromium/policies/managed/extra.json`, and per Chrome Enterprise that
policy makes the theme **admin-managed** — "users won't be able to change the
theme set by the policy". A Chromium theme is an extension, so loading the
Noctalia one fails with *"Noctalia (extension ID …) is blocked by the
administrator"*, which reads like a broken extension and is really that policy.
Nothing in the file is a blocklist; the NixOS module writes only `extraOpts`.

**Three hooks refuse to bootstrap their own config.** `fastfetch` errors out,
`cava` exits 1, and `btop` warns and exits 0 — all three when the app's config
file does not exist yet, which is exactly the state a fresh machine is in, and
the state `btop.conf` lands in the moment home-manager stops writing it. Each is
seeded from Nix as a real writable file, only when absent (`cli.nix` for
fastfetch and btop, `apps.nix` for cava). `bat`, `lazygit` and `yazi` do create
their own, so they need nothing.

**fzf's snippet appends to a universal variable.** It ends with
`set -Ux FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS\n<theme opts>"`, and universals
persist in `fish_variables`, so sourcing it once per shell would grow the value
without bound. `fish.nix` erases the variable before sourcing.

## Adding an app

1. Find the id: `jq -r '.[].name' ~/.local/state/noctalia/community-templates/catalog.json`.
2. Read its `apply.sh` — decide whether it appends or overwrites, and which file
   it touches: `curl -sL https://api.noctalia.dev/templates/<id>/apply.sh`.
3. Make sure home-manager does not write that file. Usually
   `stylix.targets.<app>.enable = false;`. Check with:
   ```sh
   nix eval --json .#nixosConfigurations.nnn-desktop.config.home-manager.users.sundial.home.file \
     --apply 'x: builtins.attrNames x' | jq -r '.[]' | grep <app>
   ```
   An empty result is what you want.
4. Add the id to `theme.templates.community_ids` (or `builtin_ids`) in
   `modules/home/noctalia.nix`.
5. Rebuild, then `noctalia msg templates-apply`, then check
   `journalctl --user -u noctalia -n 50` — a hook that hit a read-only symlink
   shows up there as a non-zero exit.

Writing one from scratch is also supported: `theme.templates.user.<id>` takes
`input_path`, `output_path` (or `output_path_dynamic`), `pre_hook`, `post_hook`,
`post_action` and `requires_path`. That is the escape hatch for a broken
upstream template — papirus-icons being the obvious candidate, seeding from
`pkgs.papirus-icon-theme` and calling `pkgs.papirus-folders` instead of reading
`/usr/share`.
