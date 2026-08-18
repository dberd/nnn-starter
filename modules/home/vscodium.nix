{
  lib,
  pkgs,
  ...
}: {
  # VSCodium itself is installed in ./apps.nix. Its configuration deliberately
  # stays IMPERATIVE, handled by the zokugun.sync-settings extension against a
  # private git repo: that profile already carries settings.json, keybindings,
  # snippets, the extension list, and the .vscode directories of a dozen work
  # repositories. Reproducing that in Nix would be a lot of work for a worse
  # result, and a declarative extensions directory is immutable, which
  # sync-settings cannot work with at all.
  #
  # What is declarative is the bootstrap. Sync Settings can only restore
  # anything once two things already exist, and neither of them lives inside the
  # synced repo:
  #
  #   1. the extension itself;
  #   2. its settings.yml, which is what points at the profile repo.
  #
  # On a fresh machine neither is present, so "Sync Settings: Download" appears
  # to do nothing. This closes that gap; afterwards one Download is enough.
  home.activation.vscodiumSyncBootstrap = lib.hm.dag.entryAfter ["writeBoundary"] ''
    cfg="$HOME/.config/VSCodium/User/globalStorage/zokugun.sync-settings/settings.yml"

    # Written only when absent — deliberately not home.file, which would make it
    # a read-only store symlink the extension could not update from its UI.
    if [ ! -e "$cfg" ]; then
      run mkdir -p "$(dirname "$cfg")"
      run tee "$cfg" > /dev/null <<'EOF'
    profile: vscodium
    repository:
      type: git
      url: git@github.com:dberd/vscode-settings.git
      branch: main
    EOF
    fi

    if ! ${pkgs.vscodium}/bin/codium --list-extensions 2>/dev/null | grep -qix 'zokugun.sync-settings'; then
      run ${pkgs.vscodium}/bin/codium --install-extension zokugun.sync-settings || true
    fi
  '';
}
