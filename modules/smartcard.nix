{ pkgs, ... }:

let
  # OpenSC's PKCS#11 module: how apps reach the certificates on a CAC (or a
  # PIV card) through the reader.
  openscModule = "${pkgs.opensc}/lib/opensc-pkcs11.so";

  # `cac-setup [bundle.zip]`: imports the DoD's CA certificates into
  # LibreWolf, so DoD sites are trusted. They come from DISA as a zip that
  # changes name with every new version, so it's fetched on the laptop when
  # you run this (or you pass the zip you downloaded) rather than pinned
  # here, where a new version would break the build.
  cacSetup = pkgs.writeShellApplication {
    name = "cac-setup";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      gawk
      gnugrep
      gnused
      nss.tools # certutil
      openssl
      unzip
    ];
    text = builtins.readFile ../scripts/cac-setup.sh;
  };
in
{
  ################################
  # Smart cards: CAC readers
  ################################

  # pcscd talks to USB smart-card readers (any CCID-compliant one; the ccid
  # driver is its default plugin). It starts when an app asks for a reader.
  services.pcscd.enable = true;

  environment.systemPackages = [
    pkgs.opensc # pkcs11-tool, opensc-tool: read the card's certificates
    pkgs.pcsc-tools # pcsc_scan: shows readers and reacts to a card
    cacSetup
  ];

  # LibreWolf loads OpenSC at start (a browser policy), so a site asking
  # for a certificate offers the card's and asks for its PIN. Chrome is a
  # Flatpak, whose sandbox can't reach the reader without extra plumbing;
  # use LibreWolf for CAC sites. (An overlay, so the LibreWolf installed in
  # desktop.nix is this one.)
  nixpkgs.overlays = [
    (_final: prev: {
      librewolf = prev.librewolf.override {
        extraPolicies.SecurityDevices.Add."CAC (OpenSC)" = openscModule;
      };
    })
  ];
}
