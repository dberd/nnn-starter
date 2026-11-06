#!/bin/sh
# /etc/NetworkManager/dispatcher.d/99-snx-vpn-routing.sh
action="$2"

case "$action" in
  up | down | vpn-up | vpn-down | dhcp4-change | dhcp6-change) ;;
  *) exit 0 ;;
esac

exec /usr/bin/systemctl restart --no-block snx-vpn-routing.service
