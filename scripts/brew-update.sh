# brew-update ([b] in `update`): install Homebrew the first time, then show how
# the installed formulas differ from the Brewfile and apply that on a yes.
# Built by modules/homebrew.nix, which sets BREW_PREFIX, BREWFILE and PATH
# and adds scripts/lib/confirm.sh.

brew=$BREW_PREFIX/bin/brew
brewfile=$BREWFILE

if ! curl -fsSI --max-time 15 -o /dev/null https://github.com; then
  echo "No network connection; can't check Homebrew for updates."
  exit 1
fi

if [ ! -d "$BREW_PREFIX/Homebrew" ]; then
  echo "Homebrew isn't installed yet."
  confirm "Install it into $BREW_PREFIX now?" || exit 0
  # Clone beside the final path so an interrupted clone isn't
  # mistaken for an installed Homebrew next time.
  rm -rf "$BREW_PREFIX/Homebrew.partial"
  git clone https://github.com/Homebrew/brew "$BREW_PREFIX/Homebrew.partial"
  mv "$BREW_PREFIX/Homebrew.partial" "$BREW_PREFIX/Homebrew"
fi
mkdir -p "$BREW_PREFIX/bin"
ln -sfn ../Homebrew/bin/brew "$BREW_PREFIX/bin/brew"

echo "Checking Homebrew for updates..."
"$brew" update --quiet
pending=$("$brew" bundle check --verbose --file="$brewfile" 2>&1 || true)
# Formulas not in the Brewfile (the dry run also lists download
# caches brew would clear; those aren't worth asking about).
extra=$("$brew" bundle cleanup --file="$brewfile" 2>/dev/null \
  | sed -n '/^Would uninstall/,/^Would .brew cleanup/p' \
  | grep -v '^Would .brew cleanup' || true)
if "$brew" bundle check --quiet --file="$brewfile" >/dev/null 2>&1 && [ -z "$extra" ]; then
  echo "Homebrew tools are up to date."
  exit 0
fi

echo
echo "$pending"
if [ -n "$extra" ]; then echo "$extra"; fi
echo
if ! confirm "Apply these Homebrew changes?"; then
  echo "Nothing changed."
  exit 0
fi
"$brew" bundle install --file="$brewfile"
"$brew" bundle cleanup --force --file="$brewfile"
echo "Homebrew tools updated."
