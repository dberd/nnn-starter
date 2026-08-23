{
  config,
  lib,
  pkgs,
  ...
}: let
  # Throne's local inbound. It is a "mixed" listener, so the same port speaks
  # both SOCKS and HTTP — confirmed from Throne's own log:
  #   inbound/mixed[mixed-in]: tcp server started at 127.0.0.1:2080
  #
  # This used to point at a standalone sing-box instead, kept alive solely so
  # Claude Code's route wouldn't depend on whatever node Throne was switched
  # to. Retired 23.08 (docs/proxy.md §9): Throne is the one thing covering the
  # rest of the system anyway, so decoupling Claude Code from it bought
  # nothing but a second engine to run.
  proxyPort = 2080;
in {
  # Claude Code — Anthropic's official CLI (binary: `claude`). Marked unfree, so
  # it relies on the allowUnfree set in flake.nix.
  #
  # We only install the package; ~/.claude (auth, settings, projects) stays
  # runtime-managed, so nothing here fights what `claude` writes at runtime.
  # To manage it declaratively instead, set programs.claude-code.settings,
  # .agents, .commands, .mcpServers, … (see the home-manager module docs) — the
  # settings.json file is only written once you provide some.
  programs.claude-code.enable = true;

  # Confine Claude Code's traffic to the proxy tunnel: when the plugin has no
  # connection up, nothing is listening on the port and connections are refused
  # rather than falling back to the plain uplink. Shadowing the command (rather
  # than adding a second one) means this also covers the VSCodium extension,
  # which spawns the CLI as a child process and inherits the environment.
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
      export HTTPS_PROXY="http://127.0.0.1:${toString proxyPort}"
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
