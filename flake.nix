{
  description = "nnn-starter — an opinionated NixOS starter for the NNN stack (NixOS + Niri + Noctalia)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Scrollable-tiling Wayland compositor + NixOS/home-manager modules.
    # Deliberately does NOT follow our nixpkgs, so niri-flake's prebuilt
    # packages stay byte-identical to what niri.cachix.org has cached.
    niri.url = "github:sodiboo/niri-flake";

    # Noctalia desktop shell (v5 line). Pinned to the `cachix` branch: upstream
    # force-pushes there only after a commit's package is built and pushed to
    # noctalia.cachix.org, so `packages.default` is guaranteed to be a cache hit
    # (no ~hour-long C++ source build). It tracks `main` (v5), just slightly
    # behind. Crucially we do NOT make it follow our nixpkgs — that would
    # rebuild it against a different nixpkgs and miss the cache.
    noctalia.url = "github:noctalia-dev/noctalia-shell/cachix";

    # greetd greeter matching Noctalia. It IS in nixpkgs, but not yet in the
    # revision our lock pins, and bumping nixpkgs wholesale for one package
    # would rebuild half the world — so it comes from its own flake instead.
    # Left to bring its own nixpkgs, for the same cache reason as niri/noctalia.
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";

    # Secrets: encrypted in-repo, decrypted at activation (secrets/, .sops.yaml).
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning (hosts/*/disko.nix).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # System-wide base16 theming.
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Community plugins for Noctalia, pinned rather than fetched at runtime.
    # Noctalia's own plugin source kind `path` is documented as "an immutable
    # local directory (e.g. a Nix store path) the host treats read-only", which
    # is exactly what an input gives us: the plugin version is in flake.lock
    # instead of being whatever git happened to hand the shell that morning.
    # Not a flake — it is a plain repository of plugin directories.
    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins";
      flake = false;
    };

    # Zen browser (not in nixpkgs). It's a repackaged binary (fixed-output
    # download + wrapFirefox), so following our nixpkgs is cheap and avoids a
    # duplicate nixpkgs in the closure.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      # Its home-manager module reuses HM's firefox module, so share ours.
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    niri,
    noctalia,
    noctalia-greeter,
    disko,
    sops-nix,
    stylix,
    ...
  } @ inputs: let
    # Build one nixosConfiguration from hosts/<name>/. Everything machine-local
    # (username, hostname, timezone, monitors) comes from that host's local.nix,
    # so adding a machine is: create hosts/<name>/{default,local}.nix +
    # hardware-configuration.nix, then one line in nixosConfigurations below.
    mkHost = hostName: let
      local = import ./hosts/${hostName}/local.nix;
      inherit (local) username;
    in
      nixpkgs.lib.nixosSystem {
        system = local.system or "x86_64-linux";
        specialArgs = {inherit inputs username local;};
        modules = [
          niri.nixosModules.niri
          noctalia.nixosModules.default
          noctalia-greeter.nixosModules.default
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          stylix.nixosModules.stylix
          home-manager.nixosModules.home-manager

          ./hosts/common
          ./hosts/${hostName}
          ./modules/nixos

          {
            nixpkgs.config.allowUnfree = true;
            # Vesktop builds Vencord with pnpm, which nixpkgs currently marks
            # insecure. It's a build-time tool only; allow it by name so the rule
            # survives pnpm version bumps.
            #
            # Note: defining this predicate replaces permittedInsecurePackages
            # entirely — any future exception has to be added here.
            nixpkgs.config.allowInsecurePredicate = pkg: nixpkgs.lib.getName pkg == "pnpm";
            nixpkgs.overlays = [
              niri.overlays.niri
              noctalia.overlays.default
            ];

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = {inherit inputs username local;};
            # niri-flake auto-imports its home modules (config + stylix) into
            # every user when home-manager runs as a NixOS module, so we only
            # add noctalia's here. Importing the niri ones again double-declares
            # `programs.niri.finalConfig`.
            home-manager.sharedModules = [
              noctalia.homeModules.default
            ];
            home-manager.users.${username} = import ./modules/home;
          }
        ];
      };

    # Helper so `nix fmt` / `nix develop` work from macOS or Linux.
    devSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs devSystems;
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      nnn-desktop = mkHost "nnn-desktop";
      # nnn-t480s = mkHost "nnn-t480s";   # ThinkPad T480s — see hosts/README
    };

    # `nix fmt`
    formatter = forAllSystems (system: (pkgsFor system).alejandra);

    # `nix develop` — tooling for hacking on this repo.
    devShells = forAllSystems (system: {
      default = (pkgsFor system).mkShell {
        packages = with pkgsFor system; [
          alejandra
          statix
          deadnix
          nh
          nix-output-monitor
          sops
          age
        ];
      };
    });
  };
}
