# Developer and agent tool version ownership

`config/dev-tools-versions.sh` is the machine-readable owner for external tool
pins and stable source policies. `flake.lock` owns the immutable Nix input revisions, and
`config/nvim/lazy-lock.json` owns Neovim plugin commits. The pins below were
verified on 2026-09-10 against each publisher's registry, release feed, or
manifest. The [audit evidence](tool-updates/2026-09-10/README.md) records the
publisher provenance, checksums, value-free contract comparisons, and pending
live convergence.
GBrain is excluded from this sweep; its report-only row remains unchanged.
A version is stable only when the publisher's stable/default registry
tag or a non-draft, non-prerelease release says so. Numeric tags containing
alpha, beta, preview, nightly, snapshot, or another suffix are excluded.

## External pins and stable policies

| Tool | Selection | Authority and stable judgment | Fresh install | Apply boundary |
|---|---:|---|---|---|
| Determinate Nix Installer | Verified 3.22.3 exception | Latest stable was 3.24.2 at review, but its installer lacks a publisher checksum | Versioned installer URL plus recorded installer SHA-256 | Report only |
| Claude Code | Latest at invocation | npm default `latest` tag, not the `stable` dist-tag. Numeric stable only; guarded apply stays off | Resolve version and integrity, then verify the exact artifact. Install-if-absent | Report only |
| Codex | Latest at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify the exact artifact. Install-if-absent | Report only |
| OpenCode | Latest at invocation | npm default `latest` tag; suffixed beta and snapshot versions are refused | Resolve version and integrity, then verify the exact artifact. Install-if-absent | Report only |
| Pi | Latest at invocation | `@earendil-works/pi-coding-agent` default tag. The retired Mario Zechner package is not the fleet distribution | Resolve version and integrity, then verify the exact artifact. Install-if-absent | Report only |
| Antigravity CLI | Latest production manifest at invocation | Google's per-platform production manifest | Publisher asset and SHA-512 from that manifest. Install-if-absent | Report only; its own self-update remains an upstream limitation |
| Cursor Agent | 2026.09.08-6caf4ff | Version embedded in Cursor's official moving installer | No automated install; observed snapshot only | Report only |
| Treehouse | Latest stable at invocation | Latest non-draft, non-prerelease GitHub release, resolved once per operation | Release archive verified against that release's publisher `checksums.txt`, only when absent | Report only |
| no-mistakes | Latest stable at invocation | Latest non-draft, non-prerelease GitHub release; later prerelease tags are excluded automatically | Release archive verified against that release's publisher `checksums.txt`, only when absent | Attended only |
| Herdr | Latest stable at invocation | `herdr.dev/latest.json` | Publisher asset and SHA-256, only when absent | Attended compatibility review; activation deferred |
| GBrain | 0.48.5.0 | Latest non-draft, non-prerelease `garrytan/gbrain` release | Not installed here | Firstmate-owned attended migration |
| gnhf | Latest at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify the exact artifact | Guarded exact apply with receipts |
| gh-axi | Latest stable at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify exact artifact | Guarded exact apply with receipts |
| tasks-axi | Latest stable at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify exact artifact | Guarded exact apply with receipts |
| quota-axi | Latest stable at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify exact artifact | Guarded exact apply with receipts |
| chrome-devtools-axi | Latest stable at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify exact artifact | Guarded exact apply with receipts |
| lavish-axi | Latest stable at invocation | npm default `latest` tag; numeric stable only | Resolve version and integrity, then verify exact artifact | Guarded exact apply with receipts |
| OpenCode ACP invocation | Latest stable per launch | npm default tag; numeric version and publisher SHA-512 verified against the packed archive before local-tarball `npx` invocation | `npm-run-latest-stable` in `config/baby-menu/agents.json` | Report only |
| OMP ACP invocation | Latest stable per launch | Same verified npm selection | `npm-run-latest-stable` in `config/baby-menu/agents.json` | Report only |
| claude-spend invocation | Latest stable per launch | Same verified npm selection | The `cspend` alias delegates to `npm-run-latest-stable` | Report only |
| Firstmate source | Current upstream `main` | Authoritative default branch commit resolved once and verified after clone or fetch | Exact resolved commit on `main` | Guarded fast-forward with receipt |
| Baby Menu source | Latest stable release | Latest non-draft, non-prerelease `baby-menu-v` release resolved to a commit | Exact resolved release commit in a detached checkout | Report only |
| actions/checkout | v7.0.1 / `3d3c42e5aac5...` | Latest GitHub GA action release | Exact workflow action SHA | CI only |
| Determinate Nix Installer action | v23 / `3138316df39e...` | Latest GitHub GA action release | Exact workflow action SHA | CI only |
| Kun loader | [KUN_LOADER_REV and KUN_LOADER_SHA256](../config/dev-tools-versions.sh) | Exact `skills/kun/SKILL.md` from `kunchenguid/kun`; living ENTRY/TOOLS/OPINIONS/VOICE files are not this pin | Repository copy via Home Manager | Reviewed `skill-reviewed-updates` adopt; never live skill stores |
| Matt Pocock skills | [MATTPOCOCK_SKILLS_VERSION](../config/dev-tools-versions.sh) | Latest non-draft GitHub GA tag of `mattpocock/skills` (MIT) | Claude marketplace plugin; native autoUpdate owns live bytes | Reviewed pin adopt only; do not compete with marketplace autoUpdate |

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

