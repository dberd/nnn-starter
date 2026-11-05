# Module arguments:
{lib, pkgs, ...}:

# No programs.claude-code.enable line.

# Wrapper name:
pkgs.writeShellScriptBin "codex" ''

# Keep the Happ port detection, connection check and proxy exports.

# Final command:
exec ${pkgs.codex}/bin/codex "$@"
''