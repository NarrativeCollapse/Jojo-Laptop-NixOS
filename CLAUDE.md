# Working on this repo

NixOS 26.05 flake + Home Manager config for the host `jojo`, an Acer
laptop (i7-13620H, Intel UHD + NVIDIA RTX 4060 Laptop GPU as PRIME
offload). See README.md for layout and usage. It started as a copy of
NarrativeCollapse/NixOS-Desktop-KDE-Intel (the host `shitbox`, an
Intel-only HP laptop); the hardware differences are `modules/nvidia.nix`,
Steam's offload environment in `modules/gaming.nix`, and the host files.
Fixes made in one repository don't reach the other on their own.

## Before every commit

Run `nix fmt` and `nix flake check`; both must pass with no evaluation
warnings. `nix flake check` includes the VM boot test (`tests/boot.nix`,
needs KVM, a few minutes). CI (`.github/workflows/check.yml`) runs the same
check, `scripts/check-eval-warnings.sh` and a full system build on every
push; `next-release.yml` runs them weekly against the next NixOS release
(see "Release upgrade" in README.md; `scripts/next-release.sh` picks the
branches). Changes must evaluate on both releases until the upgrade. A
failing Check on main or Next release run opens a GitHub issue titled
"<workflow> is failing", which closes itself once the workflow passes.

## Versioning (keep this up to date)

The config has a version number (`0.N`: 0.1, 0.2, … 0.10), defined once as
`version` in flake.nix. It becomes a system label tag, and must match the
"**Current version: 0.N**" line at the top of README.md (`nix flake check`
enforces this). Each version also gets a git tag of the same name. Moving
to 1.0 is the owner's call, not a bump.

- Bump the version (the number after the dot, by one) in the same push as any change that affects the
  built system: packages, services, Home Manager config, the Brewfile,
  flake inputs. (`update-system` on the laptop, and the manual Update
  flake.lock workflow, bump it themselves via
  `scripts/bump-version.py`; `update-system` also tags and pushes.)
- Don't bump for docs, comments, CI, or lint config alone.
- `home/austin/nvim/` (the LazyVim config and its `lazy-lock.json`) is read
  from the checkout at run time, not built into the system: changes there
  alone don't bump the version either. (`home/austin/neovim.nix` does.)
- For a bump: change `version` in flake.nix, update "Current version" at the
  top of README.md, add a row at the top of its Versions table (one or two
  sentences of highlights), and after pushing, tag the pushed commit with
  the version (e.g. `0.2`) and push the tag.
- Several commits in one push share one version.
