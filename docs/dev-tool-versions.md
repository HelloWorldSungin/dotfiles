# Developer and agent tool version ownership

`config/dev-tools-versions.sh` is the machine-readable owner for external tool
pins. `flake.lock` owns the immutable Nix input revisions, and
`config/nvim/lazy-lock.json` owns Neovim plugin commits. The pins below were
verified on 2026-09-09 against each publisher's registry, release feed, or
manifest. A version is stable only when the publisher's stable/default registry
tag or a non-draft, non-prerelease release says so. Numeric tags containing
alpha, beta, preview, nightly, snapshot, or another suffix are excluded.

## Exact external pins

| Tool | Exact pin | Authority and stable judgment | Fresh install | Apply boundary |
|---|---:|---|---|---|
| Determinate Nix Installer | 3.22.3 | Determinate GitHub GA release, with v3.22.0 prerelease excluded | Versioned installer URL plus recorded installer SHA-256 | Report only |
| Claude Code | 2.1.236 | Official npm `stable` dist-tag. The moving `latest` 2.1.266 is deliberately not the stable channel | Exact npm package and registry integrity | Report only |
| Codex | 0.153.4 | Official npm default tag; 0.154.0 alpha builds excluded | Exact npm package and registry integrity | Report only |
| OpenCode 1 | 1.18.30 | Official npm default tag and matching GA release; OpenCode 2 beta and snapshots excluded | Exact npm package and registry integrity | Report only |
| Pi | 0.85.1 | `@earendil-works/pi-coding-agent` default tag. The retired Mario Zechner package is not the fleet distribution | Exact npm package and registry integrity | Report only |
| Antigravity CLI | 1.1.28 | Google's per-platform production manifest | Exact publisher asset and SHA-512 from that manifest | Report only; its own self-update remains an upstream limitation |
| Cursor Agent | 2026.09.08-6caf4ff | Version embedded in Cursor's official moving installer | No automated install; observed snapshot only | Report only |
| Treehouse | 2.3.0 | Latest non-draft, non-prerelease GitHub release | Exact release archive and publisher checksum | Report only |
| no-mistakes | 1.70.1 | Latest GitHub GA release; 1.71.0 and 1.72.0 prereleases excluded | Exact release archive and publisher checksum | Attended only |
| Herdr | 0.9.0 | `herdr.dev/latest.json`; newer preview builds excluded | Exact manifest asset and publisher checksum, only when absent | Attended only |
| GBrain | 0.48.5.0 | Latest non-draft, non-prerelease `garrytan/gbrain` release | Not installed here | Firstmate-owned attended migration |
| gnhf | 0.1.49 | npm default tag | Exact npm package and registry integrity | Guarded exact apply |
| gh-axi | 0.1.35 | npm default tag | Exact npm package and registry integrity | Guarded exact apply |
| tasks-axi | 0.2.5 | npm default tag | Exact npm package and registry integrity | Guarded exact apply |
| quota-axi | 0.1.41 | npm default tag | Exact npm package and registry integrity | Guarded exact apply |
| chrome-devtools-axi | 0.1.34 | npm default tag | Exact npm package and registry integrity | Guarded exact apply |
| lavish-axi | 0.1.67 | npm default tag | Exact npm package and registry integrity | Guarded exact apply |
| OpenCode ACP invocation | 1.18.30 | npm default tag | Exact `npx` spec in `config/baby-menu/agents.json` | Report only |
| OMP ACP invocation | 0.1.2 | npm default tag | Exact `npx` spec in `config/baby-menu/agents.json` | Report only |
| claude-spend invocation | 1.0.6 | npm default tag | `CLAUDE_SPEND_VERSION` in `config/dev-tools-versions.sh`, read at run time by `bin/claude-spend-pinned` (the `cspend` alias) | Report only |
| Firstmate source | `0fe226c93efd...` | No upstream releases exist, so the audited default-branch commit is the explicit exception | Exact commit | Guarded exact fast-forward only |
| Baby Menu source | 0.1.24 / `65eb280ea0e0...` | Latest non-prerelease `baby-menu-v0.1.24` release | Exact release commit | Report only |
| actions/checkout | v7.0.1 / `3d3c42e5aac5...` | Latest GitHub GA action release | Exact workflow action SHA | CI only |
| Determinate Nix Installer action | v22 / `ef8a148080ab...` | Latest GitHub GA action release | Exact workflow action SHA | CI only |

