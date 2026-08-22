# VPN stack: Throne (general-purpose proxy) + snx-rs (Check Point corporate
# VPN), plus the split-routing fix that makes the two coexist.
#
# Throne stays for now, but the earlier note here overstated the case for it and
# is corrected: each of the three subscription nodes was run through plain
# sing-box 1.13.14 on a socks inbound of its own (22.08), and two of the three
# carried traffic.
#
#   LV  vless + tls + xtls-rprx-vision      works
#   FR  vless + reality + vision            "reality verification failed"
#   FR  hysteria2 + salamander obfs         works
#
# So Hysteria2 is not the obstacle — nixpkgs' sing-box is built with_quic and
# speaks it natively; that limitation belongs to the ruh-vpn plugin's server
# model, not to sing-box. Nor is REALITY, and this is where the earlier note was
# wrong: the same profile was put through Xray-core 26.3.27 — the very core
# Throne bundles — and it fails there too, with "received real certificate
# (potential MITM or redirection)". That is the same event sing-box reports as
# "reality verification failed": the server did not accept our keys, so it did
# what a REALITY server does with a stranger and passed us to the real site.
# fr.vavn.pro:443 duly answers with a genuine Let's Encrypt certificate for its
# own name, while Hysteria2 to the same host on UDP 443 carries traffic fine.
# Throne's own latency test on that profile recorded -1 the day it was imported.
# The node has never worked on this machine under any core; the subscription
# snapshot dates from 18.08 and wants refreshing before the profile is judged.
#
# What Throne is still the only thing providing: the tray icon, the server
# picker and the subscription updates. sing-box's own answer to that is the
# Clash API, which Throne's core exposes too (`core_box_clash_api` in its
# settings), so a widget of ours can drive either core over the same HTTP.
#
# The price is that Throne fights the corporate VPN, and not through routing:
# it works in nftables, ahead of the routing rules, and its output chain ends in
# two catch-alls with no exemption for RFC1918 — every DNS query is redirected
# to its own resolver, and every IPv4 TCP connection into its transparent proxy.
# Step 5 of the routing script below is what defuses both.
{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  # nixpkgs' snx-rs does not give the GUI the libraries it loads at runtime.
  # Despite the gtk4 in its buildInputs, snx-rs-gui is a Slint app (winit +
  # glutin/glow); it dlopens everything below rather than linking it, so none of
  # it lands in the RPATH and nothing is pulled into the runtime closure.
  #
  #   wayland + libxkbcommon — winit needs these just to start. Without them
  #   the process dies immediately with "Error initializing winit event loop:
  #   The wayland library could not be loaded" and no tray icon ever appears.
  #
  #   libglvnd — Slint's renderer dlopens libEGL.so.1 / libGL.so.1. Without
  #   them the failure is *silent*: the tray icon appears and its menu works,
  #   but Connect/Settings/Status open no window at all, with nothing on stderr
  #   and nothing in the journal. libglvnd alone is enough — NixOS' EGL vendor
  #   JSON points at mesa by absolute store path — but driverLink is included
  #   so this keeps working under a non-mesa (e.g. NVIDIA) driver.
  #
  # The package is built with wrapGAppsHook4, so this appends to the wrapper it
  # already produces instead of nesting a second one around it.
  snx-rs = pkgs.snx-rs.overrideAttrs (old: {
    preFixup =
      (old.preFixup or "")
      + ''
        gappsWrapperArgs+=(
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [pkgs.wayland pkgs.libxkbcommon pkgs.libglvnd]}:${pkgs.addDriverRunpath.driverLink}/lib"
        )
      '';
  });
