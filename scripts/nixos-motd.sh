# nixos-motd: the welcome banner shown in new shells.
# Built by home/austin/bling.nix, which sets MOTD_TIPS, MOTD_TEMPLATE,
# MOTD_LOGO and PATH.

if [ -e "${XDG_CONFIG_HOME:-$HOME/.config}/no-show-user-motd" ]; then
  exit 0
fi
# Not inside containers (distrobox, toolbox, podman): the banner
# describes this machine, not the box.
if [ -n "${CONTAINER_ID:-}" ] || [ -e /run/.containerenv ] || [ -e /.dockerenv ]; then
  exit 0
fi
# shellcheck source=/dev/null
OS_NAME=$(. /etc/os-release && echo "$PRETTY_NAME")
SYSINFO=$(nixos-system-info)
TIP=$(shuf -n 1 "$MOTD_TIPS")
export OS_NAME SYSINFO TIP
# shellcheck disable=SC2016
rendered=$(envsubst '$OS_NAME $SYSINFO $TIP' < "$MOTD_TEMPLATE")

# Header: the logo in plain white, with the heading and system lines
# beside it in the colors glow uses for the rest of the banner.
if [ -t 1 ]; then
  w=$'\e[37m' h=$'\e[93;104;1m' c=$'\e[91;40m' r=$'\e[0m'
else
  w="" h="" c="" r=""
fi
info=(
  ""
  "$h Welcome to NixOS  $r"
  ""
  "  $c $OS_NAME $r"
  ""
  "󱋩  $c $SYSINFO $r"
  ""
)
mapfile -t lines < "$MOTD_LOGO"
echo
for i in "${!lines[@]}"; do
  printf '  %s%-14s%s  %s\n' "$w" "${lines[$i]}" "$r" "${info[$i]:-}"
done

if [ -t 1 ]; then
  # When it can see the terminal, glow asks it for its colors and waits
  # up to 20s for replies some terminals (e.g. the Linux console) never
  # send. A fixed style, forced color, silenced stderr and piped stdout
  # keep it from asking.
  CLICOLOR_FORCE=1 glow -s dark -w "$(tput cols 2>/dev/null || echo 80)" - <<< "$rendered" 2>/dev/null | cat
else
  glow -s notty - <<< "$rendered"
fi
