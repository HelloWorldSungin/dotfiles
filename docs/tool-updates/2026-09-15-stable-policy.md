# Stable tool policy validation - 2026-09-15

## Scope and ownership

- Five axi npm packages: `config/dev-tools-versions.sh`, fresh installer,
  read-only checker and guarded updater. Resolve publisher `latest`, reject
  prereleases, then bind exact version/integrity. gnhf and unrelated pins remain.
- Herdr: publisher stable manifest selects the platform URL and SHA-256.
  Bootstrap skips existing clients; guarded updates exclude Herdr entirely.
  The protocol and activation boundary in `docs/herdr.md` remains authoritative.
- WezTerm: no repository package/version owner or lock exists. The Mac module
  owns configuration and PATH only. The documented external policy selects the
  publisher-supported stable `wezterm` cask, with Homebrew owning verification.

Publisher sources inspected: [Herdr manifest](https://herdr.dev/latest.json),
[WezTerm macOS instructions](https://wezterm.org/install/macos.html),
[npm view](https://docs.npmjs.com/cli/v11/commands/npm-view/).

## Passed checks

| Command | Evidence |
| --- | --- |
| `bash tests/dev-tools-install-pinned.test.sh` | Stable resolution, newer Herdr release, exact overrides, dry-run, installed-command skip, prerelease/network/metadata/integrity failures, SHA tools on macOS; 0.8.2 client remains byte-for-byte unchanged |
| `bash tests/dev-tools-check-updates.test.sh` | Stable versus installed state, newer and withdrawn manifest releases, discovery failure, cache and packaged metadata behavior |
| `bash tests/dev-tools-apply-updates.test.sh` | Stable exact target and receipt, changed discovery/integrity refusal, active-lane deferral, idempotence, no downgrade, exact overrides and service exclusion |
| `bash tests/dev-tools-apply-dry-run.test.sh` | Private remote verification and no checkout mutation |
| `bash tests/dev-tools-apply-rollback.test.sh` | Prior-artifact evidence, receipt failure, reconciliation, attended reversal and refusal paths |
| `bash tests/dev-tools-nix-packaging.test.sh` | Shared derivations and packaged updater under stripped PATH with mocked registry/install commands; build only |
| `bin/dotfiles-lint` | Full repository ShellCheck, no findings |
| `git diff --check` | No whitespace errors |

All installer and update operations used isolated mocks. Temporary files were
kept under the disposable worktree's `.validation` directory using `TMPDIR`.
The packaging test used `TAR_OPTIONS=--exclude=./.validation` to exclude that
scratch directory from its repository copy. Nix was sourced using the canonical
runner's daemon-profile idiom. No package was installed into a live user prefix,
Home Manager generation activated, live configuration edited, Herdr lifecycle
driven, or no-mistakes pipeline run. Live activation remains deferred until after
dotfiles work and separate attended compatibility verification.
