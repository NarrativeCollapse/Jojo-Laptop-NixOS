# hardware-check: the hardware checklist's checks that a script can do (see
# "Hardware checklist" in README.md), each printed as OK, CHECK (worth a
# look) or INFO, plus a report with the details: share that file when
# asking for help with the hardware. It holds no passwords, serial numbers
# or network names. Run it in the Plasma session (the screen check needs
# it), with Steam closed. Built by modules/hardware.nix, which sets HOST,
# NVIDIA_BUS_IDS and PATH.

report=$HOME/hardware-report-$HOST-$(date +%F).txt
problems=0
: > "$report"

say() { printf '%s\n' "$*" | tee -a "$report"; }
ok() { say "  OK     $*"; }
check() {
  say "  CHECK  $*"
  problems=$((problems + 1))
}
info() { say "  INFO   $*"; }
# details <title> <command...>: a command's output, for the report only.
details() {
  local title=$1
  shift
  {
    echo
    echo "## $title"
    "$@" 2>&1 || true
  } >> "$report"
}
read_file() { cat "$1" 2>/dev/null || true; }
# PCI devices of a class (sysfs, e.g. 0x03 display, 0x0280 network):
# "<address> <vendor id>", one per line.
pci_class() {
  local dev
  for dev in /sys/bus/pci/devices/*; do
    if [[ $(read_file "$dev/class") == "$1"* ]]; then
      echo "${dev##*/} $(read_file "$dev/vendor")"
    fi
  done
}
# 0000:01:00.0 -> PCI:1:0:0, the form hardware.nvidia.prime uses.
prime_id() {
  local a=${1#*:}
  echo "PCI:$((16#${a%%:*})):$((16#$(cut -d: -f2 <<< "$a" | cut -d. -f1))):$((16#${a##*.}))"
}
driver_of() {
  local link
  link=$(readlink "/sys/bus/pci/devices/$1/driver" 2>/dev/null || true)
  if [ -n "$link" ]; then basename "$link"; else echo none; fi
}

say "Hardware check: $HOST, $(date '+%F %R')"
say ""

# The laptop
say "Laptop"
info "$(read_file /sys/class/dmi/id/sys_vendor) $(read_file /sys/class/dmi/id/product_name)" \
  "(board $(read_file /sys/class/dmi/id/board_name), BIOS $(read_file /sys/class/dmi/id/bios_version)" \
  "from $(read_file /sys/class/dmi/id/bios_date))"
info "Kernel $(uname -r), $(nixos-version 2>/dev/null || true)"

# Graphics
say ""
say "Graphics"
mapfile -t gpus < <(pci_class 0x03)
nvidia_dev=""
actual=()
for gpu in "${gpus[@]}"; do
  read -r addr vendor <<< "$gpu"
  case $vendor in
    0x8086) name=Intel ;;
    0x10de)
      name=NVIDIA
      nvidia_dev=$addr
      ;;
    *) name=$vendor ;;
  esac
  info "$name GPU at $addr ($(prime_id "$addr")), driver: $(driver_of "$addr")"
  actual+=("$(prime_id "$addr")")
done
if [ -n "$NVIDIA_BUS_IDS" ]; then
  for id in $NVIDIA_BUS_IDS; do
    if [[ " ${actual[*]} " == *" $id "* ]]; then
      ok "The config's GPU address $id is right (modules/nvidia.nix)"
    else
      check "No GPU at the config's address $id: put the ones above in modules/nvidia.nix"
    fi
  done
fi
if [ -n "$nvidia_dev" ]; then
  # Read before anything talks to the GPU (nvidia-smi wakes it).
  state=$(read_file "/sys/bus/pci/devices/$nvidia_dev/power/runtime_status")
  if [ "$state" = suspended ]; then
    ok "The NVIDIA GPU is powered off while nothing uses it"
  else
    check "The NVIDIA GPU is ${state:-in an unknown state}, not powered off. Close Steam and unplug" \
      "an HDMI display, wait a minute and run this again; if it stays on, try" \
      "'sudo systemctl stop nvidia-powerd' (see modules/nvidia.nix, dynamicBoost)"
  fi
  if command -v nvidia-smi >/dev/null; then
    info "$(nvidia-smi --query-gpu=name,driver_version,vbios_version --format=csv,noheader 2>/dev/null || echo "nvidia-smi failed")"
    details "nvidia-smi" nvidia-smi
  fi
fi

