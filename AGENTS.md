# Agent Guidelines & Allowed Commands

This document defines the execution rules, guidelines, and pre-approved command sets for AI agents operating within this repository and workspace.

## Allowed & Pre-Approved Commands

Agents are authorized to run the following categories of commands directly for inspection, diagnostics, research, and workspace maintenance:

### 1. File & Codebase Inspection
- `ls`, `find`, `grep`, `rg`, `file`, `stat`, `diff`, `tree`, `wc`
- `cat`, `head`, `tail`, `awk`, `sed`, `cut`, `sort`, `uniq`

### 2. Git & Version Control
- `git status`, `git diff`, `git log`, `git show`, `git branch`
- `git rev-parse`, `git ls-files`, `git remote`, `git checkout`
- `git fetch`, `git clone` (read-only / repository sync)

### 3. Network & Documentation Retrieval
- `curl` (API inspection, GitHub raw/content fetching, doc verification with `-s` / `-sL`)
- `wget` (downloading docs or reference assets)
- `ping`, `ip`, `ss`, `dig`, `host` (network diagnostics)

### 4. System, Process & Hardware Diagnostics
- `uname`, `lscpu`, `lspci`, `lsusb`, `dmidecode`
- `uptime`, `free`, `df`, `du`, `ps`, `pgrep`
- `journalctl`, `dmesg`
- `systemctl status`, `systemctl is-active`, `systemctl list-units`

### 5. Storage, Partitioning & Snapshots (Read-Only)
- `lsblk`, `mount`, `findmnt`
- `btrfs subvolume list`, `btrfs subvolume show`
- `btrfs filesystem df`, `btrfs filesystem show`
- `snapper list`, `snapper status`

### 6. Package Management & Querying
- `pacman -Q*`, `pacman -Si`, `pacman -Ss`
- `paru -Q*`, `paru -Si`, `yay -Q*`
- `nix-store`, `nixos-version`, `nix flake metadata`

---

## Operating Principles for Agents

1. **Autonomous Inspection:** Run read-only, discovery, and diagnostic commands proactively without asking the user for confirmation.
2. **Safe Mutation:** Any potentially destructive operation (e.g. disk reformatting, non-reversible data deletion, forced Git pushes) must always be explicitly stated and reviewed.
3. **Reproducibility & Modularity:** Adhere to clean modular structures for configuration files (Niri KDL, Noctalia TOML/CSS, Chezmoi templates, Shell scripts).


