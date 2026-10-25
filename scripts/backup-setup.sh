# backup-setup: the one-time backup setup (password, drive, first backup).
# Built by modules/backup.nix, which sets BACKUP_HOME and PATH and adds
# scripts/lib/confirm.sh.

password=/etc/secrets/restic-password

echo "Backup setup: daily encrypted backups of $BACKUP_HOME to an external drive."
echo

# 1. The repository password.
if sudo test -s "$password"; then
  echo "OK  Backup password: already set ($password)."
else
  echo "Step 1 of 3: the backup password."
  echo "Every backup is encrypted with it. If it's lost, the backups can never be read."
  pw=$(head -c 32 /dev/urandom | base64)
  echo
  echo "    $pw"
  echo
  echo "Save it now somewhere OFF this laptop (password manager, printed sheet)."
  read -r -p "Type 'saved' once it's stored: " reply
  if [ "$reply" != saved ]; then
    echo "Stopped; nothing was changed."
    exit 1
  fi
  sudo install -d -m 700 /etc/secrets
  sudo install -m 600 /dev/stdin "$password" <<< "$pw"
  echo "OK  Password saved to $password (readable by root only)."
fi
echo

# 2. The drive: a partition labelled BACKUP (mounted at /mnt/backup).
if [ -e /dev/disk/by-label/BACKUP ]; then
  echo "OK  Backup drive: found a partition labelled BACKUP ($(readlink -f /dev/disk/by-label/BACKUP))."
else
  echo "Step 2 of 3: the backup drive."
  read -r -p "Plug in the external drive to use, then press Enter. " _
  sleep 2
  mapfile -t usb < <(lsblk -dnro NAME,TRAN | awk '$2 == "usb" { print $1 }')
  if [ "${#usb[@]}" -eq 0 ]; then
    echo "No USB drive found. Plug one in and run backup-setup again."
    exit 1
  fi
  echo
  for disk in "${usb[@]}"; do
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "/dev/$disk"
    echo
  done
  read -r -p "Partition to use (e.g. sdb1). EVERYTHING on it will be erased: " part
  disk=$(lsblk -dno PKNAME "/dev/$part" 2>/dev/null || true)
  [ -n "$disk" ] || disk=$part
  if [[ ! -b /dev/$part || " ${usb[*]} " != *" $disk "* ]]; then
    echo "'$part' isn't one of the USB drives listed above. Nothing was changed."
    exit 1
  fi
  read -r -p "Type '$part' again to erase it and format it for backups: " again
  if [ "$again" != "$part" ]; then
    echo "Stopped; nothing was changed."
    exit 1
  fi
  # Unmount it if the desktop mounted it when it was plugged in.
  if [ -n "$(lsblk -no MOUNTPOINTS "/dev/$part" | tr -d '[:space:]')" ]; then
    sudo umount "/dev/$part"
  fi
  sudo mkfs.ext4 -F -L BACKUP "/dev/$part"
  sudo udevadm settle
  echo "OK  /dev/$part is formatted and labelled BACKUP."
fi
echo

# 3. Mount it and run the first backup.
echo "Step 3 of 3: the first backup."
if ! mountpoint -q /mnt/backup; then
  sudo mount /mnt/backup
fi
if ! confirm "Run the first backup now? It can take a while."; then
  echo "Setup is done. Plugging in the drive backs up straight away (and daily while it stays plugged in)."
  exit 0
fi
if ! sudo systemctl start restic-backups-home; then
  echo "The backup failed. See what happened: journalctl -u restic-backups-home"
  exit 1
fi
sudo restic-home snapshots
echo
echo "Backups are set up. From now on, plugging in the drive backs up straight away"
echo "(a desktop notification says when it's done); while it stays plugged in, the"
echo "backup also runs daily."
