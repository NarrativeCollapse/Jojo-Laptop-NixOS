# update-system ([s] in `update`): update flake.lock, build, show the changes,
# then apply now, at the next restart, or not at all.
# Built by modules/updates.nix, which sets CONFIG_FLAKE, CONFIG_HOST and PATH.

cd "$CONFIG_FLAKE"
files=(flake.lock flake.nix README.md)

if [ -n "$(git status --porcelain -- "${files[@]}")" ]; then
  echo "flake.lock, flake.nix or README.md has uncommitted changes in $CONFIG_FLAKE."
  echo "Commit or discard them first."
  exit 1
fi

echo "Fetching config changes from GitHub..."
if ! git pull --ff-only --quiet; then
  echo "git pull failed (offline, or local commits that need merging first)."
  exit 1
fi

# Whatever happens before the update is applied (a failed step, Ctrl+C),
# the repo is put back exactly as it was: `phase` says how far it got.
#   updating:  flake.lock may be edited, nothing committed yet
#   committed: the version commit exists but isn't applied
#   finished:  applied, or deliberately kept (see "Applying failed")
undo() {
  git reset --quiet --soft HEAD~1
  git restore --staged --worktree -- "${files[@]}"
}
work=$(mktemp -d)
log=$work/update.log
phase=updating
cleanup() {
  rm -rf "$work"
  case $phase in
    updating) git restore --staged --worktree -- "${files[@]}" 2>/dev/null || true ;;
    committed) undo ;;
  esac
}
trap cleanup EXIT

echo "Checking for updates..."
nix flake update 2>&1 | tee "$log"
if git diff --quiet -- flake.lock; then
  echo "No updates: every input is already at its newest version."
  if [ "$(readlink -f /nix/var/nix/profiles/system)" != "$(readlink -f /run/current-system)" ]; then
    echo "(A newer version is waiting to start at the next restart.)"
  elif [ "$(nixos-version --configuration-revision 2>/dev/null || true)" != "$(git rev-parse HEAD)" ]; then
    echo "(The running system isn't built from the latest config commit; \`rebuild\` applies it.)"
  fi
  exit 0
fi

# Bump the config version (flake.nix, README "Current version" and a
# Versions row naming the updated inputs), and commit, so the build
# carries a clean configuration revision.
version=$(python3 scripts/bump-version.py "$log")
git commit --quiet -m "chore: update flake.lock ($version)" -- "${files[@]}"
phase=committed

echo "Building $version (nothing on the system changes yet)..."
# The link in $work keeps the build from being deleted by Nix's cleanup
# (min-free, base.nix) before it's applied.
if ! new=$(nix build --out-link "$work/system" --print-out-paths "$CONFIG_FLAKE#nixosConfigurations.$CONFIG_HOST.config.system.build.toplevel"); then
  echo "The build failed, so nothing was applied. flake.lock is back where it was."
  exit 1
fi

echo
echo "What $version changes compared to the running system:"
nvd diff /run/current-system "$new"
echo
# "Now" switches the running desktop over; for big updates (Plasma, a
# new NixOS release) apps can misbehave until the next login, so
# "at the next restart" starts the new version fresh instead.
echo "Apply $version:"
echo "  [n] Now"
echo "  [r] At the next restart (safer for big updates, e.g. Plasma)"
echo "  [s] Skip"
read -r -n 1 -p "Choose: " how
echo
case $how in
  n | N) mode=switch ;;
  r | R) mode=boot ;;
  *)
    echo "Not applied. flake.lock is back where it was."
    exit 0
    ;;
esac

if ! sudo nixos-rebuild "$mode" --flake "$CONFIG_FLAKE#$CONFIG_HOST"; then
  phase=finished
  echo "Applying failed. The $version commit is kept locally (not pushed)."
  exit 1
fi
phase=finished
if [ "$mode" = boot ]; then
  done_msg="$version starts at the next restart"
else
  done_msg="$version is applied"
fi
git tag -a "$version" -m "Config $version"
if git push --quiet && git push --quiet origin "$version"; then
  echo "$done_msg, and pushed to GitHub with its tag."
else
  echo "$done_msg, but pushing failed. Later, run:"
  echo "  cd $CONFIG_FLAKE && git push && git push origin $version"
fi
