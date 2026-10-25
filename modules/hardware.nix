{
  config,
  lib,
  pkgs,
  ...
}:

let
  # smartd's alert, through notify-desktop (notifications.nix). If austin
  # isn't logged in it's skipped, but the warning repeats daily and is in
  # `journalctl -u smartd`.
  smartdNotify = pkgs.writeShellScript "smartd-notify" ''
    exec ${lib.getExe config.my.notifyDesktop} smartd drive-harddisk \
      "Disk problem: $SMARTD_DEVICESTRING" \
      "$SMARTD_MESSAGE. Check your backups; details: disk-health"
  '';
in
{
  ################################
  # Boot loader
  ################################

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
      # Without this, anyone at the boot menu can press `e` and edit the
      # kernel command line (e.g. add init=/bin/sh). The disk is still LUKS-
      # encrypted either way, but locking the editor closes an easy local
      # tampering vector on a laptop that leaves the house.
      editor = false;
      # A Memtest86+ entry at the bottom of the boot menu. Faulty RAM causes
      # random crashes that look like software bugs; a pass or two (leave it
      # running for an hour or more) rules it out. Esc leaves it.
      memtest86.enable = true;
    };
    efi.canTouchEfiVariables = true;
    grub.enable = false;
    # Shorter menu wait on a laptop you boot often.
    timeout = 3;
  };

  # The initrd (early boot, including the disk-password prompt) runs systemd:
  # NixOS's default since 26.05 and the only option from 26.11, so it isn't
  # set here (26.11 rejects setting it).

  # TRIM through dm-crypt (allowDiscards) is set per host, next to the
  # encrypted disk it applies to: see hosts/jojo/configuration.nix.

  ################################
  # Graphical boot: Plymouth
  ################################

  # A Breeze-themed splash that also draws the disk-unlock password prompt,
  # instead of scrolling kernel text. Press Esc during boot to see the
  # messages behind it.
  boot.plymouth = {
    enable = true;
    theme = "breeze";
    themePackages = [ pkgs.kdePackages.breeze-plymouth ];
  };
  # Load the Intel GPU driver in the initrd so the splash and password prompt
  # appear at native resolution from the start (early KMS).
  boot.initrd.kernelModules = [ "i915" ];
  # Keep kernel and systemd status text off the screen on a normal boot
  # (the Plymouth module adds "splash" itself).
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];

  ################################
  # Memory: zram swap + oomd
  ################################

  # No disk swap is configured (see hosts/jojo/hardware-configuration.nix).
  # zram gives us compressed in-RAM swap so large builds / games don't hit the
  # OOM killer, without writing anything to the encrypted disk.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  # Kernel memory tuning for zram (the values Fedora and Pop!_OS use):
  # swapping to RAM is cheap, so prefer it over dropping file cache
  # (swappiness above 100); skip swap read-ahead, which only helps real disks
  # (page-cluster 0); and keep kswapd from reclaiming in bursts.
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;

    # Kernel-info hardening — enable if you're security-motivated; can
    # inconvenience debugging/profiling tools. (Network hardening is in
    # network.nix.)
    # "kernel.dmesg_restrict" = 1;
    # "kernel.kptr_restrict" = 2;
  };

  # When memory really runs out, systemd-oomd closes the app using the most
  # (its whole process group) after sustained memory pressure, instead of
  # the desktop freezing until the kernel's last-resort OOM killer acts.
  # Fedora does the same. `journalctl -u systemd-oomd` shows what it closed.
  systemd.oomd.enableUserSlices = true;

  ################################
  # Power / thermal / firmware
  ################################

  services.power-profiles-daemon.enable = true;

  # Closing the lid suspends on battery (the default), but not on AC (e.g.
  # docked or downloading). Remove this to always suspend.
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";

  # Intel thermal management. Separate concern from power-profiles-daemon
  # (which handles the CPU governor/EPP, not thermal trip points). It runs
  # in adaptive mode, following the thermal tables in the laptop's firmware,
  # the ones Windows uses.
  services.thermald.enable = true;

  # Acer's own performance modes and fan readings (what NitroSense does on
  # Windows). Linux's acer-wmi driver has them, but switches them on only
  # for the models it lists (some Predators and the Nitro AN515-58), and
  # this laptop isn't one. Acer's Nitro and Predator laptops share the
  # interface, so forcing it on often works, but it's untested here. To
  # try: uncomment, rebuild, reboot. Then
  # `cat /sys/firmware/acpi/platform_profile_choices` lists Acer's modes,
  # the battery icon's power profiles switch between them (Performance
  # raises the power limits for games), and `sensors` shows the fans. If
  # anything misbehaves, comment it out again or boot the previous version.
  # boot.kernelParams = [ "acer_wmi.predator_v4=1" ];

  # Thunderbolt: boltd lets a Thunderbolt dock or drive connect (System
  # Settings → Thunderbolt asks to authorize it). Does nothing if the USB-C
  # port isn't Thunderbolt.
  services.hardware.bolt.enable = true;

  services.fwupd.enable = true;
  hardware.enableRedistributableFirmware = true;

  # Disk health: smartd reads the SSD's own health counters (spare blocks,
  # wear, media errors, temperature) every 30 minutes and warns on the
  # desktop when one crosses its limit, again each day until it's fixed.
  # A drive usually reports trouble like this weeks before it fails.
  # `disk-health` shows the full report.
  services.smartd = {
    enable = true;
    # The module's own alerts are terminal `wall` messages and X11 pop-ups;
    # smartdNotify (top of this file) sends a desktop notification instead.
    notifications.wall.enable = false;
    defaults.monitored = "-a -m <nomailer> -M daily -M exec ${smartdNotify}";
  };
  environment.systemPackages = [
    # `sensors`: CPU core and NVMe temperatures (and fan speeds, where the
    # driver reports them).
    pkgs.lm_sensors
    (pkgs.writeShellApplication {
      name = "disk-health";
      text = ''
        # Every disk smartctl finds: overall verdict plus the health counters.
        # (smartctl's exit code flags even minor log entries; keep going.)
        sudo ${pkgs.smartmontools}/sbin/smartctl --scan | while read -r dev _ type _; do
          sudo ${pkgs.smartmontools}/sbin/smartctl -H -A -d "$type" "$dev" || true
        done
      '';
    })
  ];

  ################################
  # External drives: NTFS and exFAT
  ################################

  # USB drives and SD cards formatted on Windows (NTFS) or for cameras and
  # phones (exFAT) already mount read-write: the kernel has both drivers,
  # and Plasma's mounting service uses the kernel's ntfs3. This adds their
  # tools, so Partition Manager can format drives as NTFS or exFAT, and
  # there are repair tools: `sudo ntfsfix -d /dev/sdX1` clears the "dirty"
  # mark Windows leaves on a drive it didn't shut down cleanly (Fast
  # Startup), which can stop it mounting; `sudo fsck.exfat /dev/sdX1`
  # checks an exFAT one.
  boot.supportedFilesystems = [
    "ntfs"
    "exfat"
  ];

  ################################
  # Graphics
  ################################

  hardware.graphics = {
    enable = true;
    # 32-bit drivers, needed by 32-bit Steam/Proton titles.
    enable32Bit = true;
    # VA-API (iHD) and oneVPL drivers for Gen12+ Intel graphics, so browsers
    # and video players decode video on the GPU instead of the CPU.
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  ################################
  # Bluetooth
  ################################

  # Powered on at boot by default, so the Xbox controller connects at login.
  # No blueman: Plasma already ships BlueDevil when Bluetooth is enabled, and
  # blueman would add a second tray applet.
  hardware.bluetooth.enable = true;

  ################################
  # Optional: TPM-backed LUKS unlock
  ################################

  # This machine already uses systemd in initrd, so you *can* enroll the LUKS
  # key into the TPM for passwordless (but still encrypted) boot:
  #
  #   1. Add tpm2 tooling:
  #        environment.systemPackages = [ pkgs.tpm2-tools ];
  #   2. Enroll once, imperatively:
  #        sudo systemd-cryptenroll --tpm2-device=auto /dev/<luks-partition>
  #   3. Tell initrd to try the TPM:
  #        boot.initrd.luks.devices."luks-...".crypttabExtraOpts =
  #          [ "tpm2-device=auto" ];
  #
  # Left commented because it requires the one-time enroll step and a decision
  # about your threat model (TPM unlock trades a passphrase for physical-theft
  # resistance only).
}
