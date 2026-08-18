# Settings shared by every host. Anything that differs per machine (hostname,
# timezone, hardware) lives in hosts/<name>/default.nix instead.
{...}: {
  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.xkb = {
    layout = "us,ru";
    variant = "";
    options = "grp:alt_shift_toggle"; # Alt+Shift switches US <-> Russian
  };
  console.keyMap = "us";

  # The release this config was written against. Do NOT bump casually after
  # first install — read the NixOS release notes first.
  system.stateVersion = "25.05";
}