# The screen: its refresh rate (from Plasma's display settings).
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v kscreen-doctor >/dev/null; then
  screens=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)
  details "kscreen-doctor -o" echo "$screens"
  # The built-in panel (eDP): its current mode is marked with *.
  panel=$(awk '/^Output:/ { inside = /eDP/ } inside' <<< "$screens")
  current=$(grep -oE '[0-9]+x[0-9]+@[0-9.]+\*' <<< "$panel" | head -n 1 | tr -d '*' || true)
  if [ -n "$current" ]; then
    res=${current%@*}
    hz=${current#*@}
    max=$(grep -oE "$res@[0-9.]+" <<< "$panel" | cut -d@ -f2 | sort -n | tail -n 1)
    if [ "${hz%.*}" -ge "${max%.*}" ]; then
      ok "The screen runs at its highest refresh rate: $res, ${hz%.*} Hz"
    else
      check "The screen runs at ${hz%.*} Hz but can do ${max%.*} Hz: System Settings → Display Configuration → Refresh rate"
    fi
  else
    info "Couldn't read the built-in screen's mode (details in the report)"
  fi
else
  info "Screen not checked: run hardware-check in a terminal in Plasma for that"
fi

# Power: sleep, battery, Acer's interfaces
say ""
say "Power"
sleep_modes=$(read_file /sys/power/mem_sleep)
info "Sleep modes: ${sleep_modes:-unknown} (the one in [ ] is used; s2idle is \"modern standby\")"
for bat in /sys/class/power_supply/BAT*; do
  [ -e "$bat" ] || continue
  full=$(read_file "$bat/energy_full")
  design=$(read_file "$bat/energy_full_design")
  [ -n "$full" ] || full=$(read_file "$bat/charge_full")
  [ -n "$design" ] || design=$(read_file "$bat/charge_full_design")
  health=""
  if [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ]; then
    health=", holds $((full * 100 / design))% of its original capacity"
  fi
  info "Battery: $(read_file "$bat/capacity")%, $(read_file "$bat/status")$health"
done
limit=/sys/bus/wmi/drivers/acer-wmi-battery/health_mode
if [ -e "$limit" ]; then
  if [ "$(read_file "$limit")" = 1 ]; then
    ok "Battery charge limit (80%) is on"
  else
    check "Battery charge limit is off (enable_health_mode in modules/hardware.nix)"
  fi
elif grep -q acer-wmi-battery /etc/modprobe.d/nixos.conf 2>/dev/null; then
  check "The battery charge limit's driver (acer-wmi-battery) didn't start: 'journalctl -k | grep -i acer' says why"
fi
if [ -e /sys/firmware/acpi/platform_profile_choices ]; then
  info "Power modes: $(read_file /sys/firmware/acpi/platform_profile_choices) (now: $(read_file /sys/firmware/acpi/platform_profile))"
elif [[ $(read_file /sys/class/dmi/id/sys_vendor) == Acer* ]]; then
  info "No Acer power modes (they can be forced on: predator_v4 in modules/hardware.nix)"
fi
if command -v powerprofilesctl >/dev/null; then
  info "Power profile: $(powerprofilesctl get 2>/dev/null || echo unknown)"
fi

# Temperatures
cpu_max=$(sensors -u 2>/dev/null | awk '/temp[0-9]+_input/ { t = int($2); if (t > m) m = t } END { if (m) print m }' || true)
if [ -n "$cpu_max" ]; then
  if [ "$cpu_max" -lt 90 ]; then
    ok "Hottest sensor: $cpu_max °C"
  else
    check "Hottest sensor: $cpu_max °C (90 or more; fine under a game, not at idle)"
  fi
fi
details "sensors" sensors

# Wireless, sound, devices
say ""
say "Devices"
while read -r addr vendor; do
  [ -n "$addr" ] || continue
  driver=$(driver_of "$addr")
  info "Wi-Fi card: $(lspci -s "$addr" 2>/dev/null | cut -d' ' -f2- || echo "$vendor"), driver: $driver"
  if [[ $driver == rtw89* ]]; then
    info "  A Realtek card: if Wi-Fi drops, see the rtw89 lines in modules/hardware.nix"
  fi
done < <(pci_class 0x0280)
if nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^wifi:connected'; then
  ok "Wi-Fi is connected"
else
  info "Wi-Fi isn't connected"
fi
if [ -e /sys/class/bluetooth/hci0 ]; then
  ok "Bluetooth adapter found"
else
  check "No Bluetooth adapter found"
fi
if sink=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -m 1 'node.description' | cut -d'"' -f2); then
  ok "Sound output: ${sink:-found}"
else
  check "No sound output found (wpctl status shows what PipeWire sees)"
fi
if [ -c /dev/ntsync ] && [ "$(stat -c %a /dev/ntsync)" = 644 ]; then
  ok "NTSYNC is available to Proton"
else
  check "NTSYNC isn't available (/dev/ntsync, modules/gaming.nix)"
fi
details "lspci -nnk" lspci -nnk
details "lsblk" lsblk -o NAME,SIZE,TYPE,FSTYPE,TRAN,MODEL
usb_devices() {
  local product
  for product in /sys/bus/usb/devices/*/product; do
    [ -e "$product" ] || continue
    echo "$(basename "$(dirname "$product")"): $(read_file "$product")"
  done
}
details "USB devices" usb_devices

# The system
say ""
say "System"
mapfile -t failed < <(systemctl --failed --no-legend --plain 2>/dev/null | awk '{ print $1 }')
if [ "${#failed[@]}" -eq 0 ]; then
  ok "No failed services"
else
  check "Failed services: ${failed[*]} (journalctl -u <name> says why)"
fi
details "Errors in this boot's log" journalctl -b -p err --no-pager -q

say ""
if [ "$problems" -eq 0 ]; then
  say "Nothing to look at."
else
  say "$problems thing(s) to look at (CHECK above)."
fi
echo "Report with the details: $report"
