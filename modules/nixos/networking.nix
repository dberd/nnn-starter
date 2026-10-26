{...}: {
  networking.networkmanager.enable = true;

  # NixOS's own stateful firewall stays the single firewall on this system
  # (ufw is not packaged in nixpkgs at all). The upside of staying on it: the
  # `openFirewall` options other modules expose just work — see
  # programs.steam.remotePlay.openFirewall in ./gaming.nix.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [53317]; # LocalSend
    allowedUDPPorts = [53317]; # LocalSend discovery
  };

  networking.enableIPv6 = false;



  # Keep the clock correct over NTP. A skewed clock is the #1 cause of bogus
  # TLS "certificate not valid yet / expired" errors in the browser, since cert
  # validity is checked against system time.
  services.timesyncd.enable = true;

  # Faster name resolution / mDNS for `.local` hosts.
  services.resolved = {
  enable = true;
  # Новый формат: настройки передаются через settings.Resolve.
  # Значения опций — строки, как в оригинальном resolved.conf.
  settings.Resolve = {
    DNSStubListener = "yes";
    Cache = "no";
  };
};

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
