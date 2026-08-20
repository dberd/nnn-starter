# VPN stack: Throne (general-purpose TUN proxy, replaces happ) + snx-rs
# (Check Point corporate VPN), plus the split-routing fix that makes the two
# coexist.
{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  # nixpkgs' snx-rs does not give the GUI the libraries winit loads at runtime.
  # winit dlopens libwayland-client rather than linking it, so nothing lands in
  # the RPATH and `snx-rs-gui` dies immediately with
  #   Error initializing winit event loop: The wayland library could not be loaded
  # which is why no tray icon ever appeared — the process never got that far.
  #
  # The package is built with wrapGAppsHook4, so this appends to the wrapper it
  # already produces instead of nesting a second one around it.
  snx-rs = pkgs.snx-rs.overrideAttrs (old: {
    preFixup =
      (old.preFixup or "")
      + ''
        gappsWrapperArgs+=(
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [pkgs.wayland pkgs.libxkbcommon]}"
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
  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

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
  # in /etc. (Migration target: sops-nix.)
  environment.systemPackages = [snx-rs];

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
    description = "snx-rs + Throne split routing fix";
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
    path = with pkgs; [iproute2 gawk getent coreutils];
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
