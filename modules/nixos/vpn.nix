# VPN stack: Throne (general-purpose TUN proxy, replaces happ) + snx-rs
# (Check Point corporate VPN), plus the split-routing fix that makes the two
# coexist.
{
  pkgs,
  username,
  ...
}: {
  # ── Throne ────────────────────────────────────────────────────────────────
  # GUI proxy manager on top of sing-box. The upstream NixOS module does the
  # privileged parts for us: a security.wrappers entry giving ThroneCore
  # cap_net_admin/net_raw/net_bind_service (instead of upstream's setuid), and a
  # polkit rule so TUN mode can talk to systemd-resolved without prompting for a
  # password three times per connect.
  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

  # ── snx-rs ────────────────────────────────────────────────────────────────
  # Open-source Check Point (SNX) client. No NixOS module upstream, so the
  # daemon is wired up by hand, mirroring how it ran on the previous distro.
  #
  # `-m command` means the daemon just sits and waits: it does NOT connect on
  # its own. Connecting is `snxctl connect`, run as the user, and snxctl is what
  # reads the profile — from ~/.config/snx-rs/snx-rs.conf. That file holds the
  # corporate login and password, which is why it is neither in this repo nor
  # in /etc. (Migration target: sops-nix.)
  environment.systemPackages = [pkgs.snx-rs];

  systemd.services.snx-rs = {
    description = "snx-rs Check Point VPN core";
    after = ["network.target" "network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.snx-rs}/bin/snx-rs -m command -l info";
      Restart = "always";
      RestartSec = 10;
      LimitNOFILE = 65536;
    };
  };

  # ── Split routing ─────────────────────────────────────────────────────────
  # Ported from ~/Work/workspace-setup/vpn/snx-happ-routing.sh (happ → Throne;
  # the mechanism is identical because both are sing-box front-ends, and the
  # table/priority numbers below are sing-box's own defaults).
  #
  # Rules are evaluated lowest-priority-first, so ours land ahead of sing-box's
  # 9000-9010 block regardless of start order. Two things must bypass the TUN:
  #
  #   1. The efko gateways themselves — SNX builds its SSL/ESP tunnel *to* them,
  #      and running that inside the proxy tunnel either fails or sends all
  #      corporate traffic through the VPN provider.
  #   2. Corporate networks, which snx-rs installs into table 18000. That table
  #      is empty until snx connects, so the rule is harmless when it isn't.
  systemd.services.snx-vpn-routing = {
    description = "snx-rs + Throne split routing fix";
    after = ["network-online.target" "snx-rs.service"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [iproute2 gawk glibc.bin coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -e

      SNX_CONF=/home/${username}/.config/snx-rs/snx-rs.conf

      # Static public ranges of the efko gateways — always direct, never via TUN.
      EFKO_GW_NETS="195.239.33.0/24 77.105.188.0/24 213.129.115.0/24"

      # Physical uplink and gateway, both taken from the current default route.
      # Virtual interfaces are filtered out: picking our own tun would loop the
      # route back into the tunnel we are trying to bypass.
      read -r DEV LAN_GW <<<"$(ip -4 route show default table main 2>/dev/null | awk '
          {d=""; g=""
           for (i = 1; i <= NF; i++) { if ($i == "dev") d = $(i+1); if ($i == "via") g = $(i+1) }
           if (d != "" && d !~ /^(tun|veth|docker|br-|wg)/) { print d, g; exit }}')"

      [ -z "$DEV" ] && { echo "snx-vpn-routing: no physical default route" >&2; exit 1; }
      [ -z "$LAN_GW" ] && { echo "snx-vpn-routing: no gateway on $DEV" >&2; exit 1; }

      # Plus the gateway the profile currently points at, in case it is one not
      # covered by the static list above.
      SERVER=$(awk -F= '/^server-name=/{print $2; exit}' "$SNX_CONF" 2>/dev/null | tr -d '[:space:]')
      GW_SNX=$(getent hosts "$SERVER" 2>/dev/null | awk '{print $1; exit}')

      TARGETS="$EFKO_GW_NETS"
      [ -n "$GW_SNX" ] && TARGETS="$TARGETS ''${GW_SNX}/32"
      TARGETS=$(printf '%s\n' $TARGETS | sort -u)

      # 1) Every target gateway goes straight out the physical router (table 100).
      for t in $TARGETS; do
          ip route replace "$t" via "$LAN_GW" dev "$DEV" table 100
      done

      # 2) Rules, idempotently: wipe our priority block, then re-add.
      for p in {4900..4919} 5000 5100; do ip rule del priority $p 2>/dev/null || true; done
      prio=4900
      for t in $TARGETS; do
          ip rule add to "$t" lookup 100 priority $prio
          prio=$((prio+1))
      done

      # 3) Corporate traffic via snx-rs's table, ahead of sing-box's rules.
      ip rule add from all lookup 18000 priority 5100
    '';
  };
}
