# Overlays that exist only to carry a fix nixpkgs already has on master but has
# not yet shipped to the nixos-unstable branch this flake tracks. Everything
# here is meant to be DELETED at the next `nix flake update nixpkgs` — check
# first whether the branch has caught up, rather than keeping the pin alive.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      # typescript-language-server (a dependency of the neovim LSP set, see
      # modules/home/neovim.nix) fails to build on nixos-unstable as of
      # 2026-10-11:
      #
      #   error: hash mismatch in fixed-output derivation
      #     'typescript-language-server-pnpm-deps.drv'
      #     specified: sha256-MUSxDMlbG21KSesGdEvqa2kEpuVfLlXRUX1qV/FGsSo=
      #     got:       sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=
      #
      # A pnpm dependency was re-published, so the recorded hash for the
      # fetchPnpmDeps output no longer describes what pnpm now assembles. It is
      # upstream's own problem and upstream's own answer: nixpkgs master already
      # carries exactly the `got:` hash below for this same version (6.0.2).
      # Overriding only `outputHash` is therefore not a guess — it is the value
      # upstream verified, applied a channel bump early.
      #
      # Only the fixed-output fetch is touched; the package build itself is
      # untouched nixpkgs.
      typescript-language-server = prev.typescript-language-server.overrideAttrs (old: {
        pnpmDeps = old.pnpmDeps.overrideAttrs {
          outputHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
        };
      });
    })
  ];
}
