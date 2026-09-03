{pkgs, ...}: let
  # One .NET installation carrying every band the work repositories target.
  # `combinePackages` merges the sdk/ and shared/ trees, so a single DOTNET_ROOT
  # can build net6.0 … net10.0 and run all of them.
  #
  # SDK 7 is deliberately absent: net7.0 projects (Calendar, Committees.WebApi)
  # build fine with the newest SDK — the reference packs come from NuGet — but
  # they will not RUN without the 7.0 runtime, which is why aspnetcore_7_0 is
  # in the list. Same trade-off the Arch install made (see
  # ~/Work/workspace-setup/SETUP.md §02), just spelled out declaratively.
  dotnet = pkgs.dotnetCorePackages.combinePackages (with pkgs.dotnetCorePackages; [
    sdk_10_0
    sdk_9_0
    sdk_8_0
    sdk_6_0
    aspnetcore_7_0
  ]);
in {
  # Development tooling that is genuinely wanted on every host. Language
  # toolchains that a single project pins stay OUT of the global environment —
  # use direnv + a per-project flake (see ./direnv.nix):
  #
  #   echo "use flake" > .envrc && direnv allow
  home.packages = with pkgs; [
    # ── Containers ──────────────────────────────────────────────────────────
    # The daemon itself is modules/nixos/docker.nix; these are the clients.
    docker-compose
    lazydocker

    # ── Databases ───────────────────────────────────────────────────────────
    dbeaver-bin
    postgresql_18 # psql/pg_dump matching the container in ./files/docker-dev.yml

    # ── Runtimes ────────────────────────────────────────────────────────────
    nodejs # current LTS: the default for anything without an .nvmrc

    # Angular 14 (Committees) and 16 (Calendar) refuse to run on it, and
    # nixpkgs no longer carries a nodejs_16 to pin — the oldest left is 20.
    # fnm downloads the official build instead; it runs here because nix-ld
    # (modules/nixos/dev.nix) provides the FHS loader it was linked against.
    # Both frontends already carry an .nvmrc, so `--use-on-cd` in ../home/fish.nix
    # switches versions on `cd` with nothing to remember.
    fnm

    dotnet

    # Golang tools
    go
    gopls
    delve
    gotools
    
    # Postman alternative
    hoppscotch
  ];

  # `dotnet tool install -g dotnet-ef` writes into ~/.dotnet/tools, which is
  # writable — so EF Core tooling installs the normal way, it just needs to be
  # on PATH and to know where the SDK lives.
  home.sessionPath = ["$HOME/.dotnet/tools"];
  home.sessionVariables = {
    DOTNET_ROOT = "${dotnet}";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
  };

  # The local dev stack (postgres 18, redis 8.4, memgraph 3.11 + its lab UI),
  # carried over verbatim from the old ~/docker/docker-dev.yml so
  # `docker compose -f ~/docker/docker-dev.yml up -d` keeps working.
  # Credentials in it are local-only defaults.
  home.file."docker/docker-dev.yml".source = ./files/docker-dev.yml;
}
