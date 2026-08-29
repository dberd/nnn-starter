{
  lib,
  pkgs,
  ...
}: {
  # Sensible hardware defaults for a modern Intel laptop (tested on a ThinkPad
  # X1 Carbon Gen 13 / Lunar Lake, in use on a T480s). All generic enough to keep
  # in the starter — nothing here names a specific model.

  # GPU video acceleration. hardware.graphics is enabled in desktop.nix; this
  # adds the VA-API / QSV runtimes so browsers and players decode/encode video
  # on the iGPU instead of the CPU (the single biggest battery win on Intel).
  #   intel-media-driver → the modern `iHD` VA-API driver (Gen8+ / Xe / Arc)
  #   vpl-gpu-rt         → oneVPL runtime for QuickSync (QSV) decode/encode
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  # Pin the VA-API driver so libva doesn't probe/guess.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  # `vainfo` for inspecting the available decode/encode profiles.
  environment.systemPackages = [pkgs.libva-utils];

  # Intel thermal management daemon — keeps temps/throttling sane under load.
  # Standard on Intel laptops; complements (does not conflict with) the
  # power-profiles-daemon used by the desktop.
  #   ignoreCpuidCheck: newer Intel CPUs (e.g. Lunar Lake, family 6 model 0xbd)
  #   aren't in thermald's built-in model table yet, so it would otherwise exit
  #   with "Unsupported cpu model" at boot. Forces it to run with generic config.
  # mkDefault: a host whose model ships its own MSR-writing daemon (nnn-t480s
  # runs services.throttled) turns this off rather than having the two fight.
  services.thermald.enable = lib.mkDefault true;
  services.thermald.ignoreCpuidCheck = true;

  # Firmware updates via LVFS: `fwupdmgr refresh && fwupdmgr update` pulls
  # BIOS/EC/Thunderbolt updates. ThinkPads are well supported upstream.
  services.fwupd.enable = true;

  # Thunderbolt / USB4 device authorization (docks, eGPUs, TB SSDs).
  # `boltctl` lists and authorizes devices.
  services.hardware.bolt.enable = true;

  # Compressed RAM swap. Faster than the disk swap partition and saves NVMe
  # wear; the default (50% of RAM) is plenty of headroom.
  # It does NOT replace the disk swap: zram takes the higher priority and absorbs
  # the ordinary paging, while hibernation needs a real block device and uses the
  # one disko lays down (see hosts/<name>/disko.nix).
  zramSwap.enable = true;

  # Intel microcode. nixos-hardware's common/cpu/intel sets this too, but only
  # as an mkDefault keyed on enableRedistributableFirmware — stated here so the
  # module stands on its own for a host that does not import nixos-hardware.
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  # Closing the lid suspends, and if it stays closed long enough the machine
  # writes RAM to disk and powers off properly instead of draining the battery
  # in S3 for two days. This needs a swap device at least as large as RAM
  # (hosts/<name>/disko.nix) — with only zram below, hibernation silently fails
  # and the lid switch degrades to a plain suspend.
  services.logind.lidSwitch = "suspend-then-hibernate";
  services.logind.lidSwitchExternalPower = "suspend";
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  # Out of battery should also mean hibernate, not a hard cut. upower is enabled
  # in ../desktop.nix; this is only about what it does at the bottom.
  services.upower = {
    criticalPowerAction = "Hibernate";
    percentageAction = 3;
    percentageCritical = 5;
    percentageLow = 15;
  };

  # Fingerprint reader (enroll with `fprintd-enroll`). Wires fingerprint auth
  # into PAM for login/sudo via the libfprint stack.
  services.fprintd.enable = true;
}
