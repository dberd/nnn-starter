#!/usr/bin/env bash
# snx-vpn-routing.sh
# Актуальный скрипт раздельной маршрутизации Happ / sing-box (TUN) + snx-rs (Check Point VPN).
# Перенесён из боевого модуля NixOS (modules/nixos/vpn.nix) со всеми фиксами:
#   - Определение живого сокета snx-rs (GW_LIVE)
#   - Ожидание инициализации таблицы 18000 и резолвера (исключает гонку)
#   - Явная маршрутизация внутренних корпоративных DNS-серверов
#   - Приоритет поискового домена efko.ru в systemd-resolved (для коротких имен)
#   - Защита nftables от перехвата sing-box (метки bypass 0x2024 и DNAT сам на себя)
set -e

SNX_USER="sundial"
SNX_CONF="/home/$SNX_USER/.config/snx-rs/snx-rs.conf"

# Статические публичные диапазоны шлюзов efko — всегда напрямую через физ. роутер
EFKO_GW_NETS="195.239.33.0/24 77.105.188.0/24 213.129.115.0/24"

# Физический интерфейс и шлюз из текущего маршрута по умолчанию
read -r DEV LAN_GW <<<"$(ip -4 route show default table main 2>/dev/null | awk '
    {d=""; g=""
     for (i = 1; i <= NF; i++) { if ($i == "dev") d = $(i+1); if ($i == "via") g = $(i+1) }
     if (d != "" && d !~ /^(tun|veth|docker|br-|wg)/) { print d, g; exit }}')"

[ -z "$DEV" ] && { echo "snx-vpn-routing: нет физического default route, выход"; exit 0; }
[ -z "$LAN_GW" ] && { echo "snx-vpn-routing: нет шлюза на $DEV, выход"; exit 0; }

# Шлюз из профиля
SERVER=$(awk -F= '/^server-name=/{print $2; exit}' "$SNX_CONF" 2>/dev/null | tr -d '[:space:]')
GW_SNX=""
[ -n "$SERVER" ] && GW_SNX=$(getent hosts "$SERVER" 2>/dev/null | awk '{print $1; exit}')

# Живой шлюз, с которым snx-rs реально установил соединение
GW_LIVE=$(ss -tnpH 2>/dev/null | awk '/snx-rs/ {
    for (i = NF; i > 0; i--) if ($i ~ /^[0-9.]+:[0-9]+$/) { print $i; exit }
  }' | awk -F: '{print $1}' | head -1)

TARGETS="$EFKO_GW_NETS"
[ -n "$GW_SNX" ] && TARGETS="$TARGETS ${GW_SNX}/32"
[ -n "$GW_LIVE" ] && TARGETS="$TARGETS ${GW_LIVE}/32"
TARGETS=$(printf '%s\n' $TARGETS | sort -u)

# 1) Все целевые шлюзы направляем напрямую через домашний роутер (table 100)
for t in $TARGETS; do
    ip route replace "$t" via "$LAN_GW" dev "$DEV" table 100
done

# 2) Правила ip rule: очищаем диапазон 4900..4919 и пересоздаем
for p in {4900..4919} 5000 5100; do ip rule del priority $p 2>/dev/null || true; done
prio=4900
for t in $TARGETS; do
    ip rule add to "$t" lookup 100 priority $prio
    prio=$((prio+1))
done

# 3) Корпоративный трафик направляем в таблицу snx-rs (18000) ПЕРЕД правилами sing-box/Happ (9000)
ip rule add from all lookup 18000 priority 5100

# 3a) Ожидание поднятия таблицы 18000 и DNS в resolved (до 20 секунд, устраняет race condition)
if ip link show snx-tun >/dev/null 2>&1; then
    for _ in $(seq 20); do
        [ -n "$(ip route show table 18000 2>/dev/null)" ] \
          && [ -n "$(resolvectl dns snx-tun 2>/dev/null | sed 's/^[^:]*://' | tr -d '[:space:]')" ] \
          && break
        sleep 1
    done
fi

# 4) Явная маршрутизация корпоративных DNS-серверов в snx-tun
SNX_DNS=$(resolvectl dns snx-tun 2>/dev/null \
  | sed 's/^[^:]*://' | tr ' ' '\n' | grep -E '^[0-9.]+$' || true)
for d in $SNX_DNS; do
    ip route replace "$d" dev snx-tun table 18000 2>/dev/null || true
done

# 4a) Резолв доменов: закрепляем search domain для коротких имен (dt-revproxy -> dt-revproxy.efko.ru)
if ip link show snx-tun >/dev/null 2>&1; then
    DOMS=$(resolvectl domain snx-tun 2>/dev/null | sed 's/^[^:]*://' \
      | tr ' ' '\n' | sed 's/^~//' | grep -E '^[a-zA-Z0-9][a-zA-Z0-9.-]*$' || true)
    [ -n "$DOMS" ] || DOMS=efko.ru
    resolvectl domain snx-tun $DOMS || true
fi

# 4b) Охват всей корпоративной сети 10.0.0.0/8 (страховка от неанонсированных шлюзом внутренних подсетей)
if [ -n "$(ip route show table 18000 2>/dev/null)" ]; then
    ip route replace 10.0.0.0/8 dev snx-tun table 18000 2>/dev/null || true
fi

# 5-6) Защита nftables от перехвата исходящего трафика модулями redirect sing-box
BYPASS_MARK=$(nft list chain inet sing-box output 2>/dev/null \
  | awk '$1 == "meta" && $2 == "mark" && $NF == "return" {print $3; exit}')
[ -n "$BYPASS_MARK" ] || BYPASS_MARK=0x2024

CORP=$(ip route show table 18000 2>/dev/null | awk '$1 ~ /^[0-9]/ {print $1}')
ELEMENTS=$(printf '%s\n' $TARGETS $CORP $SNX_DNS | sort -u | paste -sd, -)
if [ -n "$ELEMENTS" ]; then
    {
      echo "add table inet snx-bypass"
      echo "delete table inet snx-bypass"
      echo "table inet snx-bypass {"
      echo "  set corp {"
      echo "    type ipv4_addr"
      echo "    flags interval"
      echo "    auto-merge"
      echo "    elements = { $ELEMENTS }"
      echo "  }"
      echo "  chain output_mark {"
      echo "    type route hook output priority -200; policy accept;"
      echo "    ip daddr @corp meta mark set $BYPASS_MARK ct mark set meta mark counter accept"
      echo "  }"
      echo "  chain output {"
      echo "    type nat hook output priority -160; policy accept;"
      echo "    ip daddr @corp counter dnat ip to ip daddr"
      echo "  }"
      echo "}"
    } | nft -f -
fi

echo "snx-vpn-routing: маршрутизация успешно обновлена"
