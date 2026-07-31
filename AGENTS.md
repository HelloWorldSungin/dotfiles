# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- `.github/workflows/build.yml` is authoritative for build-only validation of
  Home Manager changes. Do not activate the resulting generation while testing.
- The personal tool update checker lives in `bin/dev-tools-check-updates`, its
  deterministic self-test is in `tests/`, and `home/sungin-ct110.nix` owns its
  package, timer, and zsh startup wiring.
- `bin/dev-tools-apply-updates` is the guarded, opt-in companion that applies only
  the two safe tiers the checker tracks (firstmate fast-forward + the allowlisted
  npm-global axi tools); it delegates detection to the checker, refuses when any
  Firstmate worker lane is in flight (a `state/*.meta` file, mirroring
  `firstmate/bin/fm-supervision-lib.sh`), and is packaged on PATH with no timer.
  Its `--help` is authoritative; the self-test sits beside the checker's in `tests/`.
- Nix flakes only read git-tracked files: `git add` any new `bin/`/`home/` file
  before `nix build ...activationPackage`, or evaluation fails with "not tracked
  by Git".
- CT110 root networking failover is tracked in `system/ct110-network-failover/`;
  its README documents the Proxmox-owned boundary, guarded apply, and E2E test.
- For one-off or infrequent operational work, start with the simplest direct end-to-end path.
  Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless
  the direct path exposes a concrete blocker or repeated need that justifies the added machinery.
- **Branch Strategy (CRITICAL)**: All build server workarounds, work-environment bugfixes, and Neovim 0.9.5 polyfills MUST ONLY be committed to the `nvim-0.9-compat` branch. Do NOT apply work server workarounds or 0.9.5 compatibility shims to the `master` branch.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
