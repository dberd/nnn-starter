# Temporary package overlays live here when a channel needs a local fix.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      # opencode 2.2.5 bun dependencies outputHash mismatch in nixpkgs-unstable
      opencode = prev.opencode.overrideAttrs (old: {
        node_modules = old.node_modules.overrideAttrs (_: {
          outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
        });
      });
    })
  ];
}
