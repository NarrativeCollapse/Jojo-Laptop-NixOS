#!/usr/bin/env bash
# Prints the arguments that point this flake at the next NixOS release,
# for `nix flake check` and `nix build`. The Next NixOS release workflow
# uses it, and so can you, from the checkout:
#   nix flake check $(scripts/next-release.sh)
#
# The next release is the one after what flake.nix pins (26.05 -> 26.11 ->
# 27.05). Once its branches exist (nixpkgs nixos-<next> and Home Manager
# release-<next>, both needed: a mismatched pair is an evaluation warning),
# it's those; they appear a few weeks before the release. Until then it's
# what the release will be cut from: nixos-unstable and Home Manager master.
# plasma-manager has no release branches, so it's always its latest commit.
# flake.lock isn't touched.
set -euo pipefail
cd "$(dirname "$0")/.."

# 0 if the repository has the branch, 1 if not; anything else (offline,
# GitHub down) stops here rather than quietly testing the wrong release.
branch_exists() {
  local status=0
  git ls-remote --exit-code --heads "$1" "$2" >/dev/null || status=$?
  case $status in
    0) return 0 ;;
    2) return 1 ;;
    *)
      echo "Couldn't reach $1 (git exit code $status)." >&2
      exit 1
      ;;
  esac
}

current=$(grep -oE 'NixOS/nixpkgs/nixos-[0-9]{2}\.(05|11)' flake.nix | head -n 1) || true
if [ -z "$current" ]; then
  echo "Couldn't find the nixos-YY.MM branch of nixpkgs in flake.nix." >&2
  exit 1
fi
current=${current##*nixos-}
year=${current%.*} month=${current#*.}
if [ "$month" = 05 ]; then
  next=$year.11
else
  next=$((10#$year + 1)).05
fi

if branch_exists https://github.com/NixOS/nixpkgs "nixos-$next" &&
  branch_exists https://github.com/nix-community/home-manager "release-$next"; then
  echo "Next release: $next, from its own branches." >&2
  nixpkgs=github:NixOS/nixpkgs/nixos-$next
  home_manager=github:nix-community/home-manager/release-$next
else
  echo "Next release: $next, not branched yet; using nixos-unstable and Home Manager master." >&2
  nixpkgs=github:NixOS/nixpkgs/nixos-unstable
  home_manager=github:nix-community/home-manager
fi

echo "--no-write-lock-file" \
  "--override-input nixpkgs $nixpkgs" \
  "--override-input home-manager $home_manager" \
  "--override-input plasma-manager github:nix-community/plasma-manager"
