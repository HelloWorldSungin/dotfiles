# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- `.github/workflows/build.yml` is authoritative for build-only validation of
  Home Manager changes. Do not activate the resulting generation while testing.
- `bin/dotfiles-test` (every `tests/*.test.sh`, per-suite bound and attribution)
  and `bin/dotfiles-lint` (ShellCheck `-x` at full severity over every tracked
  shell file) are this repository's canonical validation entry points, and
  `.no-mistakes.yaml` points the pipeline's Test and Lint steps at them. Both put
  Nix on PATH the way `bootstrap.sh` does: a service environment inherits neither
  `~/.nix-profile/bin` nor the Nix daemon profile, and three suites need `nix` and
  `chromium` from there. Neither adds `~/.local/bin`, where `shellcheck` and
  `no-mistakes` live: a missing one hard-fails by design, never a skip and never
  a PATH workaround. `system/ct110-network-failover/e2e-failover-test.sh` is
  deliberately outside `bin/dotfiles-test`; its README owns that attended run.
- `.no-mistakes.yaml` traps, both load-bearing:
  1. no-mistakes reads `commands` from the DEFAULT-BRANCH copy
     of that file, so an edit there is validated by the previous configuration and
     only governs runs started after it lands. `allow_repo_commands`, which would
     honor a pushed branch's commands instead, is deliberately off.
     `tests/no-mistakes-config.test.sh` drives the real parser; its key-set
     assertion is what catches a typo, because the parser ignores unknown keys
     silently. `review_agents` is one such key here: it is global-only, so a
     repository copy is accepted and then ignored. The captain decision
     `nm-global-reviewer-fixer-profiles` owns that capability. A top-level
     `agent` IS read from this file, but as one ordered list for every role.
  2. Never run `no-mistakes ci-workflow` in this checkout. It emits a Go-shaped
     `.github/workflows/ci.yml`; `build.yml` above is this repository's CI.
     `tests/no-mistakes-config.test.sh` drives it only in throwaway repositories,
     which is how the parser can be the oracle without writing here.
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
  installer, cspend wrapper, codex context-window helper, guarded updater) and
  of the one closure-input attrset they select from, which also generates the
  store-path manifest the checker measures closure-only packages with;
  `common.nix` and `sungin-ct110.nix` consume them through the `devTools` module
  argument, so the host module owns only its timer and zsh startup wiring.
- `bin/dev-tools-apply-updates` is the guarded, opt-in companion that applies only
  the two safe tiers the checker tracks (Firstmate exact fast-forward plus six
  allowlisted npm-global tools); it delegates detection to the checker, independently
  re-verifies exact artifacts, refuses when any
  Firstmate worker lane is in flight (a `state/*.meta` file, mirroring
  `firstmate/bin/fm-supervision-lib.sh`), and is packaged on PATH with no timer.
  `--dry-run` verifies the Firstmate tier against the real remote in a private
  throwaway repository - never the checkout - so a preview matches the apply.
  Every real mutation is preceded by a mode-0600 receipt under
  `$DEV_TOOLS_APPLY_RECEIPT_DIR`; reversal is `--rollback <receipt> --attended`,
  is never automatic, and reconciles each tool's observed state against the
  receipt - settling it in place - before touching anything, so an
  unreconcilable state refuses that whole tier. Its `--help` is authoritative;
  the self-tests sit beside the checker's in `tests/`.
- `~/.codex/config.toml` is machine-maintained (project trust, hook approvals,
  TUI state) and must never be replaced or symlinked to a repo file. Home Manager
  owns exactly one key in it, `model_context_window`, through the atomic
  idempotent merge in `bin/codex-set-context-window`; `docs/agents.md` records the
  GPT long-context values (Sol, Terra, Astra) for both pi and Codex, and the
  command that re-verifies Codex's advertised ceilings against an upgraded
  binary.
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
