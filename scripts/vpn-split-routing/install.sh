#!/usr/bin/env bash
# install.sh
# Установка актуальной раздельной маршрутизации Happ + snx-rs на CachyOS / Arch Linux
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ":: 1. Установка скрипта маршрутизации в /usr/local/bin/..."
cp "$DIR/snx-vpn-routing.sh" /usr/local/bin/snx-vpn-routing.sh
chmod +x /usr/local/bin/snx-vpn-routing.sh

echo ":: 2. Установка systemd сервисов..."
cp "$DIR/snx-vpn-routing.service" /etc/systemd/system/
cp "$DIR/snx-vpn-routing-trigger.service" /etc/systemd/system/

echo ":: 3. Установка хука NetworkManager..."
mkdir -p /etc/NetworkManager/dispatcher.d
cp "$DIR/99-snx-vpn-routing.sh" /etc/NetworkManager/dispatcher.d/99-snx-vpn-routing.sh
chmod +x /etc/NetworkManager/dispatcher.d/99-snx-vpn-routing.sh

echo ":: 4. Настройка loose reverse path filtering (RP-filter) для туннеля snx..."
# Предотвращает отбрасывание keepalive-пакетов ядром Linux
cat > /etc/sysctl.d/99-vpn-rpfilter.conf << 'EOF'
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF
sysctl --system >/dev/null

echo ":: 5. Активация и запуск служб..."
systemctl daemon-reload
systemctl enable --now snx-vpn-routing.service
systemctl enable snx-vpn-routing-trigger.service

echo "=== Готово! Актуальная раздельная маршрутизация установлена и активна! ==="
