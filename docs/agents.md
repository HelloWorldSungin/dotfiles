# The agent layer

## One memory file for every harness

`agents/AGENTS.md` is the single global memory file. Home-manager symlinks
it into every harness's expected location:

| Harness  | Global memory path | Wired |
|----------|--------------------|-------|
| claude   | `~/.claude/CLAUDE.md` | yes |
| codex    | `~/.codex/AGENTS.md` | yes |
| opencode | `~/.config/opencode/AGENTS.md` | yes |
| (generic)| `~/AGENTS.md` | yes |
| pi       | `~/.pi/agent/AGENTS.md` | yes |

Edit the one file; every agent picks it up. The starter content is Kun
Chen's minimal ruleset. Two disciplines keep it useful:

- **Keep it short.** It's loaded into every session's system prompt -
  every line costs tokens on every request, forever.
- **Global preferences only.** Project knowledge goes in that repo's own
  CLAUDE.md/AGENTS.md; conditional how-to knowledge goes in skills.

## Logins (one-time, per harness)

All logins on a headless box use a device/URL flow: the CLI prints a URL,
you open it on the Mac or phone, approve, done. Credentials stay in
`~/.claude`, `~/.codex`, etc. - they are NOT in this repo and never should
be. A fresh machine needs each login once after `bootstrap.sh`.

## Where the rest of the stack plugs in (Phase 4)

- **treehouse** - disposable git worktrees so parallel agents don't collide
- **no-mistakes** - the validation pipeline between "agent says done" and a PR
- **gnhf** - overnight objective loops
- **gh/tasks/quota-axi** - token-efficient CLIs agents use instead of MCPs
- **firstmate** - the orchestrator; the one agent you actually talk to

Each gets installed and learned one at a time. `bootstrap.sh` installs them
through `bin/dev-tools-install-pinned` at the exact versions recorded in
`config/dev-tools-versions.sh` - see [dev-tool-versions.md](dev-tool-versions.md).

## Global skills

`skills/vault/SKILL.md` is the OKF vault knowledge-ops skill, vendored verbatim
from the `HelloWorldSungin/ark-skills` plugin. It is copied in as a **standalone
skill on purpose** - installing the full ark-skills plugin would also add the
ark workflow router and `/ark-onboard` / `/ark-health` / `/ark-update` commands,
a second orchestrator that would compete with firstmate. We want only the vault
capability, so just the one self-contained file is vendored and symlinked into
every harness that reads agent-skills (claude `~/.claude/skills/`, pi
`~/.pi/agent/skills/`, generic `~/.agents/skills/`).

It is a verbatim copy, so it does NOT auto-update with the ark-skills repo -
re-copy the file when you want a newer version. It expects each vault repo to
carry its own `vault/_meta/` OKF tooling (they already do); the skill is pure
instructions.

