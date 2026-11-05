#!/usr/bin/env bash
# backup-to-additional500.sh
# Резервное копирование критических данных перед переустановкой на CachyOS + LUKS.
# Целевой диск: /run/media/sundial/Additional_500 (доступно ~60 ГБ)
set -euo pipefail

DEST="/run/media/sundial/Additional_500/NIXOS_BACKUP_$(date +%Y%m%d_%H%M%S)"
echo "=== Создание резервной копии в: $DEST ==="
mkdir -p "$DEST"

RSYNC=(rsync -a --human-readable --info=progress2,stats1)

# 1. Личные документы, изображения, заметки
echo -e "\n:: 1/7 Копирование Documents, Pictures, Notes..."
"${RSYNC[@]}" "$HOME/Documents/" "$DEST/Documents/"
"${RSYNC[@]}" "$HOME/Pictures/" "$DEST/Pictures/"
"${RSYNC[@]}" "$HOME/Notes/" "$DEST/Notes/"

# 2. Рабочие проекты (Work) без сборочного мусора
echo -e "\n:: 2/7 Копирование Work (без node_modules, .angular, bin, obj)..."
"${RSYNC[@]}" \
  --exclude 'node_modules/' \
  --exclude '.angular/' \
  --exclude 'bin/' \
  --exclude 'obj/' \
  --exclude '.cache/' \
  "$HOME/Work/" "$DEST/Work/"

# 3. Сохранения игр (Lutris, Wine-префиксы, Steam compatdata)
echo -e "\n:: 3/7 Копирование сохранений игр..."
mkdir -p "$DEST/GameSaves"

# Явные бэкапы сейвов
if [ -d "$HOME/Games/SaveFiles" ]; then
  "${RSYNC[@]}" "$HOME/Games/SaveFiles/" "$DEST/GameSaves/SaveFiles/"
fi
if [ -d "$HOME/Games/Save_backups" ]; then
  "${RSYNC[@]}" "$HOME/Games/Save_backups/" "$DEST/GameSaves/Save_backups/"
fi

# Сейвы из префиксов ~/Games (AppData, Saved Games, STALKER)
for pfx in "$HOME/Games"/*_prefix "$HOME/Games"/sekiro "$HOME/Games"/MWC*; do
  [ -d "$pfx" ] || continue
  name=$(basename "$pfx")
  u_dir="$pfx/drive_c/users/steamuser"
  if [ -d "$u_dir/Saved Games" ]; then
    mkdir -p "$DEST/GameSaves/prefixes/$name/Saved Games"
    "${RSYNC[@]}" "$u_dir/Saved Games/" "$DEST/GameSaves/prefixes/$name/Saved Games/"
  fi
  if [ -d "$u_dir/AppData/Roaming" ]; then
    mkdir -p "$DEST/GameSaves/prefixes/$name/AppData/Roaming"
    "${RSYNC[@]}" "$u_dir/AppData/Roaming/" "$DEST/GameSaves/prefixes/$name/AppData/Roaming/"
  fi
  if [ -d "$u_dir/AppData/Local" ]; then
    mkdir -p "$DEST/GameSaves/prefixes/$name/AppData/Local"
    "${RSYNC[@]}" "$u_dir/AppData/Local/" "$DEST/GameSaves/prefixes/$name/AppData/Local/"
  fi
done

# Сейвы STALKER Anomaly
if [ -d "$HOME/Games/STALKER" ]; then
  mkdir -p "$DEST/GameSaves/STALKER"
  find "$HOME/Games/STALKER" -maxdepth 3 -type d -name "*save*" -exec rsync -a {} "$DEST/GameSaves/STALKER/" \; 2>/dev/null || true
fi

# Сейвы Steam compatdata (только AppData и Saved Games из префиксов)
echo ":: Сбор сейвов из Steam compatdata..."
mkdir -p "$DEST/GameSaves/SteamCompatdata"
find "$HOME/.local/share/Steam/steamapps/compatdata" -maxdepth 6 -type d \( -name "Saved Games" -o -name "Roaming" \) 2>/dev/null | while read -r d; do
  appid=$(echo "$d" | awk -F'/compatdata/' '{print $2}' | cut -d'/' -f1)
  mkdir -p "$DEST/GameSaves/SteamCompatdata/$appid"
  rsync -a "$d/" "$DEST/GameSaves/SteamCompatdata/$appid/$(basename "$d")/" 2>/dev/null || true
done

# 4. База и профили Lutris
echo -e "\n:: 4/7 Копирование Lutris metadata и pga.db..."
mkdir -p "$DEST/Lutris"
"${RSYNC[@]}" --exclude 'runners/' --exclude 'runtime/' "$HOME/.local/share/lutris/" "$DEST/Lutris/"

# 5. Ключи и авторизация (SSH, GPG, Claude)
echo -e "\n:: 5/7 Копирование SSH, GPG, Claude..."
"${RSYNC[@]}" "$HOME/.ssh/" "$DEST/.ssh/"
"${RSYNC[@]}" "$HOME/.gnupg/" "$DEST/.gnupg/"
if [ -d "$HOME/.claude" ]; then
  "${RSYNC[@]}" --exclude 'cache/' "$HOME/.claude/" "$DEST/.claude/"
fi

# 6. Конфиги приложений и история
echo -e "\n:: 6/7 Копирование конфигов (~/.config) и fish_history..."
mkdir -p "$DEST/.config"
for c in vesktop Element obsidian qBittorrent zen niri noctalia dbeaver; do
  if [ -d "$HOME/.config/$c" ]; then
    "${RSYNC[@]}" --exclude 'Cache*' --exclude 'GPUCache*' "$HOME/.config/$c/" "$DEST/.config/$c/"
  fi
done

mkdir -p "$DEST/.local/share/fish"
if [ -f "$HOME/.local/share/fish/fish_history" ]; then
  cp -a "$HOME/.local/share/fish/fish_history" "$DEST/.local/share/fish/"
fi

# 7. Сам репозиторий nixos-config (на всякий случай копия вместе с историей)
echo -e "\n:: 7/7 Резервная копия репозитория nixos-config..."
"${RSYNC[@]}" --exclude 'result' --exclude '.git/objects/pack/*.pack' "$HOME/nixos-config/" "$DEST/nixos-config/"

echo -e "\n========================================================"
echo " Резервное копирование завершено успешно!"
echo " Папка: $DEST"
echo " Занятое место:"
du -sh "$DEST"
echo "========================================================"
