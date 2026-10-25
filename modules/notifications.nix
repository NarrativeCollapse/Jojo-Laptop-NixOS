{ lib, pkgs, ... }:

# Desktop notifications from system services, so problems don't sit unseen
# in the journal.
let
  # `notify-desktop <app> <icon> <title> <body>`: a critical notification in
  # austin's Plasma session, sent from a system service (running as root).
  # Skips quietly when austin isn't logged in. runuser keeps this script's
  # PATH, so notify-send is found directly.
  notifyDesktop = pkgs.writeShellApplication {
    name = "notify-desktop";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
      util-linux
    ];
    text = ''
      bus=/run/user/$(id -u austin)/bus
      [ -S "$bus" ] || exit 0
      runuser -u austin -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        notify-send --urgency=critical --app-name="$1" --icon="$2" "$3" "$4"
    '';
  };
in
{
  # For other modules: `lib.getExe config.my.notifyDesktop` is the command.
  # Used by notify-failure@ below and by smartd (hardware.nix).
  options.my.notifyDesktop = lib.mkOption {
    type = lib.types.package;
    default = notifyDesktop;
    readOnly = true;
    description = "Sends a critical desktop notification to austin from a system service.";
  };

  # `notify-failure@`: attach it to a system unit with
  #   onFailure = [ "notify-failure@%n.service" ];
  # and a failure raises a notification with the journalctl command that
  # shows why. Used by restic-backups-home (backup.nix).
  config.systemd.services."notify-failure@" = {
    description = "Desktop notification that %i failed";
    serviceConfig.Type = "oneshot";
    scriptArgs = "%i";
    script = ''
      ${lib.getExe notifyDesktop} systemd dialog-error \
        "$1 failed" "See what happened: journalctl -u $1"
    '';
  };
}
