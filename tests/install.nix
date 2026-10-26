# Installer test: install-jojo, the installer ISO's script (the same
# build), runs in a VM on a blank virtual disk, answered on the console the
# way a person answers it, and then that disk boots: the disk password at
# the prompt, then jojo's login screen. Catches an installer that would
# stop halfway through install day, after Windows is already erased.
#
# What differs from the laptop, because the VM has no internet:
# - The config comes from the copy on the USB stick (GitHub can't be
#   reached), the installer's own fallback.
# - What's installed is jojo prebuilt by CI (INSTALL_JOJO_SYSTEM), not
#   built in the VM from the config the installer just wrote; that config
#   is evaluated, offline, to check it works. The prebuilt system finds its
#   disk by the installer's labels (hosts/jojo/hardware-configuration.nix)
#   and adds only what the test needs: its root shell (test
#   instrumentation), QEMU's drivers, and no boot splash, so the disk
#   password prompt reaches the serial console.
#
# It takes about half an hour and needs ~60 GB of disk. Run it with
#   nix build .#install-test -L
# (the Installer test workflow does, on every push).
{
  # pkgs.writeShellApplication install-jojo, as on the ISO.
  installJojo,
  # The config as copied onto the ISO (/etc/jojo-config there).
  snapshot,
  # jojo's system to install (config.system.build.toplevel).
  installedSystem,
  # The flake's inputs, so the written config evaluates offline: their
  # store paths, and the --override-input arguments that point at them.
  flakeInputs,
  evalOverrides,
}:

let
  diskPassword = "disk-pass";
  userPassword = "austin-pass";
  # The commit install-jojo makes in ~/nixos-config.
  commitMessage = "hosts/jojo: hardware configuration for this install";

  # Both machines are the same computer: they share its disk.
  disk = {
    virtualisation.diskImage = "./target.qcow2";
    virtualisation.diskSize = 64 * 1024;
    virtualisation.cores = 4;
  };