in {
  # ── Throne ────────────────────────────────────────────────────────────────
  # GUI proxy manager on top of sing-box. The upstream NixOS module does the
  # privileged parts for us: a security.wrappers entry giving ThroneCore
  # cap_net_admin/net_raw/net_bind_service (instead of upstream's setuid), and a
  # polkit rule so TUN mode can talk to systemd-resolved without prompting for a
  # password three times per connect.
  #
  # Kept while ruh-vpn is being brought up: removing it first left the machine
  # with no working proxy at all, which was a mistake. It goes when the plugin
  # is demonstrably doing its job, not before.
  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

  environment.systemPackages =
    [snx-rs]
    ++ (with pkgs; [
      # Standalone core, for testing a server outside Throne — which is how the
      # REALITY limitation above was found. Not a service: nothing runs it.
      sing-box
      # nft is what the bypass in the routing script is written in, and it was
      # missing entirely, which is why Throne's rules stayed invisible for so
      # long: they live in nftables and iptables-save does not show them.
      nftables
    ]);

  # Reverse-path filtering drops the VPN's keepalive traffic: replies come back
  # on the tunnel rather than the interface the kernel would route to. snx-rs'
  # own NixOS documentation calls for exactly this.
  networking.firewall.checkReversePath = "loose";

  # ── snx-rs ────────────────────────────────────────────────────────────────
  # Open-source Check Point (SNX) client. No NixOS module upstream, so the
  # daemon is wired up by hand, mirroring how it ran on the previous distro.
  #
  # `-m command` means the daemon just sits and waits: it does NOT connect on
  # its own. Connecting is `snxctl connect`, run as the user, and snxctl is what
  # reads the profile — from ~/.config/snx-rs/snx-rs.conf. That file holds the
  # corporate login and password, which is why it is neither in this repo nor
  # in /etc. It comes from sops-nix (modules/nixos/secrets.nix).

  systemd.services.snx-rs = {
    description = "snx-rs Check Point VPN core";
    after = ["network.target" "network-online.target"];
    # nss-lookup.target is passive: After= alone does not pull it in, so it also
    # has to be wanted (systemd.special(7)).
    wants = ["network-online.target" "nss-lookup.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${snx-rs}/bin/snx-rs -m command -l info";
      Restart = "always";
      RestartSec = 10;
      LimitNOFILE = 65536;
    };
  };

  # ── Split routing ─────────────────────────────────────────────────────────
  # Ported from ~/Work/workspace-setup/vpn/snx-happ-routing.sh (happ → sing-box;
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
  #
  # The rules are refreshed on every network event rather than once at boot. DEV
  # and LAN_GW below are read out of the current default route, and that route
  # changes on reconnect, on moving to another network, and on a DHCP renew. A
  # single oneshot does not cover any of that: after the first such change the
  # rules still pointed at an interface that was gone, and corporate traffic went
  # through the TUN — exactly what they exist to prevent.
  #
  # The logic stays here, in one place; the NetworkManager hook further down only
  # restarts this unit. No separate "snx connected" trigger is needed: rule 5100
  # is installed unconditionally, and table 18000 is simply empty until it isn't.
  systemd.services.snx-vpn-routing = {
    description = "snx-rs + sing-box split routing fix";
    # nss-lookup.target: the script resolves the profile's gateway name with
    # getent. Without it a cold boot runs before the resolver is up, getent
    # quietly returns nothing, and only the static subnet list is left.
    after = ["network-online.target" "nss-lookup.target" "snx-rs.service"];
    # nss-lookup.target is passive: After= alone does not pull it in, so it also
    # has to be wanted (systemd.special(7)).
    wants = ["network-online.target" "nss-lookup.target"];
    wantedBy = ["multi-user.target"];
    # getent is its own derivation, not part of glibc.bin — that one ships
    # getconf, not getent. It was missing here, so the lookup below silently
    # produced nothing on every boot and the profile's own gateway never got a
    # rule; only the three static subnets did.
    # iproute2 covers both `ip` and `ss`; systemd is here for resolvectl, which
    # is what knows the nameservers the tunnel handed out.
    path = with pkgs; [iproute2 gawk getent coreutils gnugrep gnused nftables systemd];
    # The hook restarts this on every event, and a reconnect emits a burst of
    # them within seconds. The default limit (5 starts per 10s) would drop the
    # unit into failed precisely when it is needed most.
    unitConfig.StartLimitIntervalSec = 0;
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

      # Not an error but the normal state between down and up: there may be no
      # network at boot, or none for a moment while switching. The hook calls us
      # again once the link is back, so exit cleanly instead of flapping failed.
      [ -z "$DEV" ] && { echo "snx-vpn-routing: no physical default route yet, skipping"; exit 0; }
      [ -z "$LAN_GW" ] && { echo "snx-vpn-routing: no gateway on $DEV yet, skipping"; exit 0; }

      # Plus the gateway the profile currently points at, in case it is one not
      # covered by the static list above.
      SERVER=$(awk -F= '/^server-name=/{print $2; exit}' "$SNX_CONF" 2>/dev/null | tr -d '[:space:]')
      GW_SNX=$(getent hosts "$SERVER" 2>/dev/null | awk '{print $1; exit}')

      # And the address snx actually ended up talking to. Resolving server-name
      # only guesses which gateway got picked; the established socket is the
      # answer. The two differ whenever the name is round-robin or the profile
      # is switched, and a gateway outside the three static /24s would otherwise
      # get no rule at all.
      #
      # The peer column is scanned for from the end of the line rather than by
      # index: `ss` drops the State column when filtering by state, so a fixed
      # $5 would silently read the wrong field. The trailing users:(...) blob
      # does not look like addr:port, so the first match walking backwards is
      # the peer.
      GW_LIVE=$(ss -tnpH 2>/dev/null | awk '/snx-rs/ {
          for (i = NF; i > 0; i--) if ($i ~ /^[0-9.]+:[0-9]+$/) { print $i; exit }
        }' | awk -F: '{print $1}' | head -1)

      TARGETS="$EFKO_GW_NETS"
      [ -n "$GW_SNX" ] && TARGETS="$TARGETS ''${GW_SNX}/32"
      [ -n "$GW_LIVE" ] && TARGETS="$TARGETS ''${GW_LIVE}/32"
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

      # 3a) snx creates the tunnel device first and installs its routes and its
      #     resolver a moment later, so a run triggered by the device appearing
      #     lands in the gap: table 18000 is still empty, nothing gets bypassed,
      #     and the unit reports success. Wait for the table instead of racing
      #     it. 20 s is generous next to the second it actually takes, and the
      #     loop is skipped entirely when there is no tunnel — which is the
      #     normal state at boot.
      if ip link show snx-tun >/dev/null 2>&1; then
          for _ in $(seq 20); do
              [ -n "$(ip route show table 18000 2>/dev/null)" ] && break
              sleep 1
          done
      fi

      # 4) The nameservers the gateway hands out are not necessarily inside the
      #    routes it hands out. 10.1.0.16 was not: queries to it left through the
      #    home router instead of the tunnel and were answered by whatever was
      #    listening out there. Route each of them explicitly.
      SNX_DNS=$(resolvectl dns snx-tun 2>/dev/null \
        | sed 's/^[^:]*://' | tr ' ' '\n' | grep -E '^[0-9.]+$' || true)
      for d in $SNX_DNS; do
          ip route replace "$d" dev snx-tun table 18000 2>/dev/null || true
      done

      # 5) Everything above is routing, and routing is not where sing-box in TUN
      #    mode makes its decisions. It works in nftables, before the routing
      #    rules get a say, and its output chain ends in a catch-all:
      #
      #      chain output { type nat hook output priority mangle + 1
      #        ... th dport 53 dnat ip to <its resolver>          # all DNS
      #        ... meta l4proto tcp redirect to :<its port>       # all TCP
      #
      #    The only exemptions are 127.0.0.0/8 and the machine's own addresses —
      #    nothing for RFC1918. So corporate traffic never reached snx-tun no
      #    matter what table 18000 said: DNS was answered by a public resolver
      #    (snx-tun's tx counter stayed at zero), and TCP was redirected into the
      #    proxy, which then could not reach an internal host and dropped the
      #    connection right after the TLS ClientHello.
      #
      #    A nat chain at a lower priority number runs first, and a DNAT to the
      #    address the packet already carries still counts as a NAT decision: the
      #    conntrack is flagged as translated, so sing-box's chain is skipped for
      #    that flow. Rewriting an address to itself changes nothing else.
      #
      #    The set is built from table 18000 — the corporate routes the gateway
      #    pushed — plus the nameservers, which are not necessarily inside them.
      #    Harmless when sing-box runs as a plain local proxy: it installs no
      #    firewall rules then, and the table is simply never consulted.
      #
      #    That defuses the nat hook and nothing else, which turns out not to
      #    be enough: sing-box hooks output four times over, and only one of
      #    the four is nat.
      #
      #    Its own chains all open with the same two rules — `meta mark 0x2024
      #    return` and `ct mark 0x2024 return`. 0x2024 is the mark sing-box puts
      #    on the sockets it opens itself, so that its own traffic does not fall
      #    back into its own tunnel. Setting that mark on corporate traffic from
      #    a chain that runs before any of its four is therefore one lever that
      #    lifts all of them at once, and it is the only lever that reaches
      #    output_udp_icmp: that chain is `type route`, not nat, so no NAT
      #    decision of ours can preempt it, and UDP to a corporate address was
      #    still being marked 0x2023 and routed into the TUN by rule 9001.
      #
      #    The mark is read back out of Throne's own ruleset rather than
      #    hardcoded, so a change of constant upstream turns into a mismatch we
      #    can see instead of a silent leak. The nat chain below stays as well:
      #    it rests on kernel NAT semantics rather than on a constant, and the
      #    two together cover the hook from both sides.
      BYPASS_MARK=$(nft list chain inet sing-box output 2>/dev/null \
        | awk '$1 == "meta" && $2 == "mark" && $NF == "return" {print $3; exit}')
      [ -n "$BYPASS_MARK" ] || BYPASS_MARK=0x2024

      nft list table inet snx-bypass >/dev/null 2>&1 \
        && nft delete table inet snx-bypass || true
      CORP=$(ip route show table 18000 2>/dev/null | awk '$1 ~ /^[0-9]/ {print $1}')
      ELEMENTS=$(printf '%s\n' $CORP $SNX_DNS | sort -u | paste -sd, -)
      if [ -n "$ELEMENTS" ]; then
          {
            echo "table inet snx-bypass {"
            echo "  set corp {"
            echo "    type ipv4_addr"
            echo "    flags interval"
            # The gateway pushes both aggregates and single hosts inside them
            # (10.2.0.0/18 and 10.2.0.2), which a plain interval set rejects as
            # conflicting. auto-merge folds the overlaps instead.
            echo "    auto-merge"
            echo "    elements = { $ELEMENTS }"
            echo "  }"
            # -200 is ahead of all four of sing-box's chains; the earliest of
            # them, output_prematch, sits at mangle - 1 = -151. `type route` is
            # what makes the kernel redo the route lookup after the mark
            # changes, and ct mark carries the decision to the rest of the flow.
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
    '';
  };

  # The NetworkManager hook below covers everything NetworkManager knows about,
  # and snx-tun is not one of those things: the tunnel is created by snx-rs
  # directly, so connecting emits no dispatcher event and the rules were only
  # refreshed if you remembered to restart this unit by hand. udev does announce
  # the interface, though, and systemd turns that into a device unit — so hang
  # the refresh off the device instead.
  systemd.services.snx-vpn-routing-trigger = {
    description = "Refresh split routing when snx-rs brings its tunnel up";
    # The escape in the unit name is systemd's own encoding of the '-' in
    # snx-tun, not something we get to choose.
    wantedBy = ["sys-subsystem-net-devices-snx\\x2dtun.device"];
    after = ["sys-subsystem-net-devices-snx\\x2dtun.device"];
    serviceConfig = {
      Type = "oneshot";
      # restart, not start: snx-vpn-routing is RemainAfterExit, and starting a
      # unit that is already active does nothing at all — which is precisely the
      # state it is in every time except the first connect after a boot.
      #
      # This unit deliberately does NOT set RemainAfterExit itself: it has to
      # fall back to inactive to be startable again on the next reconnect.
      ExecStart = "${config.systemd.package}/bin/systemctl restart snx-vpn-routing.service";
    };
  };

  # Ask the kernel again on every network event. NetworkManager drops hooks like
  # this into /etc/NetworkManager/dispatcher.d and calls them with the interface
  # in $1 and the action in $2.
  #
  # The restart is --no-block on purpose: the dispatcher runs its hooks serially
  # and waits for each to finish, and systemctl without the flag would in turn
  # wait for the unit — two waits on each other add a visible pause at boot.
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "snx-vpn-routing-hook" ''
        action="$2"

        # Nothing else (pre-up, hostname, dns-change) affects which route wins,
        # and the hook fires often — leave quietly.
        case "$action" in
          up | down | vpn-up | vpn-down | dhcp4-change | dhcp6-change) ;;
          *) exit 0 ;;
        esac

        exec ${config.systemd.package}/bin/systemctl restart --no-block snx-vpn-routing.service
      '';
    }
  ];
}
