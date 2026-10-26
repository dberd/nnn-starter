{
  config,
  lib,
  pkgs,
  ...
}: let
  # Happ's local HTTP inbound — the fallback used only when Happ.conf cannot be
  # read at runtime; the wrapper below prefers the live value.
  #
  # 10809 is Happ's own default. It lives in ~/.config/Happ.conf as
  #   [Preferences]
  #   allowConnectionFromLAN\HTTPPort=10809
  #   allowConnectionFromLAN\Socks5Port=10808
  # and its SOCKS twin on 10808 is what Happ's bundled sing-box dials as the
  # outbound of its TUN inbound (~/.config/Happ/config.json, "tag": "proxy").
  # So the whole machine's traffic already funnels through that pair of ports —
  # this wrapper just addresses them directly instead of going via the TUN.
  #
  # HTTP (10809) rather than SOCKS (10808): these variables are consumed by
  # Node, and undici's ProxyAgent speaks HTTP CONNECT with no socks5 scheme at
  # all. Pointing HTTPS_PROXY at 10808 fails in a much more confusing way than
  # it looks like it should.
  #
  # Why this is read at runtime instead of just being stated here: it was
  # stated here, as 2080 — Throne's mixed inbound, from when Throne was the one
  # engine on this box (docs/proxy.md §1). modules/nixos/happ.nix replaced
  # Throne and nothing imports a throne module any more, so nothing had been
  # listening on 2080 since that migration. Combined with the fail-closed
  # design below, claude died on a bare ECONNREFUSED while every other
  # application kept working through Happ's TUN — a stale constant presenting
  # itself as an outage. Reading Happ's own setting means changing the port in
  # Happ's UI is enough, and the preflight makes the remaining failure modes
  # name themselves.
  fallbackPort = 10809;
in {
  # Claude Code — Anthropic's official CLI (binary: claude). Marked unfree, so
  # it relies on the allowUnfree set in flake.nix.
  #
  # We only install the package; ~/.claude (auth, settings, projects) stays
  # runtime-managed, so nothing here fights what claude writes at runtime.
  # To manage it declaratively instead, set programs.claude-code.settings,
  # .agents, .commands, .mcpServers, … (see the home-manager module docs) — the
  # settings.json file is only written once you provide some.
  #
  # Straight from nixpkgs again. From ~23.08.2026 it could not be: Anthropic's
  # download bucket answered AccessDenied to every anonymous GET, so
  # modules/nixos/claude-code.nix carried an overlay re-pointing the package at
  # the npm tarball (@anthropic-ai/claude-code-linux-x64) instead. Both halves
  # of that are gone now: the bucket serves again, and nixpkgs fetches a
  # zstd-compressed binary through a manifest.zst.json, which the overlay's
  # plain-ELF src could not satisfy anyway ("zstd: … unsupported format"). If
  # the 403s ever return, git log -- modules/nixos/claude-code.nix has the
  # whole story and the npm URL.
  programs.claude-code.enable = true;

  # Confine Claude Code's traffic to the proxy tunnel: when Happ has no
  # connection up, nothing is listening on the port and the run is refused
  # rather than falling back to the plain uplink. Shadowing the command (rather
  # than adding a second one) means this also covers the VSCodium extension,
  # which spawns the CLI as a child process and inherits the environment.
  #
  # Why bother, when Happ's TUN already covers everything: Anthropic geo-blocks
  # this region. Without the guard, a run with Happ down does not merely fail —
  # it authenticates this account from an IP it must never be seen from, and
  # does so silently. Refusing on loopback is the correct outcome.
  #
  # This is application-level, not packet-level: it relies on Claude Code
  # honouring the proxy variables. The kernel-level alternative would need a
  # stable selector — nftables resolves cgroup paths when the rule is loaded, so
  # a transient systemd scope cannot be matched, and uid/gid selectors would
  # mean either a separate account or a setuid sg wrapper.
  #
  # hiPrio resolves the profile collision with the package the module above
  # installs; finalPackage is that same module's wrapped build, so settings and
  # plugins are preserved.
  home.packages = [
    (lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      # Prefer the port Happ itself is configured with, so this does not go
      # stale again. Pure bash on purpose: a wrapper that runs before anything
      # else should not depend on what happens to be on PATH.
      conf="$HOME/.config/Happ.conf"
      port=""
      if [ -r "$conf" ]; then
        while IFS= read -r line; do
          case $line in
          *HTTPPort=*) port=''${line##*=} ;;
          esac
        done <"$conf"
        port=''${port//[!0-9]/} # the file is CRLF-clean, but do not bet on it
      fi
      [ -n "$port" ] || port=${toString fallbackPort}

      # Preflight: actually connect, rather than trusting that a listener
      # implies a reachable one. A refused loopback connect returns at once, so
      # this costs nothing in the normal case.
      if ! (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
        echo "claude: nothing accepting connections on 127.0.0.1:$port." >&2
        echo "claude: start Happ and make sure its HTTP inbound is enabled." >&2
        echo "claude: refusing to run outside the tunnel — this region is geo-blocked." >&2
        exit 69 # EX_UNAVAILABLE
      fi

      export HTTPS_PROXY="http://127.0.0.1:$port"
      export HTTP_PROXY="$HTTPS_PROXY"
      # These variables are inherited by everything claude spawns — git, npm,
      # MCP servers. Corporate hosts must stay out of the proxy: they are
      # reached through the snx tunnel (see modules/nixos/vpn.nix), and loopback
      # obviously shouldn't round-trip either.
      export NO_PROXY="localhost,127.0.0.1,::1,.efko.ru,.local"
      export no_proxy="$NO_PROXY"

      exec ${config.programs.claude-code.finalPackage}/bin/claude "$@"
    ''))
  ];
}
