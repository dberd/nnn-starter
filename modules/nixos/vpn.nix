# VPN stack: Throne (general-purpose TUN proxy, replaces happ) + snx-rs
# (Check Point corporate VPN), plus the split-routing fix that makes the two
# coexist.
{pkgs, ...}: {
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
  # daemon is wired up by hand.
  #
  # The config file holds the corporate login and password, so it is NOT in this
  # repo: create /etc/snx-rs/snx-rs.conf by hand, mode 0600, root-owned.
  # (Migration target: sops-nix + sops.templates.)
  environment.systemPackages = [pkgs.snx-rs];

  systemd.services.snx-rs = {
    description = "snx-rs Check Point VPN daemon";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    # Not wantedBy multi-user.target on purpose: connect on demand with
    # `systemctl start snx-rs` / the snx-rs tray app, like the old setup.
    serviceConfig = {
      ExecStart = "${pkgs.snx-rs}/bin/snx-rs -c /etc/snx-rs/snx-rs.conf";
      Restart = "on-failure";
    };
  };

  # ── Split routing ─────────────────────────────────────────────────────────
  # Ported from the old ~/snx-happ-routing.sh (happ → Throne; the mechanism is
  # identical because both are sing-box-style TUN clients that grab the default
  # route).
  #
  # Two things have to bypass the TUN:
  #   1. The efko SSL/IKE gateways themselves — otherwise the SNX underlay would
  #      try to run inside the very tunnel it is establishing.
  #   2. Corporate networks snx-rs installs in table 18000 — they must be
  #      consulted before Throne's own rules.
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

      SNX_CONF=/etc/snx-rs/snx-rs.conf

      # Static public ranges of the efko gateways — always direct, never via TUN.
      EFKO_GW_NETS="195.239.33.0/24 77.105.188.0/24 213.129.115.0/24"

      # Physical uplink: first default route in the main table that is not a
      # tunnel device. (The old script hardcoded enp5s0; deriving it keeps this
      # working on the laptop and after any NIC rename.)
      DEV=$(ip -4 -o route show default table main \
        | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1)}' \
        | awk '!/^(tun|utun|sing|throne|snx|wg|tap)/ {print; exit}')
      if [ -z "$DEV" ]; then
        echo "no physical default route found, nothing to do" >&2
        exit 0
      fi

      LAN_GW=$(ip -4 route show default dev "$DEV" table main | awk '{print $3; exit}')
      [ -z "$LAN_GW" ] && LAN_GW=192.168.1.254

      # Current gateway from the config, as a safety net for a gateway that is
      # not in the static list above.
      TARGETS="$EFKO_GW_NETS"
      if [ -r "$SNX_CONF" ]; then
        SERVER=$(awk -F= '/^server-name=/{print $2; exit}' "$SNX_CONF" | tr -d '[:space:]')
        if [ -n "$SERVER" ]; then
          GW_SNX=$(getent hosts "$SERVER" | awk '{print $1; exit}' || true)
          [ -n "$GW_SNX" ] && TARGETS="$TARGETS ''${GW_SNX}/32"
        fi
      fi
      TARGETS=$(printf '%s\n' $TARGETS | sort -u)

      # 1) Each target goes straight out the physical router (table 100).
      for t in $TARGETS; do
        ip route replace "$t" via "$LAN_GW" dev "$DEV" table 100
      done

      # 2) Rules, idempotently: wipe our priority block, then re-add.
      for p in $(seq 4900 4919) 5000 5100; do
        ip rule del priority "$p" 2>/dev/null || true
      done
      prio=4900
      for t in $TARGETS; do
        ip rule add to "$t" lookup 100 priority "$prio"
        prio=$((prio + 1))
      done

      # 3) Corporate traffic via snx-rs's table, ahead of the TUN client's rules.
      ip rule add from all lookup 18000 priority 5100
    '';
  };
}
