# backup-test [folder]: restore a folder from the latest backup into a
# temporary directory, compare it with the files on disk, and delete it.
# Built by modules/backup.nix, which sets BACKUP_HOME and PATH.

dir=$(realpath -m "${1:-$HOME/Documents}")
case $dir in
  "$BACKUP_HOME" | "$BACKUP_HOME"/*) ;;
  *)
    echo "Pick a folder inside $BACKUP_HOME (the backup only covers your home)."
    exit 1
    ;;
esac
if ! mountpoint -q /mnt/backup; then
  echo "The backup drive isn't mounted. Plug it in (it mounts by itself), or run: sudo mount /mnt/backup"
  exit 1
fi

tmp=$(mktemp -d)
trap 'sudo rm -rf "$tmp"' EXIT
echo "Restoring $dir from the latest backup into a temporary folder..."
sudo restic-home restore latest --target "$tmp" --include "$dir"
sudo chown -R "$(id -u):$(id -g)" "$tmp"
if [ ! -d "$tmp$dir" ]; then
  echo "FAILED: $dir isn't in the latest backup (or nothing could be restored)."
  exit 1
fi

same=0 changed=0 gone=0
while IFS= read -r -d "" restored; do
  current=${restored#"$tmp"}
  if [ ! -e "$current" ]; then
    gone=$((gone + 1))
  elif cmp -s "$restored" "$current"; then
    same=$((same + 1))
  else
    changed=$((changed + 1))
  fi
done < <(find "$tmp$dir" -type f -print0)
total=$((same + changed + gone))
if [ "$total" -eq 0 ]; then
  echo "FAILED: the restore produced no files."
  exit 1
fi

echo
echo "Restore test passed: $total files restored from the latest backup."
echo "  $same identical to the files on disk now"
echo "  $changed changed since that backup (normal for files you've edited)"
echo "  $gone deleted since that backup"
