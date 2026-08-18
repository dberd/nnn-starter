{pkgs, ...}: {
  # System-level development plumbing. The user-level tooling (docker clients,
  # dbeaver, node, dotnet SDK) lives in modules/home/dev.nix.

  # nix-ld provides an ELF interpreter at the FHS path (/lib64/ld-linux-*.so),
  # so prebuilt binaries that were never linked against the Nix store can run.
  #
  # This is not a nicety here: VSCodium extensions download their own
  # helpers — C#/Roslyn language servers, debuggers, ESLint bundles — and
  # those are ordinary FHS binaries that otherwise fail with a confusing
  # "no such file or directory" (the missing file being the loader, not the
  # binary). Same story for anything `dotnet tool install -g` fetches.
  programs.nix-ld = {
    enable = true;
    # Merged with the module's own defaults (zlib, openssl, curl, systemd, …).
    # These are the extras the .NET runtime and its tooling look for.
    libraries = with pkgs; [
      icu # dotnet globalization — without it DOTNET_SYSTEM_GLOBALIZATION_INVARIANT is required
      krb5 # SQL Server / Kerberos auth in Npgsql & System.Data.SqlClient
      libgdiplus # System.Drawing on older targets
    ];
  };
}
