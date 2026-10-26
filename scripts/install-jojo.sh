# install-jojo: erase a disk, encrypt it and install this config (the
# installer ISO). Built by hosts/installer/configuration.nix, which sets
# REPO_URL, SNAPSHOT, SNAPSHOT_REV, CONFIG_VERSION, KERNEL_CACHE and PATH
# and adds scripts/lib/confirm.sh.

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

step() {
  echo
  echo "== $1"
}

cat <<'INTRO'
Install jojo

This erases one disk completely, encrypts it (you'll choose the
password asked at every boot), and installs this NixOS config on it.
INTRO
echo "Config snapshot on this USB stick: $CONFIG_VERSION (commit $SNAPSHOT_REV)."

step "1. Internet"
until curl -fsS --max-time 10 -o /dev/null https://cache.nixos.org/nix-cache-info; do
  echo "No internet connection. Packages are downloaded during the install."
  read -r -p "Press Enter to open the Wi-Fi setup (nmtui), or Ctrl+C to stop. " _
  nmtui || true
done
echo "Connected."
# jojo's kernel (CachyOS, modules/kernel.nix) downloads from its own cache.
# Checked now, before anything is erased: without it, the install would
# compile the kernel, an hour or more.
if ! curl -fsS --max-time 15 -o /dev/null "$KERNEL_CACHE/nix-cache-info"; then
  echo "The kernel's download server ($KERNEL_CACHE) can't be reached, so the"
  echo "install would have to compile the kernel (an hour or more). Trying again"
  echo "later is usually better."
  confirm "Install anyway?" || exit 1
fi

step "2. Choose the disk to erase"
iso_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /iso 2>/dev/null)" 2>/dev/null || true)
mapfile -t disks < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" && $1 !~ /zram|loop/ { print $1 }' | grep -v -x "/dev/${iso_disk:-none}" || true)
if [ "${#disks[@]}" -eq 0 ]; then
  echo "No disks found (other than this USB stick)."
  exit 1
fi
lsblk -dpo NAME,SIZE,MODEL,TRAN "${disks[@]}"
echo "(The laptop's own SSD is the nvme one, usually /dev/nvme0n1. Disks marked"
echo "usb are external drives: better unplugged before installing.)"
echo
read -r -p "Disk to install on (e.g. /dev/nvme0n1): " disk
[[ $disk == /dev/* ]] || disk="/dev/$disk"
if [[ " ${disks[*]} " != *" $disk "* ]]; then
  echo "'$disk' isn't one of the disks listed above. Nothing was changed."
  exit 1
fi
echo
echo "EVERYTHING on $disk will be erased:"
lsblk -po NAME,SIZE,FSTYPE,LABEL "$disk"
read -r -p "Type the disk name ($disk) again to erase it: " again
[[ $again == /dev/* ]] || again="/dev/$again"
if [ "$again" != "$disk" ]; then
  echo "Stopped; nothing was changed."
  exit 1
fi

step "3. Disk encryption password"
echo "Asked at every boot. If it's lost, the data can't be recovered."
while true; do
  read -r -s -p "Password: " pw1
  echo
  read -r -s -p "Again: " pw2
  echo
  if [ -z "$pw1" ]; then
    echo "The password can't be empty."
  elif [ "$pw1" != "$pw2" ]; then
    echo "They don't match; try again."
  else
    break
  fi
done

step "4. Partitioning and encrypting $disk"
umount -R /mnt 2>/dev/null || true
# Lock any encrypted volume an earlier, interrupted run left unlocked on
# this disk: otherwise the kernel keeps the old partitions in use and
# formatting fails with "device in use".
lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "crypt" { print $1 }' | while read -r dev; do
  cryptsetup close "$dev" || true
done
wipefs -af "$disk"
sgdisk --zap-all "$disk"
sgdisk -n1:1MiB:+1GiB -t1:ef00 -c1:BOOT -n2:0:0 -t2:8309 -c2:cryptroot "$disk"
partprobe "$disk" || true
udevadm settle
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "part" { print $1 }')
boot=${parts[0]}
root=${parts[1]}
mkfs.fat -F 32 -n BOOT "$boot"
printf '%s' "$pw1" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$root"
luks="luks-$(cryptsetup luksUUID "$root")"
printf '%s' "$pw1" | cryptsetup open --key-file=- "$root" "$luks"
unset pw1 pw2
mkfs.ext4 -F -L nixos "/dev/mapper/$luks"
mount "/dev/mapper/$luks" /mnt
mkdir -p /mnt/boot
mount -o umask=077 "$boot" /mnt/boot

step "5. The config"
nixos-generate-config --root /mnt
dest=/mnt/home/austin/nixos-config
mkdir -p /mnt/home/austin
cloned=0
echo "Downloading the latest config from GitHub..."
if GIT_TERMINAL_PROMPT=0 git clone --quiet "$REPO_URL" "$dest"; then
  cloned=1
  echo "Using $(git -C "$dest" log -1 --format='%h: %s')"
else
  echo "Couldn't reach GitHub; using the copy on this USB stick ($CONFIG_VERSION)."
  rm -rf "$dest"
fi
if [ "$cloned" -eq 0 ]; then
  cp -rL --no-preserve=mode "$SNAPSHOT" "$dest"
  git -C "$dest" init --quiet --initial-branch=main
  git -C "$dest" remote add origin "$REPO_URL"
fi
cp /mnt/etc/nixos/hardware-configuration.nix "$dest/hosts/jojo/hardware-configuration.nix"
# nixos-generate-config also wrote a generic configuration.nix. The system
# is built from ~/nixos-config, so remove both rather than leave files
# that look like they matter.
rm -f /mnt/etc/nixos/configuration.nix /mnt/etc/nixos/hardware-configuration.nix
git -C "$dest" add -A
git -C "$dest" -c user.name="install-jojo" -c user.email="install-jojo@localhost" \
  commit --quiet -m "hosts/jojo: hardware configuration for this install"

step "6. Installing (downloads the system; this takes a while)"
nixos-install --no-root-passwd --flake "$dest#jojo"

step "7. Your login password"
until nixos-enter --root /mnt -c "passwd austin"; do
  echo "Try again."
done
nixos-enter --root /mnt -c "chown -R austin:users /home/austin"

echo
echo "Done. jojo is installed on $disk."
echo "The new hardware configuration is committed in ~/nixos-config but not"
echo "pushed; after logging in to GitHub on the laptop, run: cd ~/nixos-config && git push"
if [ "$cloned" -eq 0 ]; then
  cat <<'NEXT'

The config in ~/nixos-config is the copy from this USB stick, not yet
connected to GitHub. After the first login, see "Reinstalling" in its
README.md to connect it.
NEXT
fi
if confirm "Reboot now? (Remove the USB stick when the screen goes dark.)"; then
  systemctl reboot
fi
