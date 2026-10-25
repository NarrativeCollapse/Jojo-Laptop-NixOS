{ options, pkgs, ... }:

{
  ################################
  # NetworkManager + DNS
  ################################

  networking.networkmanager = {
    enable = true;
    dns = "systemd-resolved";
  };

  # Mullvad & modern DNS setups work best with systemd-resolved.
  services.resolved.enable = true;

  ################################
  # Mullvad VPN (official module)
  ################################

  # The module runs the daemon and installs the app itself, so don't also
  # list mullvad-vpn in environment.systemPackages.
  #
  # How to ask for the app changed between releases: NixOS 26.05 has one
  # package with the daemon and the app (pkgs.mullvad-vpn), while 26.11
  # splits them and adds gui.enable. This picks whichever the running
  # release has; once on 26.11, keep just `gui.enable = true;` (see
  # "Release upgrade" in README.md).
  services.mullvad-vpn = {
    enable = true;
  }
  // (
    if options.services.mullvad-vpn ? gui then
      { gui.enable = true; }
    else
      { package = pkgs.mullvad-vpn; }
  );

  ################################
  # Local discovery: mDNS
  ################################

  # mDNS/DNS-SD so network printers (printing is in desktop.nix) and other
  # .local devices are found automatically. openFirewall allows mDNS (UDP
  # 5353) in, which discovery needs.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  ################################
  # Firewall + hardening
  ################################

  # The NixOS firewall is on by default with nothing open; the only port
  # opened is mDNS for Avahi (above). Steam Remote Play's ports stay closed
  # (gaming.nix). Mullvad manages its own killswitch and routing, so don't
  # add VPN rules here that would fight the daemon.

  # Network hardening for untrusted Wi-Fi. rp_filter is deliberately not
  # set: the NixOS firewall handles reverse-path checking, and strict values
  # can interfere with Mullvad/WireGuard routing.
  boot.kernel.sysctl = {
    # Ignore ICMP redirects (MITM vector on hostile networks).
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    # This machine is not a router; don't emit redirects either.
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    # Drop source-routed packets.
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    # SYN-flood protection (kernel default, made explicit).
    "net.ipv4.tcp_syncookies" = 1;
  };

  # If you want SSH later (openFirewall opens port 22):
  #
  # services.openssh = {
  #   enable = true;
  #   openFirewall = true;
  #   settings.PasswordAuthentication = false;
  # };
  # services.fail2ban.enable = true;  # only worth it once SSH is exposed
}
