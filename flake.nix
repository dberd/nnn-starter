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

    # Zen browser (not in nixpkgs). It's a repackaged binary (fixed-output
    # download + wrapFirefox), so following our nixpkgs is cheap and avoids a
    # duplicate nixpkgs in the closure.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      # Its home-manager module reuses HM's firefox module, so share ours.
      inputs.home-manager.follows = "home-manager";
    };

    # rycee's Firefox-addons package set, for declaring Zen extensions instead
    # of leaving them as profile state. Not a flake — a NUR subtree.
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Helium (Blink-based) isn't in nixpkgs — upstream only publishes a .deb —
    # so it comes from a community flake, same category of trust as
    # zen-browser above. Chosen over the half-dozen equivalents for shipping
    # its own home-manager module (programs.helium) rather than just a bare
    # package.
    helium-browser = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
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
            # Packages nixpkgs marks insecure that this configuration needs anyway.
            # Matching by name rather than by full version keeps the rule alive
            # across version bumps:
            #
            #   pnpm               build-time tool for vesktop's Vencord, never run
            #   dotnet-sdk         .NET 6 is EOL; still the SDK for the net6.0 class
            #                      libraries in Committees and Calendar
            #   aspnetcore-runtime .NET 7 is EOL; net7.0 WebApi hosts will not start
            #                      without it (modules/home/dev.nix)
            #
            # Note: defining this predicate replaces permittedInsecurePackages
            # entirely — any future exception has to be added here.
            nixpkgs.config.allowInsecurePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "pnpm"
                "dotnet-sdk"
                "dotnet-runtime"
                "aspnetcore-runtime"
              ];
            nixpkgs.overlays = [
              niri.overlays.niri
              noctalia.overlays.default
            ];

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = {inherit inputs username local;};
            # No sharedModules here on purpose. niri-flake auto-imports its home
            # modules (config + stylix) when home-manager runs as a NixOS module,
            # and home-manager itself has shipped `programs.noctalia` since
            # 25.08.2026 — it is the upstreamed copy of the flake's own module,
            # same options and same build-time `noctalia config validate`.
            # Importing either one again only double-declares its options.
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
