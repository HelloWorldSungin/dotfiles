# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- `.github/workflows/build.yml` is authoritative for build-only validation of
  Home Manager changes. Do not activate the resulting generation while testing.
- The personal tool update checker lives in `bin/dev-tools-check-updates`, its
  deterministic self-test is in `tests/`, and `home/sungin-ct110.nix` owns its
  package, timer, and zsh startup wiring.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
