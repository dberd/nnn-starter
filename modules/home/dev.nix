{pkgs, ...}: {
  # Development tooling that is genuinely wanted on every host. Language
  # toolchains stay OUT of the global environment on purpose — use direnv +
  # a per-project flake (see ./direnv.nix) so each repo pins its own versions:
  #
  #   echo "use flake" > .envrc && direnv allow
  #
  #   # that project's flake.nix, e.g. for a solution that needs two SDKs:
  #   packages = [(pkgs.dotnetCorePackages.combinePackages [sdk_8_0 sdk_9_0])];
  home.packages = with pkgs; [
    # ── Containers ──────────────────────────────────────────────────────────
    # The daemon itself is modules/nixos/docker.nix; these are the clients.
    docker-compose
    lazydocker

    # ── Databases ───────────────────────────────────────────────────────────
    dbeaver-bin
    postgresql_18 # psql/pg_dump matching the container in ./files/docker-dev.yml

    # ── Runtimes ────────────────────────────────────────────────────────────
    nodejs # includes npm
    # One default .NET SDK; per-project versions (6.0 … 11.0 all exist in
    # nixpkgs) come from that project's devShell instead.
    dotnetCorePackages.sdk_9_0
  ];

  # `dotnet tool install -g dotnet-ef` writes into ~/.dotnet/tools, which is
  # writable — so EF Core tooling installs the normal way, it just needs to be
  # on PATH and to know where the SDK lives.
  home.sessionPath = ["$HOME/.dotnet/tools"];
  home.sessionVariables = {
    DOTNET_ROOT = "${pkgs.dotnetCorePackages.sdk_9_0}";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
  };

  # The local dev stack (postgres 18 + redis 8.4), carried over verbatim from
  # the old ~/docker/docker-dev.yml so `docker compose -f ~/docker/docker-dev.yml
  # up -d` keeps working. Credentials in it are local-only defaults.
  home.file."docker/docker-dev.yml".source = ./files/docker-dev.yml;
}
