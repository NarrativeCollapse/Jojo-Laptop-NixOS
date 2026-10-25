# The installer ISO: a live Plasma desktop that can install jojo.
#
# Build it on any machine with Nix (the laptop itself works):
#   nix build ~/nixos-config#installer-iso
# The ISO lands in ./result/iso/. Write it to a USB stick with ISO Image
# Writer (installed on jojo) or any "DD mode" USB writer.
#
# Booting it gives a live Plasma session (no password). Connect to Wi-Fi
# from the panel, then double-click "Install jojo" on the desktop, or run
# `sudo install-jojo` in Konsole.
{
  lib,
  pkgs,
  modulesPath,
  self,
  version,
  ...
}:

let
  repoUrl = "https://github.com/NarrativeCollapse/Jojo-Laptop-NixOS.git";

  # The config this ISO was built from, copied into the ISO: the fallback
  # when GitHub can't be reached (the installer normally clones the latest).
  snapshot = "/etc/jojo-config";
  snapshotRev = self.shortRev or self.dirtyShortRev or "unknown";

  installJojo = pkgs.writeShellApplication {
    name = "install-jojo";
    runtimeInputs = with pkgs; [
      coreutils
      cryptsetup
      curl
      dosfstools
      e2fsprogs
      gawk
      git
      gptfdisk
      networkmanager
      parted
      util-linux
    ];
    runtimeEnv = {
      REPO_URL = repoUrl;
      SNAPSHOT = snapshot;
      SNAPSHOT_REV = snapshotRev;
      CONFIG_VERSION = version;
    };
    text =
      builtins.readFile ../../scripts/lib/confirm.sh + builtins.readFile ../../scripts/install-jojo.sh;
  };
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-graphical-base.nix" ];

  image.baseName = lib.mkForce "jojo-installer-${version}";
  networking.hostName = "jojo-installer";

  # The ISO's own Nix needs flakes for `nixos-install --flake`.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Live Plasma session, logged in automatically as "nixos" (as on the
  # official Plasma ISO, minus the Calamares installer, which installs a
  # generic NixOS rather than this config).
  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = false;
  };
  services.displayManager = {
    plasma-login-manager.enable = true;
    autoLogin = {
      enable = true;
      user = "nixos";
    };
  };
  environment.plasma6.excludePackages = [ pkgs.kdePackages.plasma-workspace-wallpapers ];
  programs.kde-pim.enable = false;

  ################################
  # Wi-Fi that works out of the box
  ################################

  # All firmware, so Wi-Fi works on other laptops too (some of it is unfree).
  hardware.enableAllFirmware = true;
  nixpkgs.config.allowUnfree = true;

  # The panel's network applet stores Wi-Fi passwords in KWallet, which
  # can't unlock in a password-less live session, so connecting there
  # failed and only nmtui worked. With KWallet off, the password goes
  # straight to NetworkManager. (Admin prompts are already skipped: the
  # installer lets the wheel group do anything.)
  environment.etc."xdg/kwalletrc".text = ''
    [Wallet]
    Enabled=false
    First Use=false
  '';

  # Some laptops (HP among them) start with Wi-Fi soft-blocked.
  systemd.services.rfkill-unblock-wifi = {
    description = "Unblock Wi-Fi";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.util-linux}/bin/rfkill unblock wifi";
  };

  ################################
  # The installer
  ################################

  environment.etc."jojo-config".source = "${self}";
  environment.systemPackages = [ installJojo ];

  # "Install jojo" on the live desktop, opening Konsole.
  system.activationScripts.installJojoDesktop = ''
    mkdir -p /home/nixos/Desktop
    cat > /home/nixos/Desktop/install-jojo.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Install jojo
    Comment=Erase a disk and install this NixOS config
    Icon=nix-snowflake
    Exec=konsole --hold -e sudo install-jojo
    Terminal=false
    EOF
    chmod +x /home/nixos/Desktop/install-jojo.desktop
    chown -R nixos /home/nixos/Desktop
  '';
}
