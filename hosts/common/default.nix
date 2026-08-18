# Settings shared by every host. Anything that differs per machine (hostname,
# timezone, hardware) lives in hosts/<name>/default.nix instead.
{...}: {
  i18n.defaultLocale = "en_US.UTF-8";

  # English interface, but European conventions for everything measurable —
  # notably dd/mm/yyyy dates and 24h time instead of the US defaults.
  # i18n.supportedLocales is derived from these automatically, so en_IE gets
  # generated without listing it separately.
  i18n.extraLocaleSettings = {
    LC_TIME = "en_IE.UTF-8";
    LC_NUMERIC = "en_IE.UTF-8";
    LC_MONETARY = "en_IE.UTF-8";
    LC_PAPER = "en_IE.UTF-8";
    LC_MEASUREMENT = "en_IE.UTF-8";
    LC_ADDRESS = "en_IE.UTF-8";
    LC_TELEPHONE = "en_IE.UTF-8";
    LC_NAME = "en_IE.UTF-8";
    LC_IDENTIFICATION = "en_IE.UTF-8";
  };

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
