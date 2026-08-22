# sing-box as an ordinary local proxy, running *alongside* Throne rather than in
# place of it.
#
# The destination is that this replaces Throne outright — the same engine
# underneath, but with the server list and the switch in a bar widget instead of
# a Qt application carrying its own SQLite database. That swap cannot be done in
# one step, for two reasons worth writing down:
#
#   1. Throne's inbound is what this machine's Claude Code talks through
#      (modules/home/claude-code.nix pins HTTPS_PROXY to 127.0.0.1:2080). Turn
#      Throne off in the same rebuild that turns this on and the session doing
#      the work loses its network mid-flight.
#   2. Throne *is* sing-box. Its core installs its rules in a table named
#      `inet sing-box`, and a second sing-box in TUN mode would create a table
#      by that same name — not a conflict the kernel arbitrates, just a name
#      collision where the later writer flushes the earlier one's rules.
#
# Hence: no `tun` inbound and no `auto_route` here. In this shape sing-box does
# not touch nftables at all — it is a listener on 127.0.0.1 and nothing more,
# which is precisely what lets it share a machine with Throne. TUN, if it turns
# out to be wanted at all, comes after Throne is gone.
{config, ...}: let
  # Throne holds 2080 (mixed inbound) and would hold 9090 (its Clash API, off
  # today: `core_box_clash_api` is stored as -9090, the minus meaning disabled).
  # Both are stepped over rather than shared, so that enabling Throne's own
  # dashboard during the overlap cannot collide with ours.
  inboundPort = 2081;
  clashPort = 9091;

  # sing-box's own bypass mark. Throne's chains all open with
  # `meta mark 0x2024 return`, so wearing it keeps our outbound connections out
  # of Throne's transparent proxy — without it every connection this makes would
  # be redirected into Throne and proxied twice. See modules/nixos/vpn.nix, which
  # puts the same mark on corporate traffic for the same reason.
  bypassMark = 8228; # 0x2024
