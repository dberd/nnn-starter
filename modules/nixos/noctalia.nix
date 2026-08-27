{
  config,
  pkgs,
  inputs,
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
  # Two ids are covered because pkexec compares its exec.path annotation against
  # the literal argv path: the policy file names the /nix/store path, while the
  # shell finds the helper on PATH as /run/current-system/sw/bin/…, so the match
  # fails and pkexec falls back to the generic org.freedesktop.policykit.exec.
  # Both paths are spelled out in full rather than matched by suffix, so nothing
  # that merely shares the basename can slip through.
  #
  # Same argument as the udisks rule in ./desktop.nix: wheelNeedsPassword is
  # already false (./users.nix), so this grants nothing the user cannot already
  # get from a bare `sudo`.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (!subject.isInGroup("wheel")) {
        return;
      }
      if (action.id === "org.noctalia.greeter.apply-appearance") {
        return polkit.Result.YES;
      }
      if (action.id === "org.freedesktop.policykit.exec") {
        var program = action.lookup("program");
        if (program === "${config.programs.noctalia-greeter.package}/bin/noctalia-greeter-apply-appearance"
            || program === "/run/current-system/sw/bin/noctalia-greeter-apply-appearance") {
          return polkit.Result.YES;
        }
      }
    });
  '';
}
