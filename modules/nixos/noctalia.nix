{
  config,
  pkgs,
  inputs,
  username,
  ...
}: {
  # Noctalia's NixOS module enables the system-level support it needs. The shell
  # itself is launched per-user from home (see modules/home/noctalia.nix), so we
  # only opt into the recommended companion services here.
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
    # Use upstream's prebuilt package straight from noctalia.cachix.org instead
    # of rebuilding the (large, ~hour) C++ tree against our nixpkgs.
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  # Greeter Auto-Sync (see shell.greeter_sync in modules/home/noctalia.nix) runs
  # the greeter's apply helper as root through pkexec on every wallpaper or
  # palette change. That helper's polkit action defaults to auth_admin, which
  # would mean a password dialog every time the theme moves.
  #
  # greeter 1.6.0 ships the first half of the answer itself: this option writes
  # a rule for its own action id, which is the one pkexec picks when the helper
  # is invoked by its /nix/store path (the path its .policy file annotates).
  # The rule is narrower than the hand-written one it replaces — it also
  # requires subject.local, subject.active and the helper's exact store path —
  # and it moves with the package, which is the real gain: the action was
  # RENAMED in 1.6.0 (org.noctalia.greeter.apply-appearance →
  # ….sync-appearance, with an `argv1 --sync` annotation added), and a rule
  # naming the old id by hand would have gone quietly dead.
  services.displayManager.noctalia-greeter.passwordless-sync-users = [username];

  # The other half, which upstream's option does NOT cover. pkexec matches its
  # argv path against the policy's exec.path annotation as a literal string and
  # resolves no symlinks, so when the shell finds the helper on PATH — as
  # /run/current-system/sw/bin/noctalia-greeter-apply-appearance — no action
  # matches, pkexec falls back to the generic org.freedesktop.policykit.exec,
  # and the rule above never sees it. Both paths are spelled out in full rather
  # than matched by suffix, so nothing that merely shares the basename can slip
  # through.
  #
  # Same argument as the udisks rule in ./desktop.nix: wheelNeedsPassword is
  # already false (./users.nix), so this grants nothing the user cannot already
  # get from a bare `sudo`.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (!subject.isInGroup("wheel")) {
        return;
      }
      if (action.id === "org.freedesktop.policykit.exec") {
        var program = action.lookup("program");
        if (program === "${config.services.displayManager.noctalia-greeter.package}/bin/noctalia-greeter-apply-appearance"
            || program === "/run/current-system/sw/bin/noctalia-greeter-apply-appearance") {
          return polkit.Result.YES;
        }
      }
    });
  '';
}
