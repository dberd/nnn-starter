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

# 3. Сохранения игр и конфигурации модов
echo -e "\n:: 3/6 Копирование сохранений игр и конфигураций модов..."
mkdir -p "$DEST/GameSaves"

# Явные бэкапы сейвов
if [ -d "$HOME/Games/SaveFiles" ]; then
  "${RSYNC[@]}" "$HOME/Games/SaveFiles/" "$DEST/GameSaves/SaveFiles/"
fi
if [ -d "$HOME/Games/Save_backups" ]; then
  "${RSYNC[@]}" "$HOME/Games/Save_backups/" "$DEST/GameSaves/Save_backups/"
fi

# Сейвы из префиксов ~/Games (AppData, Saved Games, MWC, Sekiro, AC4)
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

# STALKER Anomaly / GAMMA: сейвы + профили и модлисты (modlist.txt, lockedorder.txt, plugins.txt)
if [ -d "$HOME/Games/STALKER" ]; then
  echo ":: Копирование сейвов, профилей и модлистов STALKER..."
  mkdir -p "$DEST/GameSaves/STALKER"
  
  # Профили MO2 / GAMMA (где лежат modlist.txt и lockedorder.txt)
  if [ -d "$HOME/Games/STALKER/GAMMA/profiles" ]; then
    mkdir -p "$DEST/GameSaves/STALKER/GAMMA_profiles"
    "${RSYNC[@]}" "$HOME/Games/STALKER/GAMMA/profiles/" "$DEST/GameSaves/STALKER/GAMMA_profiles/"
  fi

  # Резервные копии конфигов и модлистов
  for cb in "$HOME/Games/STALKER"/config-backup-*; do
    [ -d "$cb" ] || continue
    mkdir -p "$DEST/GameSaves/STALKER/$(basename "$cb")"
    "${RSYNC[@]}" "$cb/" "$DEST/GameSaves/STALKER/$(basename "$cb")/"
  done

  # Сейвы и настройки Anomaly (appdata/savedgames, user.ltx)
  if [ -d "$HOME/Games/STALKER/ANOMALY/appdata" ]; then
    mkdir -p "$DEST/GameSaves/STALKER/ANOMALY_appdata"
    "${RSYNC[@]}" \
      --include 'savedgames/***' \
      --include 'user.ltx' \
      --exclude '*' \
      "$HOME/Games/STALKER/ANOMALY/appdata/" "$DEST/GameSaves/STALKER/ANOMALY_appdata/"
  fi
fi

# Сейвы Steam compatdata (только AppData и Saved Games из префиксов)
echo ":: Сбор сейвов из Steam compatdata..."
mkdir -p "$DEST/GameSaves/SteamCompatdata"
find "$HOME/.local/share/Steam/steamapps/compatdata" -maxdepth 6 -type d \( -name "Saved Games" -o -name "Roaming" \) 2>/dev/null | while read -r d; do
  appid=$(echo "$d" | awk -F'/compatdata/' '{print $2}' | cut -d'/' -f1)
  mkdir -p "$DEST/GameSaves/SteamCompatdata/$appid"
  rsync -a "$d/" "$DEST/GameSaves/SteamCompatdata/$appid/$(basename "$d")/" 2>/dev/null || true
done

# 4. Ключи, авторизация и сессии AI (SSH, GPG, Claude, Antigravity/agy)
echo -e "\n:: 4/6 Копирование SSH, GPG, Claude и сессий Antigravity (agy)..."
"${RSYNC[@]}" "$HOME/.ssh/" "$DEST/.ssh/"
"${RSYNC[@]}" "$HOME/.gnupg/" "$DEST/.gnupg/"

if [ -d "$HOME/.claude" ]; then
  "${RSYNC[@]}" --exclude 'cache/' "$HOME/.claude/" "$DEST/.claude/"
fi

# Antigravity CLI сессии, базы чатов и артефакты (~/.gemini)
if [ -d "$HOME/.gemini" ]; then
  echo ":: Копирование сессий и базы данных Antigravity (~/.gemini)..."
  "${RSYNC[@]}" \
    --exclude 'cache/' \
    --exclude 'log/' \
    --exclude 'crashes/' \
    "$HOME/.gemini/" "$DEST/.gemini/"
fi

# Экспорт текущего чата в человекочитаемый markdown файл
mkdir -p "$DEST/ChatHistory"
if [ -f "$HOME/nixos-config/docs/chat-cachyos-migration-plan.md" ]; then
  cp -a "$HOME/nixos-config/docs/chat-cachyos-migration-plan.md" "$DEST/ChatHistory/chat-cachyos-migration-plan.md"
fi

# 5. Конфиги приложений и история
echo -e "\n:: 5/6 Копирование конфигов (~/.config) и fish_history..."
mkdir -p "$DEST/.config"
for c in vesktop Element obsidian qBittorrent zen niri noctalia dbeaver; do
  if [ -d "$HOME/.config/$c" ]; then
    "${RSYNC[@]}" --exclude 'Cache*' --exclude 'GPUCache*' "$HOME/.config/$c/" "$DEST/.config/$c/"
  fi
done

# Отдельно сохраняем разыменованные (настоящие текстовые) конфиги Niri и Noctalia,
# так как в NixOS ~/.config/niri/config.kdl — это симлинк в /nix/store, который на CachyOS станет битым.
echo ":: Сохранение эталонных текстовых конфигов Niri и Noctalia (Reference_Configs)..."
mkdir -p "$DEST/Reference_Configs/niri" "$DEST/Reference_Configs/noctalia"
cp -L "$HOME/.config/niri/config.kdl" "$DEST/Reference_Configs/niri/config.kdl"
[ -f "$HOME/.config/niri/noctalia.kdl" ] && cp -a "$HOME/.config/niri/noctalia.kdl" "$DEST/Reference_Configs/niri/noctalia.kdl"
cp -L "$HOME/.config/noctalia/config.toml" "$DEST/Reference_Configs/noctalia/config.toml"
[ -f "$HOME/.local/state/noctalia/settings.toml" ] && cp -a "$HOME/.local/state/noctalia/settings.toml" "$DEST/Reference_Configs/noctalia/settings.toml"
[ -f "$HOME/.local/state/noctalia/state.toml" ] && cp -a "$HOME/.local/state/noctalia/state.toml" "$DEST/Reference_Configs/noctalia/state.toml"
[ -d "$HOME/.local/state/noctalia/plugins" ] && cp -r "$HOME/.local/state/noctalia/plugins" "$DEST/Reference_Configs/noctalia/"

mkdir -p "$DEST/.local/share/fish"
if [ -f "$HOME/.local/share/fish/fish_history" ]; then
  cp -a "$HOME/.local/share/fish/fish_history" "$DEST/.local/share/fish/"
fi

# 6. Сам репозиторий nixos-config (на всякий случай копия вместе с историей)
echo -e "\n:: 6/6 Резервная копия репозитория nixos-config..."
"${RSYNC[@]}" --exclude 'result' --exclude '.git/objects/pack/*.pack' "$HOME/nixos-config/" "$DEST/nixos-config/"

echo -e "\n========================================================"
echo " Резервное копирование завершено успешно!"
echo " Папка: $DEST"
echo " Занятое место:"
du -sh "$DEST"
echo "========================================================"
