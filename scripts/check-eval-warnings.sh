#!/usr/bin/env bash
# Fails if evaluating jojo's system prints any warning (renamed or
# deprecated options, renamed packages). Used by the Check and Next NixOS
# release workflows; extra arguments go to `nix eval` (e.g. --override-input).
set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT

if ! nix eval --raw "$@" .#nixosConfigurations.jojo.config.system.build.toplevel.drvPath \
  >/dev/null 2>"$log"; then
  cat "$log" >&2
  exit 1
fi

# Newer Nix prints "evaluation warning:", older Nix "trace: warning:".
if grep -E '(evaluation warning|trace: warning):' "$log"; then
  echo "::error::Evaluation warnings (above). Fix them now: they become errors at a later NixOS release."
  exit 1
fi
echo "No evaluation warnings."