The authoritative feeds used for the audit are the
[npm registry](https://registry.npmjs.org/) for npm packages,
[GitHub Releases](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
for GitHub-distributed binaries and plugins,
[Herdr's stable manifest](https://herdr.dev/latest.json), Google's
platform-specific Antigravity production manifests, the
[Cursor installer](https://cursor.com/install), and the stable NixOS and Home
Manager release branches. Exact repository and package identifiers live beside
the values in `config/dev-tools-versions.sh`, so the checker does not infer an
owner from an executable name.

The Cursor CLI is already an intentional beta dependency in this repository.
Cursor documents only a moving installer and auto-update commands, with no
supported exact-version selector or publisher checksum. The repository does not
pretend otherwise. Bootstrap records the observed build and installer SHA-256,
but never runs the installer because the script can fetch a different moving
binary after its own bytes were recorded. `dev-tools-check-updates` exposes the
installed, observed, and currently advertised builds separately, and flags any
change to the audited installer snapshot.

Antigravity publishes exact, checksummed assets, so bootstrap can reproduce the
initial install. Its binary also self-updates during ordinary use and exposes no
documented disable switch. The checker therefore makes post-install drift
visible instead of claiming the pin controls the running binary forever.

## Nix-owned inventory

The stable package authority is Nixpkgs 26.05 at
`93108a538f079596c9a16c72cf03e9322782b6dd`. Home Manager is the matching
26.05 input at `fd0956c99c41ae3c13a73a638f1f7e963aebc4ab`. This supersedes the
deprecated 25.11 channel. The lock file carries the content hashes.

| Package | Version | Package | Version |
|---|---:|---|---:|
| gh | 2.100.0 | lazygit | 0.61.1 |
| nodejs_22 | 22.23.2 | uv | 0.11.21 |
| bats | 1.12.0 | ripgrep | 15.1.0 |
| fd | 10.4.2 | fzf | 0.72.0 |
| jq | 1.8.2 | tree | 2.3.2 |
| htop | 3.5.1 | unzip | 6.0 |
| neovim | 0.12.4 | zsh | 5.9.1 |
| starship | 1.25.1 | tea | 0.14.0 |
| chromium | 152.0.7977.82 | ghdl | 6.0.0 |
| gtkwave | 3.3.127 | coreutils | 9.11 |
| curl | 8.21.0 | gawk | 5.4.1 |
| git | 2.54.0 | gnugrep | 3.12 |
| gnused | 4.10 | diffutils | 3.12 |
| gnutar | 1.35 | gzip | 1.14 |

The table includes user-facing packages and runtime inputs of the
repository-owned tool scripts. Every row carries an evidence class that says
where its installed version may be read from, and `home/dev-tools.nix` owns the
matching split. The class is a closed set: a row that carries neither `user-env`
nor `closure` authorises no measurement source at all and reports `unknown`,
rather than quietly reading whatever the ambient PATH offers.

`user-env` rows are in the user environment, so the command the operator runs is
the pinned one and is measured through PATH. `closure` rows - coreutils, curl,
gawk, gnugrep, gnused, diffutils, gnutar, gzip - reach the operator only through
a wrapper's own PATH; `command -v` would report an unrelated system build, or
none at all, and label the pinned closure as drifted. Those are measured from the
exact store path in the manifest `home/dev-tools.nix` generates from the same
closure-only attrset the wrappers select from, and they never fall back to PATH:
a manifest that is absent, unreadable, malformed, does not bind the package, or
binds a path without a runnable version command reports `unknown` and says which
of those it was. So a repository-checkout run - the script rather than the
packaged wrapper - reports every `closure` row as `unknown` instead of measuring
the wrong binary. `git`, `jq`, and `nodejs_22` are wrapper inputs too, but they
are also in the user environment, so they stay `user-env`: an operator whose
`node` resolves to another build still sees that drift. Home Manager modules also own home-manager,
Neovim, zsh, Starship, fzf, and Git. Neovim's fourteen plugin commits remain
independently exact in `config/nvim/lazy-lock.json`; the initial lazy.nvim clone
uses the exact v11.17.5 GA tag instead of the moving `stable` alias, and the lock
then enforces its audited commit.

## Neovim plugin pins

Plugins with a GitHub release feed use the latest non-draft, non-prerelease
release. Projects without releases are pinned to the audited default-branch
commit and are marked as an explicit limitation rather than described as a
release. The checker compares the installed checkout, lock-file commit, and
current authoritative release or branch commit.

| Plugin | Stable source | Exact commit |
|---|---|---|
| codewindow.nvim | No releases; default branch at audit time | `a8e175043ce3baaa89e0a6b5171bcd920aab3dad` |
| diffview.nvim | No releases; default branch at audit time | `4516612fe98ff56ae0415a259ff6361a89419b0a` |
| gitsigns.nvim | v2.1.0 GA | `a462f416e2ce4744531c6256252dee99a7d34a83` |
| lazy.nvim | v11.17.5 GA | `85c7ff3711b730b4030d03144f6db6375044ae82` |
| neogit | v2.0.0 GA | `43fa47fb61773b0d90a78ebc2521ea8faaeebd86` |
| nvim-treesitter | No releases; default branch at audit time | `5cb0114e6242625db56dd6440e945ed1ece10bc7` |
| nvim-autopairs | 0.10.0 GA tag | `23320e75953ac82e559c610bec5a90d9c6dfa743` |
| oil.nvim | v2.16.0 GA | `17c0a8faaf48298a0c0cfb0d757c0eaee4ff7a32` |
| plenary.nvim | No releases; default branch at audit time | `74b06c6c75e4eeb3108ec01852001636d85a932b` |
| render-markdown.nvim | v8.13.0 GA | `f422cb5c6855f150e2ddcfaf44e7157b98b34f6a` |
| rose-pine | v3.0.2 GA | `f01eac6eedf6197509dde8b66de0263207ee1877` |
| snacks.nvim | v2.31.0 GA | `e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f` |
| vim-visual-multi | No releases; default branch at audit time | `a6975e7c1ee157615bbc80fc25e4392f71c344d4` |
| which-key.nvim | v3.17.0 GA | `fcbf4eea17cb299c02557d576f0d568878e354a4` |

## Intentionally not managed here

- GBrain installation and upgrades belong to Firstmate because they require its
  backup, schema migration, retrieval evaluation, and rollback gate. This repo
  reports GBrain drift but never changes its runtime.
- WezTerm is the documented Mac terminal, while optional `pngpaste` is a
  Homebrew helper. Neither Homebrew installation is owned by this repository.
- The Mac NVM path for Node 20.20.2 and the Bun, Antigravity IDE, and Mavis
  paths are compatibility entries for separately managed installations.
- Oh My Pi (`omp`) completion wiring, `claude-monitor`, and
  `codebase-memory-mcp` aliases target separately installed optional tools.
- `wakeonlan`, `pbcopy`, `scp`, `sqlite3`, `xclip`, `xsel`, and `wl-copy` are
  operating-system or optional integration helpers. PowerShell, macOS
  `security`, and the documented MobaXterm terminal are host-owned. The Windows
  Nerd Font script registers operator-supplied files; it does not select or
  download a font release.
- The Baby Menu extension contract mentions a separately managed `pnpm`
  developer command, and its quota integration probes an optional separately
  installed Grok CLI. Neither is a repository-owned install.
- Credentials, logins, project trust, hook approvals, TUI preferences, and the
  machine-owned Codex config remain mutable state. Home Manager merges only the
  Codex context-window key and does not replace that file.

## Check, install, and apply boundaries

`home/dev-tools.nix` is the single owner of the Nix packaging for these tools.
It builds the pin, flake-lock, and plugin-lock artifacts and the checker,
pinned installer, `cspend` wrapper, and guarded updater derivations, each with
its complete runtime closure declared. The interactive checker, the weekly
timer, the login-shell startup check, and the updater's checker dependency are
therefore one derivation rather than four copies that happen to agree.

The login shell runs `dev-tools-check-updates --startup`, which only reads the
cache the weekly timer refreshes; it never checks a source itself. It reports
tool state only from a cache inside the same freshness window every other cached
read uses, and otherwise says the cached audit is stale instead of replaying it
as current.

`dev-tools-check-updates --json --force --no-cache` is the read-only audit. It
reports every executable and plugin as installed, pinned, and latest stable,
reports Nix input and package pins, and names intentionally unmanaged tools.
Source failures are `unknown`, never silently current. Cursor instead exposes
`latest_stable: unavailable` plus `latest_observed`, because upstream provides
no stable exact-version channel.

`dev-tools-install-pinned` is fresh-machine, install-if-absent behavior. It
refuses unknown tool names, unsafe versions, registry-integrity drift, publisher
checksum drift, and an existing non-repository clone target. It does not upgrade
an existing tool. It also refuses an explicit Cursor install because no exact
upstream channel exists; a full bootstrap reports and skips that limitation.
Bootstrap invokes it after the exact Nix and Home Manager bootstrap.

`dev-tools-apply-updates` has only two mutation scopes:

1. Fast-forward Firstmate's `main` branch to the exact recorded commit, after
   proving the commit belongs to the freshly read remote branch.
2. Install the six named npm tools at the exact versions in the pin record,
   after independently re-reading each exact version and integrity from npm.

Both scopes refuse while any Firstmate worker lane exists and recheck that guard
immediately before mutation; a lane found by that recheck is reported in the
result's `worker_guard`, not only in the tier it deferred. Herdr, no-mistakes,
GBrain, Nix, agent harnesses, and Baby Menu are never apply targets.

Dry-run installs and merges nothing, and writes nothing to the Firstmate
checkout - no ref, object, index, `FETCH_HEAD`, or configuration - and does not
create the receipt directory. It does check, without creating anything, that the
receipt location could be written, and refuses exactly what the apply would
refuse if it could not; `receipt.status` then reads `unusable` rather than
`planned`. So a preview that exits 0 is one the apply can act on. It does answer
the Firstmate tier from the same authoritative remote the real run uses, because
a preview computed from whatever is already fetched locally would report
`skipped` in exactly the pending-update case where the real run applies. The
observed local default branch and the remote default branch are read into two
temporary refs in a private throwaway bare repository, with the same URL and ref
selection the apply path uses.

Both directions then run one shared comparison, so a preview's status and exit
code are the apply's: `up_to_date` only on equality, `would_apply` only on a
proven local ancestor of the pin, and a refusal - non-zero, never a quiet
`skipped` - when the pin is absent from or not contained in the authoritative
branch, or when the checkout is ahead of or diverged from it. The apply path
repeats its own fresh `ls-remote`, fetch, and remote-movement check before
running that comparison against the real checkout, and never trusts a dry-run
result. Anything the preview cannot prove - an unreachable remote, a remote that
moves mid-check, a missing object, temporary state that cannot be created or
removed - is reported as `unknown` and also exits non-zero.

Every real mutation is preceded by a mode-0600 receipt written atomically under
`$DEV_TOOLS_APPLY_RECEIPT_DIR` (by default `$XDG_STATE_HOME/dev-tools-apply-updates`).
It records each affected tool, its exact prior commit or version, its exact
target, the independently verified remote or registry evidence for both, and
per-tool and per-tier completion status. A receipt directory the run has to
create - the default location, or a `DEV_TOOLS_APPLY_RECEIPT_DIR` that does not
exist yet - is created and secured privately; an existing operator-supplied one
keeps its own mode, and one that cannot be created or written refuses the
mutation instead of being repaired in place. A receipt that cannot be written
refuses the mutation it would have covered, so nothing is ever changed without a
record, and a receipt that could not record every outcome is reported as
`receipt.status: incomplete` in both output modes and exits non-zero even when
the tools themselves converged. Dry-run names the receipt it would write and
writes nothing.

An npm tool's reversal path is proven before anything is decided, by the preview
and the apply alike. The prior version is read from the same npm prefix a
reversal reinstalls into, not from the checker's PATH lookup, and it must be
re-verifiable against the registry; without that evidence the receipt could not
describe a reversal, and a recorded mutation with no way back is worse than a
refused one. A package the prefix does not carry, or one whose prefix version
disagrees with what detection read from PATH, is refused for the same reason: the
receipt would name a prior state reinstalling could not restore. The other
allowlisted packages are unaffected and stay reversible.

A version that is absent from the registry - a locally built global install, or
one whose version was unpublished - would otherwise refuse forever. The single
recovery inside this updater is to supply that artifact yourself: put the exact
tarball at `$DEV_TOOLS_APPLY_PRIOR_ARTIFACT_DIR/<package>-<version>.tgz`
(`npm pack` names it that way). Its own `package/package.json` must name that
package at that version - the filename alone is never trusted, because
`npm install -g <tarball>` takes its target from the contents - and its checksum
then becomes the recorded prior evidence, pinning the bytes whose identity was
verified. A reversal reinstalls that file after re-verifying the checksum,
refusing if it has moved or changed. The installed version must also have a
shape a reversal could restore (`X.Y.Z`, optionally with a fourth component); a
prerelease or two-component version is refused rather than recorded as
reversible, because the rollback preflight could never accept it back. There is deliberately no flag that records
a mutation without evidence: an override would trade a refusal you can act on
for a receipt that cannot reverse anything. If you would rather not keep the
artifact, install a published version of that tool by hand first - that step is
outside this tool's receipt contract, and the next run then converges normally.

Partial apply is expected and recorded rather than hidden. Each tool carries its
own completion status, so a run that converges one package and fails or refuses
another leaves an accurate per-tool record while the tier reports the worst
case. After an apply or a partial failure the command prints the receipt path
and the exact rollback preconditions.

## Rollback

Rollback is attended, never automatic, and never restarts a service:

```sh
dev-tools-apply-updates --rollback <receipt>              # check preconditions only
dev-tools-apply-updates --rollback <receipt> --attended   # perform the reversal
```

Without `--attended` nothing is written at all - not a tool, and not one byte of
the receipt. The full preflight below still runs and reports the reconciliation
an attended run would record, so an archived or read-only receipt can be
inspected without altering it or failing on an append that was never requested.

The recorded status is never trusted on its own. Every status that can follow a
real mutation - `applied`, `pending`, `failed`, and `rollback_failed` - is
observed and reconciled; only a terminal `reconciled_at_prior` or `rolled_back`
entry is left alone. `failed` matters in particular because a post-install
version probe can disagree after `npm install -g` has already replaced the
global binary, and `rollback_failed` is what makes retrying a reversal work
after its cause is fixed.

One preflight does all of it before anything is touched:

- observed state equal to the recorded prior: the mutation did not take effect
  or has already been reversed. Nothing is mutated and the entry is settled as
  `reconciled_at_prior`, which is also what makes an interrupted rollback safe
  to rerun.
- observed state equal to the recorded target: the mutation took effect and the
  entry is eligible for reversal.
- anything else - a third version, a moved commit, an absent or unreadable tool
  - is unreconcilable, rather than drift to overwrite.

The same preflight then proves each eligible tier is actually reversible: no
in-flight Firstmate worker lane (npm reversal is the same live-tool mutation
class as the apply direction and takes the same guard), a checkout on `main`
that is clean with the recorded prior commit verified as an ancestor of the
applied commit, and every eligible npm prior artifact re-verified against its
recorded evidence - registry identity and integrity, or the checksum of the
operator-supplied artifact. A single unreconcilable or
unverifiable entry refuses its whole tier, so no tool in that tier is changed
and the tier never ends up half reverted.

Reversal is then `git reset --hard <prior commit>` - never a force, and never a
discard of local changes - and an npm reinstall of only the exact prior version
the receipt records. Each re-confirms observed state, the worker lane, and the
prior artifact evidence immediately before mutating.

An attended reversal that changes nothing - every tool refused, or nothing left
to reverse - reports `receipt.status: unchanged`, exactly like the check-only
form, because not one byte of the receipt was written. One that does settle
appends the observed state and the outcome to the receipt,
in place and mode 0600, and re-derives each tier's completion status from its own
tool entries so no apply-era tier status outlives the tools it described; a
partly reversed tier reports the worst outcome among them. The receipt's parent
directory is the operator's and its mode is never changed. The recorded prior, target, and evidence fields are never
rewritten to match the machine. A reversal whose append fails is reported as
`receipt.status: stale` and exits non-zero even though the machine state was
restored, so stale evidence is never mistaken for completion. Herdr, the shared
no-mistakes daemon, GBrain, and every other runtime-hosting tool remain outside
both directions.

## Attended runtime upgrade sequence

1. Land and fast-forward the pin change before running any repository script.
2. Wait until all Firstmate worker lanes and no-mistakes validation runs are
   clear. Record the checker output and take any tool-specific backup first.
3. Preview the two safe scopes with `dev-tools-apply-updates --dry-run`, then run
   the guarded apply if its independently verified exact versions are correct.
   Keep the receipt path it prints; reversing either tier is attended and starts
   from `dev-tools-apply-updates --rollback <receipt>`.
4. Upgrade no-mistakes separately in an attended window. Confirm there is no
   active shared-daemon work before touching its binary or daemon, then validate
   the installed version against the pin.
5. Upgrade Herdr separately in an attended window using its publisher-owned
   update flow. Review client/server compatibility and release notes first, and
   verify the live fleet is clear before any server lifecycle action.
6. Upgrade GBrain only through Firstmate's documented backup, baseline,
   compatibility, migration, smoke-test, evaluation, and rollback procedure.
7. Re-run the read-only checker. Any unknown source, version mismatch, or
   prerelease result is a refusal to declare convergence.
