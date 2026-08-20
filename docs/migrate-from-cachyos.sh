#!/usr/bin/env bash
# One-off migration of user data from the CachyOS install on the NVMe.
#
# This is a transfer, not configuration: everything here is state that cannot be
# generated from the repository. Anything that CAN be generated is deliberately
# absent — .gitconfig is produced by modules/home/git.nix (including the
# insteadOf rule and the libsecret helper), .ssh/config likewise, and the ssh
# keys themselves come from sops.
#
# Mount the source read-only first, so a mistake here cannot damage CachyOS:
#   sudo mount -o ro,subvolid=5 \
#     /dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7283A9CB50-part2 /mnt/cachy
#
# Usage: migrate-from-cachyos.sh [stage ...]   (no args = all safe stages)
set -euo pipefail

SRC=/mnt/cachy/@home/sundial
DST="$HOME"

# --no-owner/--no-group: CachyOS puts the user in gid 1000, NixOS in gid 100
# (users). Without these every copied file lands with a group that does not
# exist here.
RSYNC=(rsync -a --no-owner --no-group --human-readable --info=stats1)

[ -d "$SRC" ] || { echo "source not mounted at $SRC" >&2; exit 1; }

stage_clean() {
  # Directories with no counterpart on this machine — nothing to conflict with.
  for p in .factorio .logseq JoplinBackup .gnupg .dotnet \
           .config/vesktop .config/Element .config/qBittorrent \
           .config/MangoHud .config/vkBasalt .config/obsidian; do
    [ -e "$SRC/$p" ] || continue
    mkdir -p "$(dirname "$DST/$p")"
    echo ":: $p"
    "${RSYNC[@]}" "$SRC/$p/" "$DST/$p/"
  done
}

stage_work() {
  # Build output is excluded: 6.5G of the 8.1G in Repos is .angular, node_modules
  # and bin/obj, all of which regenerate. Dumps stays behind (re-dumpable), and
  # workspace-setup.zip is just the zipped copy of the directory next to it.
  echo ":: Work"
  "${RSYNC[@]}" \
    --exclude 'Dumps/' \
    --exclude 'workspace-setup.zip' \
    --exclude 'Repos/**/node_modules/' \
    --exclude 'Repos/**/.angular/' \
    --exclude 'Repos/**/bin/' \
    --exclude 'Repos/**/obj/' \
    "$SRC/Work/" "$DST/Work/"
}

stage_documents() {
  # Vaults holds EFKO and LongBoiPersonal, which are already in ~/Notes as git
  # repos, plus EFKO_Vault — the stale duplicate with leftover logseq folders.
  echo ":: Documents"
  "${RSYNC[@]}" --exclude 'Vaults/' "$SRC/Documents/" "$DST/Documents/"
}

stage_pictures() {
  # Only Screenshots and the avatars: Pictures/Wallpapers is already here as
  # ~/Pictures/wallpapers, seeded from the repository.
  echo ":: Pictures"
  "${RSYNC[@]}" "$SRC/Pictures/Screenshots/" "$DST/Pictures/Screenshots/"
  "${RSYNC[@]}" "$SRC/Pictures/"*.png "$DST/Pictures/"
}

stage_downloads() {
  # The EndeavourOS ISO is 3.5G of the 4.5G and already written to a USB stick.
  echo ":: Downloads"
  "${RSYNC[@]}" --exclude 'EndeavourOS_*.iso' "$SRC/Downloads/" "$DST/Downloads/"
}

stage_compatdata() {
  # Prefix 0 is Steam's shared runtime prefix, not a save, and the copy here is
  # four weeks newer. 1493710 is also newer here. Both are left alone; the other
  # sixteen prefixes do not exist on this machine at all.
  local cd=.local/share/Steam/steamapps/compatdata
  echo ":: compatdata"
  mkdir -p "$DST/$cd"
  "${RSYNC[@]}" --exclude '/0/' --exclude '/1493710/' "$SRC/$cd/" "$DST/$cd/"
}


stage_claude() {
  # Transcripts are named by session uuid, so nothing collides; --ignore-existing
  # is belt and braces. settings.json is already identical on both sides, and
  # ~/.claude.json is deliberately untouched: the copy here is the live one.
  echo ":: .claude (projects + plans only)"
  rsync -a --no-owner --no-group --ignore-existing \
    "$SRC/.claude/projects/" "$DST/.claude/projects/"
  rsync -a --no-owner --no-group --ignore-existing \
    "$SRC/.claude/plans/" "$DST/.claude/plans/"
}

stage_fish_history() {
  # fish history is a sequence of "- cmd:/  when:" blocks. Concatenating and
  # letting fish sort it out does not work — duplicates stay. awk keeps the
  # first occurrence of each command, which is what fish's own dedup does.
  local f="$DST/.local/share/fish/fish_history"
  echo ":: fish_history"
  cp -a "$f" "$f.pre-migration"
  awk '
    /^- cmd: / { key = substr($0, 9); if (key in seen) { skip = 1; next } seen[key] = 1; skip = 0 }
    /^[^ -]/ && !/^- cmd: / { skip = 0 }
    !skip { print }
  ' "$SRC/.local/share/fish/fish_history" "$f" > "$f.merged"
  mv "$f.merged" "$f"
}

stage_zen() {
  # Zen MUST be closed: these are live sqlite databases.
  #
  # Extensions are excluded on purpose — they become declarative in the nix
  # config, and a copied extensions/ would fight the declared set. Their
  # settings still come across in storage-sync-v2.sqlite.
  #
  # compatibility.ini is excluded too: it pins the profile to the application
  # path and version it last ran under, and carrying CachyOS's copy over makes
  # zen think the profile belongs to a different install.
  local src="$SRC/.config/zen/ifa6vo0k.Default (release)"
  local dst="$DST/.config/zen/default"
  pgrep -x zen >/dev/null && { echo "zen is running — close it first" >&2; return 1; }
  echo ":: zen profile"
  cp -a "$dst" "$dst.pre-migration"
  "${RSYNC[@]}" \
    --exclude 'extensions/' --exclude 'extensions.json' \
    --exclude 'extension-settings.json' --exclude 'extension-preferences.json' \
    --exclude 'addonStartup.json.lz4' --exclude 'extension-store*' \
    --exclude 'chrome/' --exclude 'user.js' --exclude 'compatibility.ini' \
    --exclude 'storage/default/moz-extension*' \
    --exclude 'datareporting/' --exclude 'gmp*/' --exclude 'security_state/' \
    --exclude 'features/' --exclude 'settings/' --exclude 'lock' \
    "$src/" "$dst/"
}

if [ $# -eq 0 ]; then
  set -- clean work documents pictures downloads compatdata claude fish_history
fi
for s in "$@"; do "stage_$s"; done
echo "done: $*"
