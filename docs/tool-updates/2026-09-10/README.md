# Stable tool audit, 2026-09-10

This change updates declarative tool pins after publisher re-verification. No
installed tool, Home Manager generation, fleet-hosting Herdr server, or shared
no-mistakes daemon was mutated. The starting 68-row report has SHA-256
`249857643d8c700a054a117982f0dd4e1277fadd44ff5e00f999cbc094d7992f`.

[Publisher provenance](publisher-provenance.json) records the authoritative
registry endpoints, refs, versions, and integrity values needed to reproduce the
accepted pins. [Inventory disposition](inventory.md) accounts for all 68 rows.
The public evidence is deliberately limited to this summary, exact publisher
provenance, and value-free parsed-contract shape projections.

## Reviewed results

| Owner | Accepted result | Publisher authority |
|---|---|---|
| Codex | 0.154.0 with exact npm integrity | npm `latest` and matching GitHub GA release |
| Nix installer action | v23 at `3138316df39ed29be04236d7ffc686fa525866aa` | GitHub GA tag |
| Nixpkgs 26.05 | `d58a46e3bc02d91ebe04667f8397752a749c0024` | `nixos-26.05`; 58 commits beyond and containing the reviewed `6aefcda9401be8acc2b74244fb3b37520ea1f0a8` |
| Antigravity | 1.2.0 with four exact SHA-512 assets | Google production manifests |
| nvim-treesitter | `d4d59cb369da46b95699bd2200efbcffc6dadb3b` | upstream default branch |

The Nixpkgs advance leaves all 28 managed package versions unchanged. Home
Manager 26.05 and the other thirteen Neovim plugin pins remain current. Cursor
still advertises build `2026.09.08-6caf4ff`; its moving installer hashes to
`8513e9f949576d7ced2a2a582252626cc86235437c2749bf93c886f1d5fdb203`.

Claude's publisher tags were `stable: 2.1.236`, `latest: 2.1.267`, and
`next: 2.1.267`. Exact fresh installs stay on the approved stable channel. The
existing 2.1.267 runtime was not downgraded and remains an attended transition.

GBrain is excluded from every repository and live change. Its observed runtime
remains 0.46.21.0, while its inherited report-only reference remains untouched.
Firstmate stays pinned at `0fe226c93efdd12a38f1c3936d758571e40111b7`
until the existing upstream-sync lifecycle reconciles the fork. PR 17's
no-mistakes 1.72.0 pin, checksums, and repository configuration are unchanged.

## Parsed contracts

[Before](contract-shapes-before.json) and [after](contract-shapes-after.json)
contain only JSON paths and observed value types. Their
[unified diff](contract-shapes.diff) records every shape change for the parsed
interfaces named in the source report's section 8.

| Contract | Result |
|---|---|
| `no-mistakes axi status`, current branch, explicit run, and detached checkout | Parsed table and attribution shapes remain compatible. |
| Herdr status, session list, stop, and delete | Consumed types remain compatible; Herdr 0.9.0 adds endpoint-generation status fields. Stop and delete remained successful in both isolated labs. |
| `quota-axi --json` | Schema 5 and all consumed window and pace types remain compatible; Alibaba and OpenCode Go are additive providers. |
| `tasks-axi list` | Parsed task-list shape is unchanged. |
| `gh-axi release list` | Parsed release-table shape is unchanged. |
| `dev-tools-check-updates --json` | Schema 4 and all 68 tool rows retain their parsed shape. The held Firstmate source is the only outdated pin. |

The quota projections contain no percentages, pace values, reserves, burn
multiples, reset times, authentication state, or provider usage. The other
projections likewise omit run identifiers, branches, paths, sockets, and live
state values. They establish field compatibility without publishing operator
telemetry.

## Codex catalog prerequisite

The installed Codex 0.153.4 binary and the exact npm-integrity-verified 0.154.0
Linux artifact both advertised `max_context_window: 872000` for Sol, Terra,
Luna, and Astra. Their binary SHA-256 values were respectively
`56ef98ab4032d317ab26e9b5e5a175650717351edb16ed9cde0cb6d1734d62da`
and `3188814c35471432d4123203e0eb38e5bddc60226e3d7ddf0e59e649ea140022`.
The provenance `codex_catalog.max_context_window` records all eleven ceilings
the 0.154.0 catalog advertised; `docs/agents.md` explains how Codex applies them.
The live Codex remains 0.153.4. Re-run the installed catalog command documented
in `docs/agents.md` after later attended convergence. That recheck is not a
prerequisite to the Pi `openai-codex` 872,000 source override.

## Validation and live handoff

All twelve `bin/dotfiles-test` suites, `bin/dotfiles-lint`,
`nix flake check --print-build-logs`, the build-only Home Manager
activation-package command, and the treesitter parse/highlight smoke check
passed. No generation was activated. The checker fixture now derives a future
minor release from each manifest pin, retaining the regression where 0.10.0 is
lexicographically lower than 0.9.0.

The guarded apply preview deferred Firstmate and all six npm tools because
workers were active. No apply or rollback receipt was written. Remaining live
work keeps these prerequisites:

- Firstmate must confirm every worker and validation run is quiet and explicitly
  hand off the Herdr interruption. Upgrade the server from an external terminal
  that survives the outage, then verify server and client at 0.9.0/protocol 22.
- Treehouse requires a drained pool. The guarded npm tools require no worker
  lanes, and their owned apply must preserve its mode-0600 receipts.
- Codex, OpenCode, Antigravity, Claude, and other report-only tools require their
  owned attended paths. Bootstrap remains install-if-absent.
- After landing, CT110 must fetch and fast-forward before running
  `bash ~/dotfiles/rebuild.sh`. The generation must not be activated during
  build-only validation.
