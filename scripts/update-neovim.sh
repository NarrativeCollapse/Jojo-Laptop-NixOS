# update-neovim ([n] in `update`): update LazyVim and its plugins to their
# latest versions, show which ones changed, and commit the new pins in
# lazy-lock.json. Built by modules/updates.nix, which sets CONFIG_FLAKE and
# PATH and adds scripts/lib/confirm.sh.

lock=home/austin/nvim/lazy-lock.json
cd "$CONFIG_FLAKE"

if [ -n "$(git status --porcelain -- "$lock")" ]; then
  echo "$lock has uncommitted changes (from :Lazy inside Neovim?)."
  echo "Commit or discard them first; to see them: cd $CONFIG_FLAKE && git diff $lock"
  exit 1
fi

echo "Fetching config changes from GitHub..."
if ! git pull --ff-only --quiet; then
  echo "git pull failed (offline, or local commits that need merging first)."
  exit 1
fi

if ! confirm "Update LazyVim and its Neovim plugins to their latest versions?"; then
  echo "Nothing changed."
  exit 0
fi

echo "Updating Neovim plugins (this can take a minute)..."
log=$(mktemp)
trap 'rm -f "$log"' EXIT
if ! nvim --headless "+Lazy! sync" +qa >"$log" 2>&1; then
  tail -n 20 "$log"
  echo "Neovim reported an error; see above. Nothing was committed."
  exit 1
fi

if git diff --quiet -- "$lock"; then
  echo "Neovim plugins are already up to date."
  exit 0
fi

echo
echo "Updated:"
git diff -U0 -- "$lock" | sed -n 's/^+ *"\([^"]*\)".*/  \1/p'
git commit --quiet -m "chore: update Neovim plugins" -- "$lock"
if git push --quiet; then
  echo "The new plugin versions are committed and pushed to GitHub."
else
  echo "The new plugin versions are committed, but pushing failed. Later, run:"
  echo "  cd $CONFIG_FLAKE && git push"
fi
echo "To go back: cd $CONFIG_FLAKE && git revert HEAD, then :Lazy restore in Neovim."
