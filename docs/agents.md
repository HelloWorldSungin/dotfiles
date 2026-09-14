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

## GPT long context (Sol, Terra and Astra)

The Codex subscription backend catalog defaults Sol, Terra, Luna, and Astra
to 272,000 tokens (`context_window = 272000`), and each of them separately
advertises `max_context_window = 872000`. The two harnesses opt into the
wider window independently and now disagree on purpose: Pi keeps the 872,000
override, while Codex returns to the 272,000 catalog default.

| Harness | Mechanism | Effective window |
|---------|-----------|------------------|
| pi | `pi/models.json` → `~/.pi/agent/models.json`, `providers.openai-codex.modelOverrides` | **872,000** for `gpt-5.6-sol`, `gpt-5.6-terra` and `gpt-6-astra` (per-model override; Luna and every other model in the catalog keep the openai-codex built-in 272,000) |
| codex | global `model_context_window` in `~/.codex/config.toml` (committed fallback `272000`, overridable via `CODEX_MODEL_CONTEXT_WINDOW` when running `bin/codex-set-context-window`) | **272,000** for every model on the catalog; `models-manager` clamps it to `min(configured, max_context_window)`, so raising the key above a model's `max_context_window` is silently held down to that ceiling |

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

Codex is different in mechanism: the verified 0.154.0 catalog advertises
`max_context_window = 872000` for `gpt-6-astra`, `gpt-5.6-sol`,
`gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-daybreak-blue-latest` and
`codex-auto-review`, and `models-manager` applies
`configured.min(max_context_window)`, so a configured value larger than the
catalog ceiling is silently clamped. The committed fallback is 272,000 and
that is the catalog's own `context_window` for Sol, Terra, Luna and Astra; `gpt-5.5`,
`gpt-5.4-mini`, `gpt-5.2`, `gpt-daybreak-red-latest` (372,000), and `gpt-5.4`
(advertised 1,000,000) all also resolve to 272,000 because the configured
ceiling is at or below their `max_context_window`. Raising the configured
key (up to a model's `max_context_window`) is the only way any model can
exceed 272,000 in Codex today. The global key is the only mechanism
Codex supports, so it is offered to the whole catalog without any per-model
counterpart. Do not restore a Pi override above the 872,000 advertised
maximum, and do not add a direct OpenAI API-key provider for this.

To re-verify against an upgraded Codex, read the catalog the installed binary
embeds rather than trusting this list (npm installs exactly one platform
package, so the `codex-*` glob resolves on CT110 and the Mac alike). The
installed binary is the authoritative source for the four models that
matter: their catalog `context_window` is 272,000 and `max_context_window`
is 872,000.

```sh
strings "$(dirname "$(readlink -f "$(command -v codex)")")"/../node_modules/@openai/codex-*/vendor/*/bin/codex \
  | grep -E '^      "(slug|context_window|max_context_window)"'
```

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
that one key - the file stays machine-owned, so project trust entries, hook
approvals and TUI preferences are untouched, and repeat rebuilds are a no-op.
An activation step has no removal path the way a declared file does: dropping it
from `home/common.nix` leaves the key behind, so back the setting out by editing
`~/.codex/config.toml` by hand.
Both tools read their config at startup, so **start a new session** to pick the
change up; no model reselection is needed.

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
