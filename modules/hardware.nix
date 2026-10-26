{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.boot.kernelPackages) kernel;

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

  # Battery charge limit: charging stops at 80%, as Acer Care Center's
  # setting does on Windows (a battery kept full on the charger, as a gaming
  # laptop often is, loses capacity years sooner). It's Acer's own "battery
  # health mode", reached through the acer-wmi-battery driver (compiled for
  # the kernel, modules/kernel.nix; the Nitro V 15 ANV15-51 is on its list
  # of laptops it works on), which turns it on when it loads, at every boot.
  # To charge to 100% once, until the next boot:
  #   echo 0 | sudo tee /sys/bus/wmi/drivers/acer-wmi-battery/health_mode
  # For good: change enable_health_mode=1 to 0 below.
  #
  # Installed with the kernel's own `modules_install` rather than copied by
  # hand as nixpkgs' package does, so that NixOS's module signing (kmodigest,
  # in nixos-unstable since October 2026, headed for 26.11) signs it and writes
  # the certificate (.ko.cer) unstable then requires of every add-on module;
  # without it, building the system's module tree fails there. On 26.05 it
  # installs the same file. Drop the override once nixpkgs' package does it.
  boot.extraModulePackages = [
    (config.boot.kernelPackages.acer-wmi-battery.overrideAttrs {
      installPhase = ''
        runHook preInstall
        make $makeFlags -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
          M="$PWD" INSTALL_MOD_PATH="$out" INSTALL_MOD_DIR=kernel/drivers/platform/x86 modules_install
        runHook postInstall
      '';
    })
  ];
  boot.kernelModules = [ "acer-wmi-battery" ];

  # The battery limit's setting (the line without a `#`), then driver
  # options to try on this laptop, one per problem: remove the `#` in front
  # of an `options` line, then rebuild and reboot. (Comments inside this
  # text are modprobe's own, so editing it can't break the build. The file
  # also reaches the initrd, where i915 loads.) If one makes things worse,
  # put the `#` back or boot the previous version.
  boot.extraModprobeConfig = ''
    options acer-wmi-battery enable_health_mode=1

    # Acer's performance modes and fan readings (what NitroSense does on
    # Windows). acer-wmi has them but turns them on only for the models it
    # lists (some Predators and the Nitro AN515-58), not this one; forcing
    # them often works, since Nitro and Predator laptops share Acer's
    # interface. Then `cat /sys/firmware/acpi/platform_profile_choices`
    # lists Acer's modes, the battery icon's power profiles switch between
    # them (Performance raises the power limits for games), and `sensors`
    # shows the fans.
    #options acer_wmi predator_v4=1

    # Realtek Wi-Fi (rtw89, e.g. RTL8852BE) that drops or is slow: turn off
    # its power saving. (`lspci -k | grep -iA3 network` names the card.)
    #options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y
    #options rtw89_core disable_ps_mode=y

    # Screen flicker (some panels with Intel graphics): turn off Panel Self
    # Refresh, at a small cost in battery life.
    #options i915 enable_psr=0
  '';

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
    # -n standby: don't spin up a sleeping hard drive just to check it
    # (the WD My Passport and Toshiba USB drives), except after 24 skipped
    # checks (12 hours), so one that's always asleep still gets checked.
    defaults.monitored = "-a -n standby,24,q -m <nomailer> -M daily -M exec ${smartdNotify}";
  };
  environment.systemPackages = [
    # `sensors`: CPU core and NVMe temperatures (and fan speeds, where the
    # driver reports them).
    pkgs.lm_sensors
    # `lspci`: the PCI devices and their drivers (which GPU is where, which
    # Wi-Fi card); NixOS doesn't install it by default.
    pkgs.pciutils
    # `hardware-check`: the hardware checklist's checks that a script can do
    # (README.md), with a report to share when asking for help.
    (pkgs.writeShellApplication {
      name = "hardware-check";
      runtimeInputs = with pkgs; [
        coreutils
        gawk
        gnugrep
        gnused
        kdePackages.libkscreen # kscreen-doctor
        lm_sensors
        networkmanager # nmcli
        pciutils
        power-profiles-daemon # powerprofilesctl
        systemd
        wireplumber # wpctl
      ];
      runtimeEnv = {
        HOST = config.networking.hostName;
        # The GPU addresses the config gives the NVIDIA driver
        # (modules/nvidia.nix), to compare with the real ones.
        NVIDIA_BUS_IDS = "${config.hardware.nvidia.prime.intelBusId} ${config.hardware.nvidia.prime.nvidiaBusId}";
      };
      text = builtins.readFile ../scripts/hardware-check.sh;
    })
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
