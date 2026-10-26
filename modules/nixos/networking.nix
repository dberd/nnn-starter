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

  # Off for Happ's sake. Its TUN has an IPv4 address only, so auto_route
  # captures IPv4 alone. With IPv6 up, browsers prefer AAAA (Happy Eyeballs)
  # and reach dual-stack sites over the native uplink, outside the tunnel.
  # The site then sees this region's address, so geo-blocked pages fail and
  # everything else leaks. Turning IPv6 off makes the tunnel the only route.
  networking.enableIPv6 = false;

  # Keep the clock correct over NTP. A skewed clock is the #1 cause of bogus
  # TLS "certificate not valid yet / expired" errors in the browser, since cert
  # validity is checked against system time.
  services.timesyncd.enable = true;

  # Faster name resolution / mDNS for `.local` hosts.
  services.resolved = {
    enable = true;
    # Cache off, also for Happ. sing-box hijacks DNS on the TUN (hijack-dns)
    # and answers through its own resolver. A resolved cache in front of it
    # keeps answers from when Happ was down or on another node: real local
    # CDN addresses, or addresses that are blocked here. Browsers then connect
    # to the wrong place until the TTL runs out. Without the cache every lookup
    # goes through sing-box. DNSStubListener is the default; it is spelled out
    # only because the two keys are read together.
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