in
{
  name = "jojo-install";
  # Copying the whole system onto the disk takes a while.
  globalTimeout = 2 * 60 * 60;

  nodes = {
    # The installer USB, as far as the test needs: install-jojo, the
    # config copy, and a root shell on the first console.
    installer =
      { lib, ... }:
      {
        imports = [ disk ];
        # UEFI, as on the laptop: jojo's boot loader writes its boot entry
        # into the firmware's variables.
        virtualisation.useEFIBoot = true;
        # The installer's own root is a second disk, so the disk being
        # installed on is /dev/vda before and after.
        virtualisation.emptyDiskImages = [ 8192 ];
        virtualisation.rootDevice = "/dev/vdb";
        virtualisation.fileSystems."/".autoFormat = true;
        # Evaluating jojo's config takes a few GB.
        virtualisation.memorySize = 6144;

        services.getty.autologinUser = "root";
        environment.systemPackages = [ installJojo ];
        environment.etc."jojo-config".source = snapshot;

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          substituters = lib.mkForce [ ];
        };
        # Registered in the VM's Nix store, so nixos-install copies the
        # system from there and the config evaluates without downloads.
        virtualisation.additionalPaths = [ installedSystem ] ++ flakeInputs;
      };

    # The same computer after the install, booting from its disk.
    target = {
      imports = [ disk ];
      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      virtualisation.efi.keepVariables = false;
      virtualisation.memorySize = 4096;
      virtualisation.useDefaultFilesystems = false;
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/this-is-not-real-and-will-never-be-used";
        fsType = "ext4";
      };
    };
  };

  testScript = ''
    import re

    installer.start()
    installer.wait_for_unit("multi-user.target")
    installer.succeed("udevadm settle")
    installer.wait_until_tty_matches("1", "root@installer")

    # install-jojo's output also goes to a log, and when it exits the shell
    # prints its exit status, so a script that stops early fails the test
    # right away, showing its whole output, instead of at a timeout.
    finished = "install-jojo finished: ([0-9]+)"

    def answer(prompt, reply, timeout=900):
        installer.wait_until_tty_matches("1", f"{prompt}|{finished}", timeout=timeout)
        if re.search(finished, installer.get_tty_text("1")):
            print(installer.succeed("cat /tmp/install-jojo.log"))
            raise Exception(f"install-jojo exited before asking: {prompt}")
        installer.send_chars(reply + "\n")

    with subtest("install-jojo installs jojo, answered on the console"):
        installer.send_chars(
            "INSTALL_JOJO_SYSTEM=${installedSystem} install-jojo 2>&1"
            " | tee /tmp/install-jojo.log;"
            " printf 'install-jojo finished: %s\\n' \"''${PIPESTATUS[0]}\"\n"
        )
        answer("Disk to install on", "/dev/vda")
        # Without /dev/, which it accepts too.
        answer("again to erase it", "vda")
        answer("Password: ", "${diskPassword}")
        answer("Again: ", "${diskPassword}")
        # Partitioning, the config, then copying the whole system.
        answer("New password", "${userPassword}", timeout=3600)
        answer("Retype new password", "${userPassword}")
        answer("Reboot now", "n")
        installer.wait_until_tty_matches("1", finished)
        print(installer.succeed("cat /tmp/install-jojo.log"))
        status = re.search(finished, installer.get_tty_text("1")).group(1)
        assert status == "0", f"install-jojo exited with {status}"

    with subtest("The disk has the installer's layout"):
        print(installer.succeed("lsblk -o NAME,PARTLABEL,FSTYPE,LABEL,SIZE /dev/vda"))
        boot_size = installer.succeed("lsblk -bndo SIZE /dev/disk/by-partlabel/BOOT").strip()
        assert boot_size == str(2 * 1024**3), f"boot partition is {boot_size} bytes"
        installer.succeed("test \"$(blkid -o value -s TYPE /dev/disk/by-label/BOOT)\" = vfat")
        installer.succeed("cryptsetup isLuks --type luks2 /dev/disk/by-partlabel/cryptroot")

    with subtest("The config it wrote evaluates"):
        config = "/mnt/home/austin/nixos-config"
        installer.succeed(
            f"git -c safe.directory='*' -C {config} log -1 --format=%s"
            " | grep -qx '${commitMessage}'"
        )
        hardware = installer.succeed(f"cat {config}/hosts/jojo/hardware-configuration.nix")
        assert "luks-" in hardware, hardware
        installer.succeed("test ! -e /mnt/etc/nixos/configuration.nix")
        installer.succeed(
            "nix eval --offline --raw ${evalOverrides}"
            f" path:{config}#nixosConfigurations.jojo.config.system.build.toplevel.drvPath >&2"
        )
        print(installer.succeed("df -h /mnt /mnt/boot"))

    with subtest("Shut the installer down"):
        installer.succeed("umount -R /mnt")
        installer.succeed("for dev in /dev/mapper/luks-*; do cryptsetup close $dev; done")
        installer.succeed("sync")
        installer.shutdown()

    # The same disk, now booting by itself.
    target.state_dir = installer.state_dir

    with subtest("The installed disk boots, asking for the disk password"):
        target.start()
        target.wait_for_console_text("Please enter passphrase for disk")
        target.send_console("${diskPassword}\n")
        target.wait_for_unit("multi-user.target")

    with subtest("It's jojo, as installed"):
        target.succeed('test "$(hostname)" = jojo')
        kernel = target.succeed("readlink -f /run/booted-system/kernel")
        assert "cachyos" in kernel, kernel
        target.succeed("ls /boot/loader/entries | grep -q specialisation-nixos-kernel")
        shadow = target.succeed("getent shadow austin | cut -d: -f2")
        assert shadow.startswith("$"), "austin has no password"
        target.succeed('test "$(stat -c %U /home/austin/nixos-config)" = austin')
        target.succeed(
            "su - austin -c 'git -C ~/nixos-config log -1 --format=%s'"
            " | grep -qx '${commitMessage}'"
        )
        target.wait_for_unit("display-manager.service")
  '';
}
