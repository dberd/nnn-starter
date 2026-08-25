# Claude Code's upstream download bucket went private, so nixpkgs cannot fetch
# the binary any more. This overlay re-points the package at npm, which still
# serves the very same executable.
#
# Symptom without this (any nixpkgs from ~23.08.2026 on):
#
#   curl: (22) The requested URL returned error: 403
#   error: cannot download claude from any mirror
#
# nixpkgs fetches `downloads.claude.ai/claude-code-releases/<ver>/linux-x64/claude`,
# a plain anonymous GET against a Google Cloud Storage bucket, and that bucket now
# answers `<Code>AccessDenied</Code>`. Every version 403s, old ones included, with
# and without a User-Agent, so it is not a pulled release.
#
# Not a network problem on our side either, which is worth recording because it
# looks like one: other GCS-backed objects (proxy.golang.org serves Go modules by
# redirecting to signed GCS URLs) fetch fine from this same machine and IP at the
# same moment. Only this bucket refuses, so nothing about routing, geography or a
# request header changes the outcome.
#
# The npm route is the same build by another road. `@anthropic-ai/claude-code` is
# only a stub whose postinstall pulls a platform-specific optional dependency —
# that dependency, `@anthropic-ai/claude-code-linux-x64`, carries the real ~390 MB
# executable and npm serves it anonymously. Verified before wiring it up here:
# extracted and run, `claude --version` → `2.1.245 (Claude Code)`.
#
# Worth keeping even after the uplink can reach GCS again: npm is the more
# durable of the two sources, and the pin here is an ordinary version + hash.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.overrideAttrs (_old: rec {
        version = "2.1.245";

        # The unpatched derivation does `installBin $src` on a bare binary, so
        # $src has to stay a single file rather than become a directory — hence
        # unpacking here instead of handing it a tarball. Naming the derivation
        # `claude` is load-bearing: installBin runs the store path through
        # stripHash, so the basename becomes the installed command's name.
        src = final.runCommandLocal "claude" {} ''
          tar xzf ${final.fetchurl {
            url = "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-${version}.tgz";
            hash = "sha256-MQyLt2nGaZRYgH0lw4nddLsQwzXxeuH7fO1z1B+iaKc=";
          }} --strip-components=1 package/claude
          install -Dm755 claude $out
        '';
      });
    })
  ];
}