in {
  # Node credentials are the only part of a profile that is actually secret —
  # the server names, ports and transports are not — so those three strings come
  # from sops and the rest stays legible here. The `_secret` indirection is the
  # sing-box module's own: it holds a *path* in the store-resident settings and
  # substitutes the file's contents into /run/sing-box/config.json at start,
  # as root, before dropping to the sing-box user.
  sops.secrets = {
    singbox-vavn-uuid = {};
    singbox-hy2-password = {};
    singbox-hy2-obfs = {};
  };

  services.sing-box = {
    enable = true;

    settings = {
      log = {
        level = "warn";
        # journald already stamps every line with a timestamp of its own.
        timestamp = false;
      };

      # ── DNS ───────────────────────────────────────────────────────────────
      # `local` is the system resolver, which on this machine is systemd-resolved
      # with the corporate servers attached to snx-tun. Routing corporate names
      # there rather than to a public resolver is the whole reason the previous
      # proxy broke the VPN: its "direct" was a hardcoded public address, so
      # internal names came back NXDOMAIN from a server that has never heard of
      # them.
      #
      # Everything else is resolved at 1.1.1.1 over DoH *through the proxy*, so
      # the queries do not describe our browsing to the local network. The server
      # is written as an address, not a name, so resolving it needs no resolver.
      dns = {
        servers = [
          {
            tag = "system";
            # systemd-resolved's stub, named by address rather than by
            # `type = "local"`. The local transport reads
            # /run/systemd/resolve/stub-resolv.conf and then times out on every
            # query here — measured, both A and AAAA, with nothing else in the
            # config to blame. Naming the stub directly works, and it is the
            # same resolver either way: resolved is what holds snx-tun's
            # corporate servers and the split-DNS domain routing.
            type = "udp";
            server = "127.0.0.53";
          }
          {
            tag = "remote";
            type = "https";
            server = "1.1.1.1";
            detour = "proxy";
          }
        ];
        rules = [
          {
            domain_suffix = ["efko.ru"];
            server = "system";
          }
        ];
        final = "remote";
        strategy = "prefer_ipv4";
      };

      # ── Inbound ───────────────────────────────────────────────────────────
      # "mixed" speaks SOCKS and HTTP on one port, which is what lets a single
      # HTTPS_PROXY/ALL_PROXY pair point at it. Bound to loopback only: this is
      # a proxy for this machine, and nothing on the LAN has any business
      # reaching it.
      inbounds = [
        {
          type = "mixed";
          tag = "mixed-in";
          listen = "127.0.0.1";
          listen_port = inboundPort;
        }
      ];

      # ── Outbounds ─────────────────────────────────────────────────────────
      # The selector is what the widget drives: the Clash API exposes it as a
      # group, `PUT /proxies/proxy` switches the member, and that is the entire
      # mechanism behind "pick a server" — no config rewrite, no restart.
      #
      # The REALITY profile from the same subscription is deliberately absent.
      # It does not complete a handshake under sing-box *or* under Xray-core
      # 26.3.27, which is the core Throne bundles: the server does not accept its
      # keys and hands back the real site's certificate. Its location is the same
      # host as the Hysteria2 node, so nothing is lost by leaving it out until
      # the subscription is refreshed and the profile can be re-tested.
      outbounds = [
        {
          type = "selector";
          tag = "proxy";
          outbounds = ["vavn-lv" "vavn-fr-hy2" "direct"];
          default = "vavn-fr-hy2";
          # Without this, switching servers leaves established connections on
          # the old one, and the switch appears not to have worked.
          interrupt_exist_connections = true;
        }

        {
          type = "vless";
          tag = "vavn-lv";
          server = "vavn.pro";
          server_port = 443;
          uuid = {_secret = config.sops.secrets.singbox-vavn-uuid.path;};
          flow = "xtls-rprx-vision";
          packet_encoding = "xudp";
          tls = {
            enabled = true;
            server_name = "vavn.pro";
            alpn = ["http/1.1" "h2"];
            utls = {
              enabled = true;
              fingerprint = "firefox";
            };
          };
          routing_mark = bypassMark;
        }

        {
          type = "hysteria2";
          tag = "vavn-fr-hy2";
          server = "fr.vavn.pro";
          server_port = 443;
          password = {_secret = config.sops.secrets.singbox-hy2-password.path;};
          obfs = {
            type = "salamander";
            password = {_secret = config.sops.secrets.singbox-hy2-obfs.path;};
          };
          tls = {
            enabled = true;
            server_name = "fr.vavn.pro";
            alpn = ["h3"];
          };
          routing_mark = bypassMark;
        }

        {
          type = "direct";
          tag = "direct";
          routing_mark = bypassMark;
        }
      ];

      # ── Routing ───────────────────────────────────────────────────────────
      # Private space and corporate names never enter the proxy. This is the
      # part that keeps the corporate VPN working, and it is a great deal
      # simpler than the nftables bypass in vpn.nix that Throne requires: a
      # local proxy decides where a connection goes by rule, so there is nothing
      # to intercept and nothing to undo.
      route = {
        rules = [
          {action = "sniff";}
          {
            ip_is_private = true;
            outbound = "direct";
          }
          {
            domain_suffix = ["efko.ru"];
            outbound = "direct";
          }
          # The two mode switches the control-centre tile flips. Without a rule
          # naming a mode, the Clash API accepts the mode change and nothing
          # observable happens.
          {
            clash_mode = "Direct";
            outbound = "direct";
          }
          {
            clash_mode = "Global";
            outbound = "proxy";
          }
        ];
        final = "proxy";
        # Which resolver turns an outbound's own server name into an address —
        # vavn.pro here. It has to be the system one: "remote" is DoH *through*
        # the proxy, and the proxy cannot be dialled before its address is
        # known. sing-box 1.12 made this explicit and 1.14 drops the implicit
        # fallback, so leaving it out is a deprecation error, not a default.
        default_domain_resolver.server = "system";
        # Off, and it matters. Turned on, sing-box binds every outbound socket
        # to the interface it decides is "the default one", which overrides the
        # routing table — corporate addresses then leave through the physical
        # uplink instead of snx-tun and time out, resolved correctly and dialled
        # into a black hole. The option exists to stop a TUN inbound from
        # swallowing its own outbound traffic; with no TUN here there is nothing
        # to protect against, and the kernel's own routing is what we want.
        auto_detect_interface = false;
      };

      # ── Control surface ───────────────────────────────────────────────────
      # The Clash external controller: the same HTTP API mihomo and Clash speak,
      # which is what makes a widget possible without inventing a protocol.
      # Verified against this exact build (1.13.14): GET /proxies lists the
      # selector with `now` and `all`, PUT /proxies/proxy switches it and the
      # exit address really does change, GET /connections carries the running
      # totals, and GET /group/proxy/delay measures every member at once.
      #
      # Loopback and no secret: anything that can reach 127.0.0.1 on this
      # machine can already reach the proxy itself on 2081.
      experimental.clash_api = {
        external_controller = "127.0.0.1:${toString clashPort}";
        default_mode = "Rule";
      };
    };
  };
}