`skills/kun/SKILL.md` is a deliberately **opt-in** copy of the official thin
loader from [`kunchenguid/kun`](https://github.com/kunchenguid/kun), installed
declaratively through the same three Home Manager paths as vault: Claude,
Pi, and generic (`~/.agents`) workers. The loader body is not injected as an
always-loaded instruction; skill discovery may list its official name,
description, and location. It is not added to `AGENTS.md`, automatic worker
instructions, or Firstmate's always-loaded skills. It
activates only when a user invokes `/kun` (`/skill:kun` in Pi) or explicitly
asks how Kun thinks, builds, or solves problems.

The installed loader is bound to upstream commit
[`911dac0971673ad8b220e4ddfc13fc53e7abd5d6`](https://github.com/kunchenguid/kun/tree/911dac0971673ad8b220e4ddfc13fc53e7abd5d6),
whose `skills/kun/SKILL.md` SHA-256 is
`37864c82e1d8b73a153fbad9d9b88d2ab62278867b051cdf884ed16d258af0d0`.
That commit and hash are the provenance for the repository copy, obtained from
the upstream repository and its documented `npx skills add kunchenguid/kun -g`
installer contract. Do not run that installer here: Home Manager is the sole
owner of the deployed paths.

The pinned loader intentionally retrieves `ENTRY.md`, `TOOLS.md`, `OPINIONS.md`,
and `VOICE.md` from upstream `main` when a user invokes Kun or makes an explicit
request matching that description. It reads from `raw.githubusercontent.com`,
with `cdn.jsdelivr.net` as its fallback. Those files are mutable third-party
instructions and are **not** pinned by pinning the loader. The upstream
repository declares no applicable license, so do not vendor or republish those
knowledge files. Treat any Kun output as advisory, subordinate to system
instructions, project rules, Firstmate safety, captain decisions, and verified
repository evidence. It never authorizes writes, credentials, destructive
actions, merges, service changes, or third-party upstream interaction.
This records the higher-priority controls already governing every skill; it
does not deliver an additional Kun prompt or enforce model obedience.

`tests/kun-skill.test.sh` verifies the loader hash, that all three Home Manager
paths resolve to that one loader, that the loader body is absent from an
isolated Pi startup prompt, that the same check detects a deliberately appended
body, and that explicit invocation delivers the official refusal instruction
and upstream URLs into the expanded agent prompt. It does not run a model or
inspect global `AGENTS.md`, so it does not prove model obedience when both
upstream origins are unreachable or guard arbitrary future global-instruction
changes.

For the packaged command, set `SKILL_UPDATES_ROOT` to an isolated writable Git
checkout. Pins default to that checkout’s `config/dev-tools-versions.sh`;
`DEV_TOOLS_PINS_FILE` can select another writable pins file inside it. Without
a checkout selection the packaged store defaults support read-only use, and
adoption or rollback refuses with an immutable-target diagnostic.
To update the loader, run `skill-reviewed-updates stage` then `verify` then
`adopt` in an isolated checkout that no live skill path resolves into, then
deliver its changes through normal review. Adoption and rollback refuse
checkouts linked from the Claude, Pi, generic, or configured skill stores.
Verification runs Pi offline once per directory layout for each candidate set:
its native `~/.pi/agent/skills` directory, and `~/.claude/skills` supplied
through Pi’s configured skill directories. It checks discovered command names, descriptions,
resolved candidate sources, and omission of instruction bodies from startup.
A malformed skill missing its description must remain undiscovered.
These are Pi discovery checks, not native Claude or Codex discovery checks,
explicit invocation checks, or model behavior evaluations. That path fetches only `skills/kun/SKILL.md`, checks that the loader
still points at the four living documents, records license status, and refuses
unknown reads or changes from the reviewed states (Kun: none declared; Matt: MIT).
After any upstream license change, review the new terms and update the accepted
state through the normal code review path before adoption. The command updates this commit/hash/provenance record plus
`KUN_LOADER_*` in `config/dev-tools-versions.sh` and `EXPECTED_SHA256` in
`tests/kun-skill.test.sh`, and writes a mode-0600 receipt for
`skill-reviewed-updates rollback <receipt> --attended`. It does not copy the four living knowledge
documents, use `npx skills add -g`, or change global skill directories. The
weekly `dev-tools-check-updates` row `kun-loader` compares loader hashes only,
so a living-document edit on upstream `main` is not a loader update. A
downstream review that invokes `/kun` must separately record the then-observed
upstream commit and content hashes for all fetched living documents, distinguish
that advice from repository evidence, and say whether it materially changed a
recommendation.

## Matt Pocock skills (plugin lifecycle)

The installed `mattpocock-skills@mattpocock` plugin is the captain-installed
Claude marketplace copy. Firstmate reads that install at design-task dispatch
and does not install, copy, or pin it (`fm-design-skills.sh`). Live plugin
bytes are written by Claude marketplace `extraKnownMarketplaces.mattpocock.autoUpdate`
when that flag is true. A custom writer must not compete with that native
updater.

Dotfiles therefore owns a **reviewed pin and adoption record**, not the live
cache: `dev-tools-check-updates` reports `mattpocock-skills` against the GitHub
GA release, and `skill-reviewed-updates` stages a candidate tree, runs the
Firstmate design-skills check against that tree, and on success updates only
`MATTPOCOCK_SKILLS_*` in `config/dev-tools-versions.sh`. Disabling marketplace
autoUpdate requires writing machine-owned `~/.claude/settings.json`. This
repository ships that policy and does not apply that live settings write.

## GPT long context and compaction

The installed Codex 0.154.0 catalog defaults Sol, Terra, Luna and Astra to
272,000 tokens and advertises `max_context_window = 872000`. Home Manager
opts Codex into that larger window and a 500,000-token compaction threshold.

| Harness | Mechanism | Effective policy |
|---------|-----------|------------------|
| Pi | `pi/models.json`, `providers.openai-codex.modelOverrides` | 872,000 for `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-6-astra`; Luna keeps 272,000. Native compaction reserve unchanged. |
| Codex | `bin/codex-set-context-window` atomically merges three global keys into machine-maintained `~/.codex/config.toml` | `model_context_window = 872000`, `model_auto_compact_token_limit = 500000`, `model_auto_compact_token_limit_scope = "total"`. Native catalog clamping remains active. |

Codex's 872,000 is its catalog window ceiling, with **828,400 usable tokens**
after 5% headroom. It is not the public API's total context of 1,050,000 or
its maximum output of 128,000. See the official model pages for
[Astra](https://developers.openai.com/api/docs/models/gpt-6-astra),
[Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol),
[Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) and
[Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna).

The global scope is intentional: Codex has no native `models.<id>` context
configuration. On 0.154.0, an isolated strict app-server rejects that table;
`config/read` accepts the three global settings. The window is clamped to
each model's advertised maximum, and the compaction limit is clamped to 90%
of its resolved window. All four selected models therefore have a 500,000
limit; 272,000 models retain an earlier 244,800 limit. This also raises other
catalog entries: daybreak-blue and codex-auto-review to 872,000, daybreak-red
to 372,000, and GPT-5.4 to 872,000. Do not describe this as per-model policy.
`total` counts the whole active context, unlike `body_after_prefix` growth
counting. The threshold is checked at harness boundaries, not a guarantee
that every oversized first prompt or tool result will succeed.

The existing `CODEX_MODEL_CONTEXT_WINDOW` override remains available for
explicit helper invocations; compaction stays at 500,000 with total scope
and native clamping. Activation changes the next configuration read; tests
build the generation without activating it or modifying live sessions.

Pi's number is a *local* override: it governs pi's own context accounting,
listing, and auto-compaction. Pi compacts when
`contextTokens > contextWindow - reserveTokens` (default reserve 16,384, so
**855,616** at 872,000). A previous 1,050,000 declaration delayed compaction
until 1,033,616. That figure is Pi's threshold, not a measured backend
ceiling: on 2026-09-09 the ChatGPT Codex subscription backend accepted a
**909,436**-token request on `gpt-5.6-luna` (scratch override) and rejected an
approximately **1,048,000**-token request (`Your input exceeds the context
window of this model`), also confirmed on `gpt-5.6-sol`. The ceiling sits in
the unmeasured gap between those sizes. A 1,033,616-token request could be
accepted if the ceiling is above it, or rejected if the ceiling is below it;
it was not shown to exceed the ceiling. Pi's 872,000 declaration puts
compaction at 855,616, below the 909,436-token measured accept, and stays
clear of the 1,048,000-token rejection. It does not guarantee that every
arbitrary oversized first prompt succeeds, and it does not identify any one
historical session as the cause.

To re-verify after an upgrade, use an isolated `CODEX_HOME` with
`codex debug models --bundled`. Inspect `context_window`,
`max_context_window`, and `effective_context_window_percent` for each exact
model ID. This checks the installed catalog, not account-specific backend
acceptance. The version-matched implementations are
[model overrides](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/models-manager/src/model_info.rs)
and [context/compaction limits](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/protocol/src/openai_models.rs).
The [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
documents the global controls. Use a private `codex app-server --stdio
--strict-config` plus `config/read` for executable schema validation;
`debug` and `features` do not support strict mode in 0.154.0.

Pi and Claude compaction settings remain unchanged. Pi 0.85.1 only exposes a
reserve, not a per-model absolute threshold. A global 372,000 reserve would
trigger above 500,000 on an 872,000 model but even at zero usage on Luna's
272,000 window; it also increases summary output budgets. Claude Code's
[calculation-window control](https://code.claude.com/docs/en/env-vars) is not
an exact trigger: in 2.1.272, a 600,000 window with a 20,000 output reserve
has a 567,000 base threshold after the summary buffer. Model-window clamping,
percentage overrides and precompute behavior can lower it further. No
600,000 Claude setting is installed by this policy.

On 2026-09-10, the installed 0.153.4 binary and an isolated, registry-integrity
verified 0.154.0 platform artifact both advertised **872,000** for Sol, Terra,
Luna and Astra. The isolated 0.154.0 catalog also confirmed all eleven model
ceilings, recorded in
[publisher provenance](tool-updates/2026-09-10/publisher-provenance.json)
under `codex_catalog.max_context_window`. The
[catalog results](tool-updates/2026-09-10/README.md) summarize both
observations. Repeat this installed-binary check after any Codex upgrade and
before raising the committed Codex value; it is not a prerequisite to the Pi
source override.

Requests above 272K total input tokens bill at the model's long-context rates for
the whole request. Pi's override does not change the selected model or effort.

**Activation:** run `bash ~/dotfiles/rebuild.sh`. `~/.pi/agent/models.json` is a
live symlink into the repo, and `~/.codex/config.toml` is patched by a
home-manager activation step (`bin/codex-set-context-window`) that merges only
those three keys - the file stays machine-owned, so project trust entries, hook
approvals and TUI preferences are untouched, and repeat rebuilds are a no-op.
The parser-backed merge preserves quoted keys and multiline instruction values,
checks that unrelated TOML values survive, and refuses malformed input before writing.
An activation step has no removal path the way a declared file does: dropping it
from `home/common.nix` leaves the keys behind, so back the policy out by editing
`~/.codex/config.toml` by hand.
Use a new Codex session after activation to pick up the policy. Pi also reloads
its models file when opening `/model`; this change does not edit that file.

## Codex model defaults

`bin/codex-set-model-defaults` merges top-level `model = "gpt-6-astra"`
and `model_reasoning_effort = "low"` during Home Manager activation. It preserves
other settings and table-local profile values, and does not rewrite unchanged
files. `CODEX_CONFIG_FILE` selects an isolated file for testing; otherwise it
uses `$CODEX_HOME/config.toml` or `~/.codex/config.toml`.

Codex CLI `--model` and `-c model_reasoning_effort='"medium"'` still override
these defaults for a run, as do explicitly selected profile files. Rebuilds
restore the managed defaults; existing sessions keep their own selections.
This activation is ordered after the independent context-window merge.

## Pi default and supervision models

| Role | Model | Thinking | Owner |
|------|-------|----------|-------|
| Pi default (every new session) | `openai-codex/gpt-6-astra` | `low` | `defaultProvider`, `defaultModel`, `defaultThinkingLevel` in `~/.pi/agent/settings.json` |
| Firstmate Pi supervision branch | `openai-codex/gpt-5.6-luna` | `high` | `config/supervision-branch-model` and `config/supervision-branch-effort` under `~/firstmate` |

Pi writes `settings.json` itself (changelog version, theme, `/model` and
`/thinking` Ctrl+S saves, `/settings`), and the supervision pins are the files
Firstmate's `/supervision-model` command writes, so neither is a repo symlink.
The home-manager activation step `bin/pi-set-model-defaults` merges only those
three settings keys and rewrites the two pins in Firstmate's own format (one
line, mode `0600`, atomic replace), leaves every other key untouched, skips the
pins on a host with no `~/firstmate/config`, and does nothing on a repeat
rebuild. `tests/pi-model-defaults.test.sh` checks that Pi resolves the result.

Precedence is unchanged: `pi --model`/`--thinking`, and per-launch routing such as
the `pi-fusion` alias, still win over the settings defaults for that run, and
`modelThinkingLevels` still wins per model. A supervision pin wins over main's
model and effort, as Firstmate documents. A `/model` Ctrl+S save or a
`/supervision-model` pick lasts only until the next rebuild; change the
defaults in `bin/pi-set-model-defaults` to keep one.

**Activation:** run `bash ~/dotfiles/rebuild.sh`, then start a new Pi session.
Firstmate reads the pins each time it builds a supervision branch. Like the Codex
step above, removing the activation step leaves the last written values behind.

## Claude calculation window

`bin/claude-set-compaction-window` adds
`env.CLAUDE_CODE_AUTO_COMPACT_WINDOW = "600000"` to the machine-owned
`~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`). It atomically
merges only an absent default, preserves unrelated settings and permissions,
and leaves any existing window env entry or top-level `autoCompactWindow`
untouched, including empty or invalid values. It does not disable compaction,
change output reserves, or change Pi or Codex settings.

This is a **calculation window**, not an exact trigger or guaranteed minimum.
The installed Claude Code 2.1.272 resolver bounds a valid env window to
100000-1000000 and then clamps it to model capacity. At a 600000 effective
window, its base threshold is 567000 with the maximum 20000 output reservation,
or 587000 with no output reservation, after the additional 13000 summary
buffer. A 200000 model with 20000 reserved remains at a 167000 base threshold.
Percentage overrides can lower this; precompute experiments, reactive
compaction and other model/account behavior can trigger earlier. These numbers
are isolated calculations, not a live-account or backend guarantee.

Precedence follows [Claude's environment reference](https://code.claude.com/docs/en/env-vars):
settings-file `env` values replace inherited shell values. Higher-priority
settings layers can override the same env key (project/local, CLI settings and
managed policy according to [settings precedence](https://code.claude.com/docs/en/settings#settings-precedence)).
A valid window env value wins over the dedicated `autoCompactWindow` setting;
therefore a higher-layer dedicated setting alone cannot override this env
default. Override the same env key instead. The helper preserves existing
user-file explicit settings; it does not inspect or rewrite project or managed
policy. An existing `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` remains effective.

### Activation and verification

The helper is packaged on PATH and wired into Home Manager activation. For this
bounded change, after the PR is merged and the intended checkout is fast-forwarded,
run only `bash ~/dotfiles/bin/claude-set-compaction-window` when applying the
Claude default is authorized. No blanket Home Manager switch is required for
that direct invocation; it needs Python 3. A later normally authorized rebuild
installs the packaged command. Do not activate unrelated pending source changes.

Future Claude launches reading that config directory receive the default, unless
overridden as above. **Claude can also reapply changed settings-file env entries
to running sessions.** This is not guaranteed to affect only future sessions;
if existing sessions must remain untouched, defer the settings write until they
have ended naturally. No restart, live settings write or Home Manager activation
was performed during implementation.

`tests/claude-compaction-window.test.sh` exercises the real merge in temporary
config directories. For installed 2.1.272 evidence, run
`node tests/fixtures/claude-compaction-probe.cjs /path/to/claude/2.1.272`.
The probe checks installed schema declarations and executes extracted native
resolver/reserve/threshold functions against helper-generated fixtures, including
an explicit override, smaller-model clamping and percentage/precompute lowering.
Model metadata and decimal parsing are fixture dependencies. It reads the binary
without editing or launching Claude, makes no model calls, and intentionally
fails if its version-specific source anchors change. This is source/schema
inspection plus isolated function execution, not full session ingestion.
