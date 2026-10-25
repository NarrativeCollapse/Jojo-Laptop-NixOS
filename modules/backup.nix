{
  config,
  lib,
  pkgs,
  ...
}:

let
  # What's backed up: austin's home folder.
  home = config.users.users.austin.home;
  # Touched after every successful backup; read by backup-reminder below.
  stamp = "/var/lib/restic-home-last-success";
  staleDays = 7;
in
{
  ################################
  # Backups: restic for /home
  ################################
  #
  # The system is reproducible from this flake; /home/austin is not. This job
  # backs it up daily to a restic repository.
  #
  # ONE-TIME SETUP: run `backup-setup` (defined below). It creates the
  # repository password in /etc/secrets/restic-password (keep a copy OFF this
  # machine; losing it makes the backups unreadable forever), formats a USB
  # drive partition as ext4 labelled BACKUP, mounts it at /mnt/backup, and
  # runs the first backup. Until then the job skips silently.
  #
  # After that, plugging in the drive is all it takes: it mounts and backs
  # up straight away (backup-on-plug, below), and the daily run covers a
  # drive that's left plugged in.
  #
  # For a remote target instead, change `repository` to e.g.
  # "sftp:austin@myserver:/srv/restic-jojo" and remove the
  # ConditionPathIsMountPoint line.
  #
  # Check and restore (as root; the password file is root-only):
  #        sudo restic-home snapshots
  #        sudo restic-home restore latest --target /tmp/restore \
  #          --include /home/austin/Documents
  #
  # (For proper secret management later, look at sops-nix or agenix; a
  # root-only file outside the store is the simplest sound approach for a
  # single machine.)

  services.restic.backups.home = {
    initialize = true; # create the repo on first run if it doesn't exist
    repository = "/mnt/backup/restic-jojo";
    passwordFile = "/etc/secrets/restic-password";

    paths = [ home ];

    # Excludes tuned for this machine: everything below is either a cache or
    # re-downloadable. The Steam library alone would dwarf the real data.
    # Steam's userdata/, config/ and steamapps/compatdata/ (Proton prefixes,
    # where games without Steam Cloud keep their saves) are still backed up;
    # restic dedups the near-identical Wine files across prefixes.
    exclude = map (path: "${home}/${path}") [
      ".cache"
      ".nv" # NVIDIA's shader and compute caches
      ".local/share/Steam/steamapps/common" # installed games
      ".local/share/Steam/steamapps/shadercache"
      ".local/share/Steam/steamapps/downloading"
      ".local/share/Steam/steamapps/temp"
      ".local/share/Steam/appcache"
      ".local/share/Steam/depotcache"
      ".local/share/Steam/logs"
      ".local/share/Steam/package" # Steam client updates
      ".local/share/Steam/ubuntu12_32" # Steam client runtime
      ".local/share/Steam/ubuntu12_64"
      ".steam"
      ".local/share/Trash"
      ".local/share/containers" # podman images/layers
      ".local/share/baloo" # KDE file indexer
      ".var/app/*/cache" # flatpak app caches
      ".npm"
      ".cargo"
      "**/node_modules"
      "**/.direnv"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true; # run a missed backup at next boot
      RandomizedDelaySec = "15m";
    };

    # Retention, applied via `restic forget --prune` after each backup.
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];

    # `restic check` after every run, so corruption surfaces as a failed unit
    # instead of at restore time. Besides the repository structure, each run
    # re-reads a random 2% of the stored data, so over weeks the file
    # contents themselves are verified too (not just the index).
    runCheck = true;
    checkOpts = [ "--read-data-subset=2%" ];
  };

  systemd.services."restic-backups-home" = {
    # Skip quietly (no failed unit) when the drive isn't attached or setup
    # hasn't been done yet.
    unitConfig = {
      ConditionPathIsMountPoint = "/mnt/backup";
      ConditionPathExists = "/etc/secrets/restic-password";
    };
    # Runs only when backup, prune and check all succeeded.
    serviceConfig.ExecStartPost = [ "${pkgs.coreutils}/bin/touch ${stamp}" ];
    # A run that starts and fails (full drive, wrong password, corrupt repo)
    # raises a desktop notification; see modules/notifications.nix.
    onFailure = [ "notify-failure@%n.service" ];
  };

  # Plugging in the backup drive backs up straight away. udev starts
  # backup-on-plug when a partition labelled BACKUP appears; that mounts
  # /mnt/backup, runs the backup, and when it succeeded says on the desktop
  # that the drive can be unplugged. (Formatting the drive in backup-setup
  # doesn't count as plugging it in, so setup isn't interrupted.)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="BACKUP", TAG+="systemd", ENV{SYSTEMD_WANTS}+="backup-on-plug.service"
  '';
  systemd.services.backup-on-plug = {
    description = "Back up /home when the backup drive is plugged in";
    requires = [ "mnt-backup.mount" ];
    after = [ "mnt-backup.mount" ];
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.coreutils
      pkgs.systemd
    ];
    # The success stamp moves only when a backup really ran and passed (not
    # when the job skipped because setup isn't done yet).
    script = ''
      before=$(stat -c %Y ${stamp} 2>/dev/null || echo 0)
      systemctl start restic-backups-home.service
      after=$(stat -c %Y ${stamp} 2>/dev/null || echo 0)
      if [ "$after" != "$before" ]; then
        ${lib.getExe config.my.notifyDesktop} Backups drive-harddisk "Backup finished" \
          "You can unplug the backup drive: eject it in Disks & Devices first."
      fi
    '';
  };

  # Because the job skips silently, it could stop running for months unseen.
  # Once a day (and shortly after login) warn on the desktop when the last
  # successful backup is missing or older than `staleDays`.
  systemd.user.services.backup-reminder = {
    description = "Warn when the last /home backup is too old";
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.coreutils
      pkgs.libnotify
    ];
    script = ''
      if [ -e ${stamp} ]; then
        age_days=$(( ($(date +%s) - $(stat -c %Y ${stamp})) / 86400 ))
        [ "$age_days" -lt ${toString staleDays} ] && exit 0
        msg="The last successful backup of /home was $age_days days ago. Plug in the backup drive: the backup starts by itself."
      else
        msg="/home has never been backed up. Open a terminal and run: backup-setup"
      fi
      notify-send --urgency=critical --app-name=Backups --icon=drive-harddisk "Backups are out of date" "$msg"
    '';
  };
  # Counted from login, as update-reminder (updates.nix): a calendar timer
  # catching up on a missed day would fire right at login, before Plasma
  # can show the warning, and then again 10 minutes later.
  systemd.user.timers.backup-reminder = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "10min";
      OnUnitActiveSec = "1d";
    };
  };

  # Plain restic CLI available regardless of the module's wrapper;
  # `backup-setup`, which walks through the one-time setup (the repository
  # password, the backup drive, and the first backup); and `backup-test`.
  environment.systemPackages = [
    pkgs.restic
    (pkgs.writeShellApplication {
      name = "backup-setup";
      runtimeInputs = with pkgs; [
        coreutils
        e2fsprogs
        gawk
        systemd
        util-linux
      ];
      runtimeEnv = {
        BACKUP_HOME = home;
      };
      text = builtins.readFile ../scripts/lib/confirm.sh + builtins.readFile ../scripts/backup-setup.sh;
    })

    # `backup-test [folder]`: a real test restore. Restores a folder
    # (~/Documents by default) from the latest backup into a temporary
    # directory, compares it with the files on disk now, and deletes it.
    (pkgs.writeShellApplication {
      name = "backup-test";
      runtimeInputs = with pkgs; [
        coreutils
        diffutils
        findutils
        util-linux
      ];
      runtimeEnv = {
        BACKUP_HOME = home;
      };
      text = builtins.readFile ../scripts/backup-test.sh;
    })
  ];

  # External backup drive: the partition labelled BACKUP (backup-setup
  # formats and labels one). `nofail` means boot proceeds normally when the
  # drive is absent; plugged in later, backup-on-plug mounts it. (If the
  # drive is ever plugged in but not mounted: `sudo mount /mnt/backup`.)
  # Deliberately NOT using x-systemd.automount:
  # an autofs mountpoint would satisfy ConditionPathIsMountPoint even with no
  # drive present, turning the safe skip into a failure.
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-label/BACKUP";
    fsType = "ext4";
    options = [ "nofail" ];
  };
}
