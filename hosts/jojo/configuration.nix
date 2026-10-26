{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  # Read the LUKS device names from the generated hardware configuration, so
  # the setting below follows the disk after a reinstall (which gives it a
  # new UUID) instead of naming one that no longer exists. (NixOS passes a
  # module only the arguments it names, hence the explicit list above.)
  hardware = import ./hardware-configuration.nix {
    inherit
      config
      lib
      pkgs
      modulesPath
      ;
  };
in
{
  imports = [
    ./hardware-configuration.nix

    ../../modules/base.nix
    ../../modules/hardware.nix
    ../../modules/kernel.nix
    ../../modules/network.nix
    ../../modules/desktop.nix
    ../../modules/gaming.nix
    ../../modules/nvidia.nix
    ../../modules/users.nix
    ../../modules/backup.nix
    ../../modules/homebrew.nix
    ../../modules/notifications.nix
    ../../modules/updates.nix
    ../../modules/smartcard.nix
  ];

  networking.hostName = "jojo";

  # Let TRIM through dm-crypt, for every encrypted device in
  # hardware-configuration.nix, so the weekly fstrim job (on by default)
  # actually reaches the NVMe drive. Trade-off: someone holding the disk can
  # see which blocks are unused, though not their contents.
  boot.initrd.luks.devices = lib.mapAttrs (_: _: {
    allowDiscards = true;
  }) hardware.boot.initrd.luks.devices;

  # NOTE: Do not change this once the system is installed. This must match the
  # NixOS release you FIRST installed with, NOT the release you're currently
  # running: jojo is installed with 26.05, so it stays "26.05" through later
  # upgrades. home.stateVersion in home/austin/home.nix matches it.
  system.stateVersion = "26.05";
}
