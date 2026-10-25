"""Bump the config version for a flake.lock update (used by `update-system`
on the laptop and by the manual Update flake.lock workflow).

Usage: bump-version.py <update.log>

Increments `version` in flake.nix (the number after the dot: 0.1 -> 0.2,
0.9 -> 0.10), updates README.md's "Current version" line, and adds a
Versions table row naming the updated inputs. Prints the new version.
"""

import re
import sys
from pathlib import Path

flake = Path("flake.nix")
readme = Path("README.md")

text = flake.read_text()
major, minor = map(int, re.search(r'version = "(\d+)\.(\d+)";', text).groups())
cur = f"{major}.{minor}"
new = f"{major}.{minor + 1}"
flake.write_text(text.replace(f'version = "{cur}";', f'version = "{new}";', 1))

inputs = sorted(set(re.findall(r"Updated input '([^']+)'", Path(sys.argv[1]).read_text())))
row = f"| **{new}** | `flake.lock` update: {', '.join(inputs) or 'inputs'}. |"

lines = readme.read_text().splitlines(keepends=True)
out = []
for line in lines:
    if line.startswith(f"**Current version: {cur}**"):
        line = line.replace(f"`{cur}`", f"`{new}`").replace(f"**Current version: {cur}**", f"**Current version: {new}**")
    elif line.startswith(f"| **{cur}** |"):
        out.append(row + "\n")
        line = line.replace(f"| **{cur}** |", f"| {cur} |", 1)
    out.append(line)
readme.write_text("".join(out))
print(new)
