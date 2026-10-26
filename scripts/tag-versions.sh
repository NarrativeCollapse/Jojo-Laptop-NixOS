#!/usr/bin/env bash
# Tags every config version that has no git tag yet (0.3, 0.4, ...) on the
# commit that first set it in flake.nix, and prints the new tags' names. Run
# by the Tag versions workflow on every push to main, which then pushes the
# new tags; existing tags are left alone, so it's safe to run again and the
# first run also tags the older versions that never got one. Needs the
# full history (not a shallow clone).
set -euo pipefail

declare -A first # version -> the first commit that set it
# Every commit that changed flake.nix, oldest first. Only 0.N versions are
# tagged: v1-v3 were development numbers, never installed (see Versions in
# README.md).
while read -r commit; do
  version=$(git show "$commit:flake.nix" | grep -oE '^\s*version = "[0-9]+\.[0-9]+";' | cut -d'"' -f2 || true)
  if [ -n "$version" ] && [ -z "${first[$version]:-}" ]; then
    first[$version]=$commit
  fi
done < <(git log --reverse --format=%H -- flake.nix)

for version in "${!first[@]}"; do
  if ! git rev-parse --quiet --verify "refs/tags/$version" >/dev/null; then
    git tag -a "$version" -m "Config $version" "${first[$version]}"
    echo "$version"
  fi
done | sort -V
