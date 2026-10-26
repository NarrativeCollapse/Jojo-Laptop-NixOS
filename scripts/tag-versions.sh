#!/usr/bin/env bash
# Tags the checked-out commit (the one just pushed to main) with the config
# version its flake.nix sets (0.3, 0.4, ...), unless that version already
# has a tag, and prints the new tag's name. Run by the Tag versions
# workflow, which then pushes it. Only the pushed commit is tagged: GitHub
# refuses to let a workflow tag an older commit whose workflow files differ
# from the current ones, which is why 0.1 and 0.2 have no tags.
set -euo pipefail

version=$(grep -oE '^\s*version = "[0-9]+\.[0-9]+";' flake.nix | cut -d'"' -f2)
if ! git rev-parse --quiet --verify "refs/tags/$version" >/dev/null; then
  git tag -a "$version" -m "Config $version" HEAD
  echo "$version"
fi
