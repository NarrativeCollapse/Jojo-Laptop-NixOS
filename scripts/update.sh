# `update`: the update menu (or `update system|flatpak|brew|neovim|firmware|all|rollback`).
# Built by modules/updates.nix, which puts the update-* commands on PATH.

# brew-update comes from modules/homebrew.nix. A failure in one part
# is reported but doesn't stop the menu or the other parts.
run() {
  "$@" || echo "($1 stopped with an error; see above.)"
  echo
}
all() {
  run update-system
  run update-flatpak
  run brew-update
  run update-neovim
  run update-firmware
}

case "${1:-}" in
  system) run update-system; exit ;;
  flatpak) run update-flatpak; exit ;;
  brew) run brew-update; exit ;;
  neovim) run update-neovim; exit ;;
  firmware) run update-firmware; exit ;;
  all) all; exit ;;
  rollback) run update-rollback; exit ;;
  "") ;;
  *)
    echo "Usage: update [system|flatpak|brew|neovim|firmware|all|rollback]"
    exit 1
    ;;
esac

while true; do
  cat <<'MENU'
  Updates
  ───────
  [s] System (NixOS)   check, show changes, ask to apply
  [f] Flatpak apps
  [b] Homebrew tools
  [n] Neovim plugins (LazyVim)
  [w] Firmware (BIOS and devices)
  [a] All of the above
  [r] Roll back the last system update
  [q] Quit

MENU
  read -r -n 1 -p "  Choose: " key
  echo
  echo
  case $key in
    s | S) run update-system ;;
    f | F) run update-flatpak ;;
    b | B) run brew-update ;;
    n | N) run update-neovim ;;
    w | W) run update-firmware ;;
    a | A) all ;;
    r | R) run update-rollback ;;
    q | Q | "") exit 0 ;;
    *) echo "No option '$key'." && echo ;;
  esac
done
