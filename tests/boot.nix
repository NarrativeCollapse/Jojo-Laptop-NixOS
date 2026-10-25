# Boot test: starts jojo's configuration in a QEMU VM and checks that it
# boots, its services start, Plasma logs in and the config's own commands
# run. Catches changes that build but don't work. Runs as the `boot` check
# (`nix flake check`, and CI on every push); on its own:
#   nix build .#checks.x86_64-linux.boot -L
# Interactively, with a window onto the VM:
#   nix run .#checks.x86_64-linux.boot.driverInteractive
{
  modules,
  version,
  versionSuffix,
}:

{
  name = "jojo-boot";

  nodes.machine =
    { lib, ... }:
    {
      imports = modules;

      # Only what the VM can't do like the laptop:
      # - No encrypted disk: the test supplies its own virtual disks (the
      #   VM also ignores the laptop's file systems and boot loader).
      boot.initrd.luks.devices = lib.mkForce { };
      # - Log straight into Plasma instead of waiting at the login screen.
      #   (The real config leaves the session to SDDM's memory; see
      #   desktop.nix. Here it has to be named.)
      services.displayManager = {
        autoLogin = {
          enable = true;
          user = "austin";
        };
        defaultSession = "plasma";
      };
      # - The test framework reads the kernel's console messages, so it
      #   needs the full log level instead of the quiet boot (hardware.nix).
      boot.consoleLogLevel = lib.mkForce 7;
      # - The test framework names the system "test" instead of the usual
      #   label ("${version}-26.05..."); keep the version in it so the check
      #   of the banner's version line below still means something. (The
      #   framework sets "test" with mkForce, so this needs a stronger
      #   priority: lower numbers win, mkForce is 50.)
      system.nixos.label = lib.mkOverride 40 "${version}-test";
      # - Likewise the framework's version ("26.05test") has no date; give
      #   it the real one ("26.05.20260926.5e2305d"), which update-reminder
      #   reads the packages' age from (through `nixos-version`).
      system.nixos.versionSuffix = lib.mkOverride 40 versionSuffix;
      # - The VM framework swaps the video drivers for its own
      #   ("modesetting", at priority 10), which would leave the NVIDIA
      #   driver out of the VM altogether. Keep the laptop's, so the VM
      #   boots the same driver setup. (With no NVIDIA GPU in the VM, the
      #   driver's modules and nvidia-powerd fail to start; expected.)
      services.xserver.videoDrivers = lib.mkOverride 5 [ "nvidia" ];
      # - Enough memory and CPU for Plasma.
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        # - Two blank disks standing in for USB drives: /dev/vdb for the
        #   backup drive, /dev/vdc for NTFS and exFAT.
        emptyDiskImages = [
          64
          64
        ];
        # - The VM replaces the config's file systems with its own, so the
        #   backup drive's mount is repeated here, as in backup.nix.
        fileSystems."/mnt/backup" = {
          device = "/dev/disk/by-label/BACKUP";
          fsType = "ext4";
          options = [ "nofail" ];
        };
      };
    };

  # Not checked, because a VM can't have them: smartd (virtual disks report
  # no SMART data), Bluetooth, Wi-Fi, thermald, firmware updates, the NVIDIA
  # GPU itself (its services fail in the VM: nothing to drive), Flatpak
  # downloads and anything else that needs the internet.
  testScript = ''
    start_all()

    with subtest("Boots to the graphical target"):
        machine.wait_for_unit("graphical.target")

    with subtest("Core services are running"):
        for unit in [
            "display-manager.service",
            "NetworkManager.service",
            "systemd-resolved.service",
            "mullvad-daemon.service",
            "avahi-daemon.service",
            "systemd-oomd.service",
            "restic-backups-home.timer",
            "home-manager-austin.service",
        ]:
            machine.wait_for_unit(unit)

    with subtest("Plasma starts for austin"):
        machine.wait_until_succeeds("pgrep -u austin plasmashell", timeout=300)

    with subtest("The taskbar script ran (plasma-manager)"):
        machine.wait_until_succeeds(
            "grep -q nix-snowflake-white /home/austin/.config/plasma-org.kde.plasma.desktop-appletsrc",
            timeout=300,
        )
        # The panel is docked, not floating (saved in plasmashellrc).
        machine.wait_until_succeeds(
            "grep -Eq '^floating=(0|false)$' /home/austin/.config/plasmashellrc",
            timeout=120,
        )

    with subtest("Minimize uses Magic Lamp (plasma-manager)"):
        machine.succeed("grep -qx 'magiclampEnabled=true' /home/austin/.config/kwinrc")
        machine.succeed("grep -qx 'squashEnabled=false' /home/austin/.config/kwinrc")

    with subtest("The power profile follows the charger (plasma-manager)"):
        machine.wait_until_succeeds(
            "grep -qx 'PowerProfile=power-saver' /home/austin/.config/powerdevilrc",
            timeout=120,
        )

    with subtest("The config's commands are installed and run"):
        machine.succeed(
            "su - austin -c 'command -v update update-system update-flatpak"
            " update-firmware update-rollback update-neovim backup-setup"
            " backup-test brew-update disk-health nixos-motd toggle-motd"
            " boxbuddy-rs'"
        )
        # The standalone CLI tools come from Nix (bling.nix; sensors and
        # lspci from hardware.nix), not Homebrew.
        machine.succeed(
            "su - austin -c 'command -v rg fd bat tv jq yq gh glab dysk"
            " trash-put tldr shellcheck stress-ng sensors lspci'"
        )
        # yq is the Go one (mikefarah/yq), as Homebrew's was.
        yq = machine.succeed("su - austin -c 'yq --version'")
        assert "mikefarah" in yq, yq
        # An unknown option prints the usage and exits 1 (the test shell uses
        # pipefail, so check the output rather than piping it to grep).
        usage = machine.fail("su - austin -c 'update bogus' 2>&1")
        assert "Usage: update" in usage, usage
        motd = machine.succeed("su - austin -c nixos-motd")
        assert "Welcome to NixOS" in motd, motd
        # The config version (${version}) is in the running system's name, which
        # the MOTD and fastfetch show through nixos-system-info.
        info = machine.succeed("su - austin -c nixos-system-info")
        system = machine.succeed("readlink /run/current-system")
        assert "${version}" in info, f"nixos-system-info: {info!r}, system: {system!r}"

    with subtest("Firewall: only mDNS is open"):
        # Read the live rules (the NixOS firewall uses iptables here): mDNS
        # (5353) must be there, Steam Remote Play's ports must not.
        rules = machine.succeed("iptables-save; ip6tables-save")
        assert "5353" in rules, rules
        for port in ["27036", "10400"]:
            assert port not in rules, rules

    with subtest("Stability settings are in effect"):
        # Disk-full protection (nix.conf), and the 45-second stop timeout
        # for system services and austin's session.
        machine.succeed("grep -qx 'min-free = 5368709120' /etc/nix/nix.conf")
        stop = machine.succeed("systemctl show -p DefaultTimeoutStopUSec")
        assert stop.strip() == "DefaultTimeoutStopUSec=45s", stop
        user_stop = machine.succeed(
            "systemctl --user --machine=austin@.host show -p DefaultTimeoutStopUSec"
        )
        assert user_stop.strip() == "DefaultTimeoutStopUSec=45s", user_stop

    with subtest("Update reminder reads the packages' date (update-reminder)"):
        user = "systemctl --user --machine=austin@.host"
        machine.succeed(f"{user} is-active update-reminder.timer")
        # Runs now instead of 15 minutes after login; fails if the
        # notification (sent when flake.lock is over two weeks old) does.
        machine.succeed(f"{user} start update-reminder.service")
        # The date is the third part of the version (26.05.20260926.5e2305d).
        day = machine.succeed("nixos-version | cut -d. -f3").strip()
        day = f"{day[:4]}-{day[4:6]}-{day[6:]}"
        machine.wait_until_succeeds(
            "journalctl -o cat _SYSTEMD_USER_UNIT=update-reminder.service"
            f" | grep -qF 'System packages are from {day}'",
            timeout=30,
        )

    with subtest("Plugging in the backup drive backs up /home (backup-on-plug)"):
        # Set up the password and format the drive as backup-setup does,
        # then "plug it in" (formatting alone doesn't start a backup).
        machine.succeed(
            "install -d -m 700 /etc/secrets"
            " && echo test-password > /etc/secrets/restic-password"
            " && chmod 600 /etc/secrets/restic-password"
        )
        machine.succeed("mkfs.ext4 -q -L BACKUP /dev/vdb && udevadm settle")
        machine.fail("test -e /var/lib/restic-home-last-success")
        machine.succeed("udevadm trigger --action=add /dev/vdb")
        machine.wait_until_succeeds("test -e /var/lib/restic-home-last-success", timeout=300)
        machine.succeed("mountpoint -q /mnt/backup")
        snapshots = machine.succeed("restic-home snapshots")
        assert "/home/austin" in snapshots, snapshots

    with subtest("NTFS and exFAT drives can be formatted and written"):
        machine.succeed("command -v mkfs.ntfs ntfsfix mkfs.exfat fsck.exfat")
        for fstype, mkfs in [("ntfs3", "mkfs.ntfs -Q -F"), ("exfat", "mkfs.exfat")]:
            machine.succeed(f"{mkfs} /dev/vdc")
            machine.succeed(
                f"mkdir -p /mnt/usb && mount -t {fstype} /dev/vdc /mnt/usb"
                " && echo written > /mnt/usb/file && umount /mnt/usb"
            )

    with subtest("Smart cards: pcscd, OpenSC, cac-setup and LibreWolf's CAC module"):
        machine.succeed("systemctl is-active pcscd.socket")
        machine.succeed("su - austin -c 'command -v cac-setup pcsc_scan pkcs11-tool'")
        # OpenSC loads (with no reader it reports no slots and exits 1).
        info = machine.execute("su - austin -c 'pkcs11-tool --show-info' 2>&1")[1]
        assert "OpenSC Project" in info, info
        # LibreWolf's built-in policies load OpenSC.
        wrapper = machine.succeed("readlink -f /run/current-system/sw/bin/librewolf").strip()
        policies = wrapper.rsplit("/bin/", 1)[0] + "/lib/librewolf/distribution/policies.json"
        machine.succeed(f"grep -q opensc-pkcs11.so {policies}")

    with subtest("NVIDIA: driver installed, offload command, Steam on the RTX 4060"):
        # The VM has no NVIDIA GPU, so the driver can't load here; check that
        # it's installed for the running kernel and that the offload pieces
        # exist.
        machine.succeed("modinfo -F version nvidia")
        machine.succeed("su - austin -c 'command -v nvidia-offload nvidia-smi'")
        # Steam's environment (its FHS profile) starts it on the NVIDIA GPU.
        machine.succeed(
            "nix-store -qR \"$(readlink -f /run/current-system/sw/bin/steam)\""
            " | grep -- '-fhsenv-profile$'"
            " | xargs grep -rqs __NV_PRIME_RENDER_OFFLOAD"
        )

    with subtest("Gaming: NTSYNC for Proton, split-lock throttling off"):
        # /dev/ntsync exists and Proton (any user) can open it.
        machine.succeed("test -c /dev/ntsync")
        mode = machine.succeed("stat -c %a /dev/ntsync").strip()
        assert mode == "644", f"/dev/ntsync mode {mode}"
        # The VM's CPU may not offer split-lock detection, so the setting is
        # checked only where the kernel has it.
        machine.succeed(
            "test ! -e /proc/sys/kernel/split_lock_mitigate"
            " || [ \"$(cat /proc/sys/kernel/split_lock_mitigate)\" = 0 ]"
        )

    with subtest("sudo is sudo-rs"):
        sudo_version = machine.succeed("sudo --version")
        assert "sudo-rs" in sudo_version, sudo_version

    with subtest("Neovim is set up for LazyVim"):
        # ~/.config/nvim points into the config checkout (the VM has none,
        # so the link dangles here; on the laptop it's ~/nixos-config).
        machine.succeed(
            "test \"$(readlink -m /home/austin/.config/nvim)\""
            " = /home/austin/nixos-config/home/austin/nvim"
        )
        # Home Manager didn't write its own init.lua there (sideloadInitLua).
        machine.fail("test -e /home/austin/.config/nvim/init.lua")
        # nvim runs, and its wrapper carries the tools LazyVim needs.
        machine.succeed("su - austin -c 'nvim --version'")
        wrapper = machine.succeed("su - austin -c 'cat \"$(command -v nvim)\"'")
        for tool in ["tree-sitter", "gcc", "nil", "lazygit"]:
            assert tool in wrapper, f"{tool} missing from nvim's PATH: {wrapper}"

    # Anything else that failed in the VM, for the log (not a test failure:
    # see the list above).
    print(machine.execute("systemctl --failed --no-pager")[1])
  '';
}