Claude Code is the channel exception. It selects npm's default `latest` tag
(`npm view version`), not the publisher `stable` dist-tag. Those tags differ:
on 2026-09-22 `latest` was 2.1.280 and `stable` was 2.1.267. The row's channel
field stays `default` so neither the checker nor the installer reads
`dist-tags.stable`. A prerelease or missing integrity is refused. Guarded
apply stays `no`. `dev-tools-install-pinned` still skips Claude when any
`claude` command is already present, so a native install is not overwritten
and a newer binary is not downgraded. The guarded updater cannot mutate
Claude Code.

Codex, OpenCode, Pi, gnhf, and the axi tools use that same default `latest`
tag because it is their official stable release. Codex publishes `alpha` on
other tags; OpenCode publishes `beta`, `next`, and `dev` on other tags; Pi's
only other tag is `legacy-node20`. None of those packages has a separate
`stable` dist-tag. Numeric prerelease versions are refused, so a preview tag
is not selected. They stay install-if-absent. Codex, OpenCode, and Pi stay
off the guarded updater, so a running harness is not replaced. gnhf is
allowlisted and follows the existing receipt path.

Pi also carries a temporary prompt-loss patch outside this repository. This
policy does not freeze Pi's version: selection stays latest stable. It also
does not install over an existing `pi`, so the patch survives bootstrap and
the guarded updater. A later live replacement is allowed only after an
isolated compatibility check shows that patch still works on the resolved
version. That check is the removal condition for the live-update hold. It is
not a permanent pin.

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

## Latest stable policy: Firstmate developer tools

Firstmate npm tools select the publisher default tag at invocation:
`claude`, `codex`, `opencode`, `pi`, `gnhf`, `gh-axi`, `tasks-axi`,
`quota-axi`, `chrome-devtools-axi`, and `lavish-axi`. The `latest|publisher`
rows reject prereleases, a non-default channel, or missing integrity, then
re-query the resolved exact version and verify its packed archive against that
integrity before installing the local tarball. Receipts still bind
that exact version and integrity. `dev-tools-install-pinned` retains its
command name and install-if-absent behavior: an existing command is skipped
before discovery, including one outside the configured install prefix. A
moving-policy dry-run performs read-only discovery but installs nothing.
Exact rows in a trusted `DEV_TOOLS_PINS_FILE` override retain their existing
behavior; unrelated pins are unchanged.

Antigravity fresh installs read Google's production manifest for that
platform, then require its asset URL and SHA-512. An existing `agy` command
is left in place. Herdr keeps its publisher stable manifest and attended
boundary. Cursor remains the beta-only exception below.

`dev-tools-apply-updates` independently resolves each moving npm target and
requires it to match the checker's stable result. It verifies the packed
archive before previewing or installing from that local file, then uses the
active-worker protection, prefix observation,
prior-artifact evidence and mode-0600 receipt path. Receipts bind exact versions
and integrity for rollback even after the tag moves. A newer numeric installed
version is left alone; this policy does not automatically downgrade it. No
background apply timer is added. Busy lanes defer the current invocation; a
later manual invocation retries. There is no durable retry queue, automatic
retry hook, cross-session usage authority or admission protocol. no-mistakes
stays attended-only.

Treehouse and no-mistakes select the latest non-draft, non-prerelease GitHub
release (`latest|latest-archive` rows). The installer resolves that release once
per operation, fetches the same release's publisher `checksums.txt`, requires
exactly one SHA-256 entry for the platform archive, verifies the downloaded
archive against it, and requires the archive's own binary to report the resolved
version before anything is installed. A missing or ambiguous checksum entry, a
mismatch, a draft, a prerelease, a non-numeric tag or a version mismatch installs
nothing. Existing commands are never replaced or upgraded by bootstrap, and this
policy never starts, stops or restarts the no-mistakes daemon. Treehouse 3.x
reads the 2.x pool format and keeps every lease, but `treehouse status` rewrites
the pool state to version 4 and its dirty return and interactive exit paths now
exit 3 instead of 0 (Firstmate's machine callers use `get --lease` and
`return --force`, which are unaffected); activating it on a live pool is an
attended step, not part of this policy.

