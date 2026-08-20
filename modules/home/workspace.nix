{lib, ...}: let
  # Empty directories, created but never filled. Two different mechanisms want
  # them to already exist, and neither creates them itself:
  #
  #   1. Sync Settings. profiles/vscodium/data/.sync.yml in dberd/vscode-settings
  #      lists these paths under `additionalFiles` and restores each project's
  #      .vscode into them. If a directory is missing it restores nothing there
  #      and says nothing about it, which is what makes a fresh machine look like
  #      "Download did nothing". Change the list there — change it here.
  #
  #   2. git identity. modules/home/git.nix switches to the work email by
  #      `gitdir:~/Work/Repos/`, so anything cloned under that root is committed
  #      as d.berdnikov@efko.ru without further thought.
  #
  # The repositories themselves are deliberately NOT cloned: this is the shape of
  # the workspace, not its contents.
  workDirs = [
    "Work/Repos/Backend/Calendar/backend"
    "Work/Repos/Backend/Calendar/export-calendar"
    "Work/Repos/Backend/Calendar/sync-external-calendar-job"
    "Work/Repos/Backend/Calendar/sync-users"
    "Work/Repos/Backend/Committees/backend"
    "Work/Repos/Backend/Committees/background-worker"
    "Work/Repos/Backend/Logger"
    "Work/Repos/Backend/notifications"
    "Work/Repos/Backend/PW/authentification"
    "Work/Repos/Backend/PW/auth-library"
    "Work/Repos/Backend/PW/node-manager"
    "Work/Repos/Backend/PW/notifications"
    "Work/Repos/Backend/Skud/backend"
    "Work/Repos/Frontend/Calendar/frontend"
    "Work/Repos/Frontend/Committees/frontend"

    # Database dumps. Contents stay off every sync on purpose — the directory
    # was 3.5 GB on the old machine, and a dump is reproducible from its
    # database in a way a git history is not.
    "Work/Dumps"

    # Work documents, and the notes vaults (github.com/dberd/{EFKO,LongBoiPersonal},
    # cloned by hand — see docs). Same reasoning: the folder is configuration,
    # what goes in it is not.
    "Documents/EFKO_Docs"
    "Notes"
  ];
in {
  # `mkdir -p`, not home.file."…/.keep": a home.file entry would create the
  # directory as a side effect of planting a read-only store symlink inside it,
  # which is exactly what made ~/Pictures/wallpapers un-writable. And not
  # systemd.user.tmpfiles either — that runs at login rather than at switch,
  # and this repo already standardises on home.activation for this kind of work
  # (see seedWallpapers in noctalia.nix, vscodiumSyncBootstrap in vscodium.nix).
  #
  # Idempotent: existing directories and everything in them are left alone.
  home.activation.workspaceTree = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run mkdir -p ${lib.concatMapStringsSep " " (d: "\"$HOME/${d}\"") workDirs}
  '';
}
