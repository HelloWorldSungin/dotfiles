# Stable tool update review evidence

PR: https://github.com/HelloWorldSungin/dotfiles/pull/25

## Ownership and delivered behavior

This continues `fm/dotfiles-stable-tool-policy` and its existing stable-source
change, originally committed as `505e4e21752f159ea1eb3e4213b93f90c48efe17`.
The absolute Git common directory was verified as
`/home/sungin/.treehouse/firstmate-upstream-7bab20/4/firstmate-upstream/projects/dotfiles/.git`.
The working directory and repository top level both resolve to the assigned
isolated treehouse worktree.

- `config/dev-tools-versions.sh` owns bootstrap pins and source policy.
  The five axi tools use npm stable `latest` discovery; Herdr uses its publisher
  stable manifest. WezTerm remains externally owned with stable-channel guidance.
- `bin/dev-tools-install-pinned` retains install-if-absent behavior, including
  preserving existing Herdr clients. Exact artifact checks remain mandatory.
- `bin/dev-tools-apply-updates` owns convergence, receipts and rollback.
  `--explicit` durably requests work; `--resume` retries unfinished work once.
  Existing Firstmate and npm safeguards remain. Explicit invocation adds
  no-mistakes stable binary replacement with a verified archive and preserved,
  checksummed prior binary. Every new update and its attended rollback require
  fresh authoritative usage checks immediately before mutation.
- `home/dev-tools.nix` remains the single packaging owner. The updater adds curl
  and the pinned Nix util-linux `flock` dependency, recorded in the existing
  closure inventory. No unrelated package versions were updated.

The publisher stable no-mistakes release was verified read-only through
`gh-axi`: v1.72.0, excluding prereleases. Its uploaded platform archives expose
SHA-256 digests. The implementation selects assets from the
[GitHub release API](https://api.github.com/repos/kunchenguid/no-mistakes/releases/latest),
checks stable release flags and exact asset identity, and verifies downloaded
bytes against those digests. It does not guess a download URL or execute a
moving installer script. The bootstrap pin remains unchanged; explicit update
invocation resolves the current stable release.

## Integration and remaining ownership

[integration-contract.md](integration-contract.md) defines command arguments,
usage-reader JSON, output semantics and durable retry ownership.

Firstmate must supply the authoritative usage reader and invoke one-shot resume
when users finish and after restart recovery. Active no-mistakes runs remain
busy after their workers exit. Unknown, absent, malformed, failed and timed-out
usage answers cannot authorize mutation. These are caller responsibilities
made explicit by the interface, not an implemented Firstmate hook in this PR.

The legacy command keeps its existing lane guards. The new hook must use
`--explicit`/`--resume`; those paths and attended rollback of their receipts
serialize through `flock`. All callers for an installation must use the same
stable updater state directory. Unsupported locking platforms refuse.
Busy, failed, unknown and interrupted obligations persist. Exit 0 can therefore
include deferred work; consumers must inspect `obligations.remaining`.

Herdr is never an updater target. Herdr compatibility and activation remain
attended under `docs/herdr.md`. No daemon activation or lifecycle command,
periodic schedule, live package installation, Home Manager switch, user-config
edit, or Firstmate shared-source edit was performed.

## Validation on 2026-09-15

- `bin/dotfiles-test`: all 16 suites passed.
- `tests/dev-tools-explicit-updates.test.sh`: independently rerun after its final
  additional edge cases; passed using only isolated state, fake binaries,
  fake installers, fake users and fake run records.
- `bin/dotfiles-lint`: passed at full ShellCheck severity.
- `nix flake check --print-build-logs`: passed.
- Build-only Home Manager check, matching `.github/workflows/build.yml`:
  `nix build --no-link --print-out-paths --print-build-logs '.#homeConfigurations."sungin@ct110".activationPackage'`
  passed, producing `/nix/store/3rbp5zx7f39xn8m21jdni8cm3jkp49a4-home-manager-generation`.
  The generation was not activated.
- `git diff --cached --check`: passed.

The added behavior coverage includes busy-to-idle convergence, a new user
appearing between initial assessment and mutation, an active run after worker
exit, recovery after a killed updater, concurrent lock refusal, unavailable or
corrupt release data, prerelease rejection, newer installed version preservation,
installed stable no-op, unsupported platform override, unknown/malformed/timed-out
usage, failed npm install and successful retry, corrupt obligations, empty retry,
Firstmate lane preservation, attended rollback, and changed-backup refusal.
Existing suites retain installer/checker stable selection, exact overrides,
receipt and rollback invariants, stripped-PATH packaging and Herdr preservation.

Raw logs remain in the worktree's untracked `.validation/` directory, including
`dotfiles-test.log`, `explicit-final.log`, `lint.log`, `flake-check.log`, and
`activation-build.log`. Earlier validation artifacts were preserved.

This is direct-PR delivery without no-mistakes. The PR remains unmerged for main
verification and required checks; no merge is performed by this worker.