Herdr uses the top-level version, platform asset URL and SHA-256 from the
[publisher stable manifest](https://herdr.dev/latest.json), never its preview
feed or a guessed download fallback. Missing or malformed metadata and checksum
mismatches fail closed. An existing binary is never replaced by bootstrap, and
Herdr remains outside the guarded updater's allowlist. Stable selection does
not prove protocol compatibility or authorize live activation. Complete dotfiles
work first, then follow the separate attended transition in
[docs/herdr.md](herdr.md); keep the compatible client on the fleet PATH meanwhile.

WezTerm has no install/version lock in this repository. `home/sungin-mac.nix`
owns only the configuration link and application PATH. Its external install
policy is the publisher-supported stable Homebrew cask `wezterm`, documented
at [WezTerm macOS installation](https://wezterm.org/install/macos.html).
For a later attended Mac update, use `brew install --cask wezterm` when absent
or `brew upgrade --cask wezterm` when installed. Homebrew owns release selection,
checksums and already-current behavior. Do not use `wezterm@nightly`, historical
cask versions or an unverified direct download. Review any existing external
pin or nightly installation before that separate operation; dotfiles does not
alter it or terminate open terminals. No WezTerm installer is added here.

## Selection and application boundaries

Firstmate selects the current upstream `main` commit. The guarded updater
independently fetches and compares that commit, requires a clean local `main`
that can fast-forward, refuses active worker lanes, and records exact prior and
target commits before mutation. Baby Menu selects the latest stable release
for a fresh checkout and leaves an existing checkout untouched. Kun and Matt
skills continue through reviewed adoption; Matt's live plugin bytes remain
owned by Claude marketplace autoUpdate.

Firstmate's GitHub `releases/latest` endpoint returned 404 on 2026-11-11; it
does not offer a GA version selector. The current upstream `main` commit is
the available source target, and the fast-forward and active-lane checks keep
that selection from discarding unlanded work.

The Nix update path selects the current `nixos-26.05` and matching Home Manager
stable branches with `nix flake update`. `flake.lock` and the package versions
in the manifest record that selected dependency graph for reproducible builds;
they are refreshed together during an attended update. Neovim release-bearing
plugins use lazy.nvim's latest stable version selector, while
`config/nvim/lazy-lock.json` records the chosen commits. Plugins without a
release feed use the upstream default branch. CI actions resolve stable
releases to exact commit SHAs before workflow adoption.

Cursor publishes only a moving beta installer, so this repository has no
verifiable stable selection for it and never runs the installer. The Determinate
Nix installer is a temporary named exception: 3.22.3 remains the last verified
script while upstream's latest stable release was 3.24.2 at this review. Its
versioned installer has no published per-tag checksum (the checked `v3.22.3`
checksum URL returned 404 on 2026-11-11), so the recorded SHA-256 remains the
safe receipt until a publisher-verifiable stable update path exists.
GBrain remains outside dotfiles activation and follows Firstmate's attended
migration procedure.

Source inspection on 2026-09-15 confirmed the Herdr manifest schema and
WezTerm stable cask instructions. npm documents its default `latest` lookup in
[npm view](https://docs.npmjs.com/cli/v11/commands/npm-view/).
The isolated installer, checker and guarded-updater suites in `tests/` are the
behavioral evidence; no live installation or service lifecycle is needed.

## Nix-owned inventory

The stable package authority is Nixpkgs 26.05 at
`d58a46e3bc02d91ebe04667f8397752a749c0024`. Home Manager is the matching
26.05 input at `fd0956c99c41ae3c13a73a638f1f7e963aebc4ab`. This supersedes the
deprecated 25.11 channel. The lock file carries the content hashes.

| Package | Version | Package | Version |
|---|---:|---|---:|
| gh | 2.100.0 | lazygit | 0.61.1 |
| nodejs | 24.19.0 | uv | 0.11.21 |
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
the wrong binary. `git`, `jq`, and `nodejs` are wrapper inputs too, but they
are also in the user environment, so they stay `user-env`: an operator whose
`node` resolves to another build still sees that drift. Home Manager modules also own home-manager,
Neovim, zsh, Starship, fzf, and Git. Neovim's fourteen plugin commits remain
independently exact in `config/nvim/lazy-lock.json`; the initial lazy.nvim clone
checks out that recorded commit. Intentional updates select upstream's annotated
`stable` tag and record its peeled commit in the lock.

## Neovim plugin pins

Plugins with a GitHub release feed select the latest stable version on update.
Projects without releases select their default branch. The checker compares
the installed checkout, recorded lock-file commit, and current authoritative
release or branch commit.

| Plugin | Stable source | Exact commit |
|---|---|---|
| codewindow.nvim | No releases; default branch at audit time | `a8e175043ce3baaa89e0a6b5171bcd920aab3dad` |
| diffview.nvim | No releases; default branch at audit time | `4516612fe98ff56ae0415a259ff6361a89419b0a` |
| gitsigns.nvim | v2.1.0 GA | `a462f416e2ce4744531c6256252dee99a7d34a83` |
| lazy.nvim | Publisher `stable` tag, currently v11.17.5 GA | `85c7ff3711b730b4030d03144f6db6375044ae82` |
| neogit | v2.0.0 GA | `43fa47fb61773b0d90a78ebc2521ea8faaeebd86` |
| nvim-treesitter | No releases; default branch at audit time | `d4d59cb369da46b95699bd2200efbcffc6dadb3b` |
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
  machine-owned Codex config remain mutable state. Home Manager merges its owned
  Codex keys without replacing that file; see [agents.md](agents.md).

## Check, install, and apply boundaries

`home/dev-tools.nix` is the single owner of the Nix packaging for these tools.
It builds the pin, flake-lock, and plugin-lock artifacts and the checker,
pinned installer, `cspend` wrapper, guarded updater, and reviewed skill-adopter
derivations, each with its complete runtime closure declared. The interactive
checker, the weekly timer, the login-shell startup check, and the updater's
checker dependency are therefore one derivation rather than four copies that
happen to agree. `skill-reviewed-updates` is on PATH with no timer: the weekly
check already includes `kun-loader` and `mattpocock-skills`.

The login shell runs `dev-tools-check-updates --startup`, which only reads the
cache the weekly timer refreshes; it never checks a source itself. The timer is
the only thing that refreshes that cache, so the login line reports tool state
for eight days after a check - the weekly cadence plus a day of grace - and
anything older, stamped in the future, or carrying no usable timestamp says which
of those it was - never an age this clock could not establish - instead of being
replayed as current. The four-hour freshness window still governs the audit
itself, which refreshes when it is run.

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

1. Fast-forward Firstmate's `main` branch to the latest upstream commit, after
   independently proving it matches the freshly fetched remote branch.
2. Install the five axi tools and gnhf at resolved stable versions, after
   independently verifying each exact artifact and integrity. Harness CLIs
   are not in this scope.

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
`skipped` - when the selected commit differs from the authoritative remote
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
reversal reinstalls into, not from the checker's PATH lookup - one bounded read of
the executable that prefix owns, taking its output and errors together under the
same timeout detection uses, accepted only as an exact version a reinstall could
restore, and never a name that walks out of the prefix. Nothing installed there,
an executable that reports no usable version, one that exits without reporting a
version, one that does not answer inside the bound, and one whose version could
never be reinstalled are different refusals that each say which they were, on the
reversal path as well as the apply path. The observed version
must also be re-verifiable against the registry; without that evidence the receipt could not
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
verified. A reversal reinstalls a private verified copy of that file,
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
- anything else - a third version, a moved commit, a tool the prefix does not
  carry or cannot be read from - is unreconcilable, rather than drift to
  overwrite, and the refusal names which of those it observed.

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
the receipt records. Registry backed reversals verify the packed prior archive
against the receipt's SHA-512 and install that local file; operator artifacts
are copied and verified before installation. Each re-proves its whole tier precondition immediately before
mutating, not only at preflight time: observed state, the worker lane, the branch
and clean checkout with verified ancestry for Firstmate, and the recorded prior
artifact evidence for npm. Bounded registry time separates the preflight from the
mutation, so work that lands in the checkout inside that window stops the reset
instead of being discarded by it.

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
   the installed version against the checker's latest stable result.
5. Upgrade Herdr separately in an attended window using its publisher-owned
   update flow. Review client/server compatibility and release notes first, and
   verify the live fleet is clear before any server lifecycle action.
6. Upgrade GBrain only through Firstmate's documented backup, baseline,
   compatibility, migration, smoke-test, evaluation, and rollback procedure.
7. Re-run the read-only checker. Any unknown source, version mismatch, or
   prerelease result is a refusal to declare convergence.
