"""Bump the config version for a flake.lock update (used by `update-system`
on the laptop and by the manual Update flake.lock workflow).

Usage: bump-version.py <update.log>

Increments `version` in flake.nix, updates README.md's "Current version"
line, and adds a Versions table row naming the updated inputs. Prints the
new version.
"""

import re
import sys
from pathlib import Path

flake = Path("flake.nix")
readme = Path("README.md")

text = flake.read_text()
cur = int(re.search(r'version = "v(\d+)";', text).group(1))
new = cur + 1
flake.write_text(text.replace(f'version = "v{cur}";', f'version = "v{new}";', 1))

inputs = sorted(set(re.findall(r"Updated input '([^']+)'", Path(sys.argv[1]).read_text())))
row = f"| **v{new}** | `flake.lock` update: {', '.join(inputs) or 'inputs'}. |"

lines = readme.read_text().splitlines(keepends=True)
out = []
for line in lines:
    if line.startswith(f"**Current version: v{cur}**"):
        line = line.replace(f"v{cur}", f"v{new}")
    elif line.startswith(f"| **v{cur}** |"):
        out.append(row + "\n")
        line = line.replace(f"| **v{cur}** |", f"| v{cur} |", 1)
    out.append(line)
readme.write_text("".join(out))
print(f"v{new}")
