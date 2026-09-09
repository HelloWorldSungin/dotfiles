# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- `.github/workflows/build.yml` is authoritative for build-only validation of
  Home Manager changes. Do not activate the resulting generation while testing.
- `bash ~/dotfiles/rebuild.sh` is the apply path for CT110 (it sources nix,
  auto-selects the flake target, and passes `-b backup`). Changes to Nix-evaluated
  inputs require it; the `mkOutOfStoreSymlink` trees in `home/common.nix`
  (`config/`, `agents/`, `skills/`, `pi/`) are live symlinks into `~/dotfiles`,
  so those edits take effect the instant the fast-forward lands. See `docs/nix.md`.
- Ordering traps around applying on CT110, in the order they bite:
  1. `git fetch` + `git merge --ff-only` BEFORE running either script. Running
     first executes the stale pre-merge copy, silently - this has already cost a
     debugging cycle.
  2. A `home-manager switch` never installs or refreshes the agent CLIs
     (`claude`, `codex`, `opencode`, `pi`, ...). `bootstrap.sh` delegates their
     exact install-if-absent path to `bin/dev-tools-install-pinned`, deliberately
     outside Nix (`docs/dev-tool-versions.md` owns the complete inventory).
     `bootstrap.sh` is the superset - it runs the switch itself as step 2/6 - but
     it is install-if-missing, so it never upgrades a CLI that is already present.
  3. A running herdr does not automatically re-read `config/herdr/config.toml`
     even though the file is a live symlink; use `herdr server reload-config`.
     Never restart the captain's herdr to apply a config - it hosts the live fleet.
- `config/dev-tools-versions.sh` owns external tool pins and source metadata.
  The read-only checker lives in `bin/dev-tools-check-updates` and its
  deterministic self-test is in `tests/`. `home/dev-tools.nix` is the single
  owner of every packaged dev-tool derivation (pin artifacts, checker, pinned
  installer, cspend wrapper, guarded updater); `common.nix` and
  `sungin-ct110.nix` consume them through the `devTools` module argument, so
  the host module owns only its timer and zsh startup wiring.
- `bin/dev-tools-apply-updates` is the guarded, opt-in companion that applies only
  the two safe tiers the checker tracks (Firstmate exact fast-forward plus six
  allowlisted npm-global tools); it delegates detection to the checker, independently
  re-verifies exact artifacts, refuses when any
  Firstmate worker lane is in flight (a `state/*.meta` file, mirroring
  `firstmate/bin/fm-supervision-lib.sh`), and is packaged on PATH with no timer.
  Its `--help` is authoritative; the self-test sits beside the checker's in `tests/`.
- `~/.codex/config.toml` is machine-maintained (project trust, hook approvals,
  TUI state) and must never be replaced or symlinked to a repo file. Home Manager
  owns exactly one key in it, `model_context_window`, through the atomic
  idempotent merge in `bin/codex-set-context-window`; `docs/agents.md` records the
  GPT long-context values (Sol, Terra, Astra), why pi (1,050,000) and Codex
  (872,000) differ, and the command that re-verifies Codex's advertised ceilings
  against an upgraded binary.
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
