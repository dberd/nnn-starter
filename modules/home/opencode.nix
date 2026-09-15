{
  config,
  lib,
  pkgs,
  ...
}: let
  # Same local inbound as ./claude-code.nix — Throne's mixed listener, which
  # speaks both SOCKS and HTTP on one port. Kept as its own binding here rather
  # than shared, so that neither file has to be read to understand the other.
  proxyPort = 2080;
in {
  # opencode — a second agentic CLI next to Claude Code, from a different
  # vendor. Unlike `claude` it is not unfree, so it needs nothing from the
  # allowUnfree set in flake.nix.
  #
  # ~/.local/share/opencode (auth, sessions) stays runtime-managed. The
  # declarative half is `settings` (opencode.json) and `tui` (tui.json); only
  # the latter is used here, and only to name a theme.
  #
  # Colour comes from Noctalia's community template, which renders
  # ~/.config/opencode/themes/matugen.json on every palette change and has no
  # hook at all — nothing to arrange beyond naming the theme. Note the key is
  # `tui.theme` (tui.json), NOT `settings.theme`: opencode moved theme selection
  # out of opencode.json, and Stylix's own target sets tui.theme too, which is
  # what the disable below is resolving. `programs.opencode.themes` stays unused
  # on purpose — it would write store symlinks into the directory the template
  # owns.
  stylix.targets.opencode.enable = false;

  programs.opencode = {
    enable = true;
    tui.theme = "matugen";
  };

  # Route it through the tunnel, for the same reason and by the same mechanism
  # as `claude`: when the proxy has no connection up nothing is listening on the
  # port, so requests are refused rather than quietly falling back to the plain
  # uplink. Shadowing the command rather than adding a second one means anything
  # that spawns `opencode` as a child inherits it too.
  #
  # Application-level, not packet-level — it relies on opencode honouring the
  # proxy variables, which it does: it is a Bun/node program and undici reads
  # HTTPS_PROXY. The kernel-level alternative would need a stable selector, and
  # nftables resolves cgroup paths at rule-load time, so a transient systemd
  # scope cannot be matched.
  #
  # The module exposes no `finalPackage` (unlike programs.claude-code), so the
  # wrapper execs cfg.package directly. That is exact as long as extraPackages
  # stays empty — set it and the module wraps the package itself, and this would
  # jump over the wrapper.
  home.packages = [
    (lib.hiPrio (pkgs.writeShellScriptBin "opencode" ''
      export HTTPS_PROXY="http://127.0.0.1:${toString proxyPort}"
      export HTTP_PROXY="$HTTPS_PROXY"
      # Inherited by everything opencode spawns — git, npm, MCP servers.
      # Corporate hosts must stay out of the proxy: they are reached through the
      # snx tunnel (modules/nixos/vpn.nix), and loopback obviously shouldn't
      # round-trip either.
      export NO_PROXY="localhost,127.0.0.1,::1,.efko.ru,.local"
      export no_proxy="$NO_PROXY"

      exec ${config.programs.opencode.package}/bin/opencode "$@"
    ''))
  ];
}
