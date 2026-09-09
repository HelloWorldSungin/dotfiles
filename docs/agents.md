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

Each gets installed and learned one at a time - the bootstrap records the
install commands as they're adopted.

## Vendored skills

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

## GPT long context (Sol, Terra and Astra)

Both harnesses default these models to a 272,000-token window; each is opted in
separately, and the two ceilings are **not** the same.

| Harness | Mechanism | Effective window |
|---------|-----------|------------------|
| pi | `pi/models.json` → `~/.pi/agent/models.json`, `providers.openai-codex.modelOverrides` | **1,050,000** for `gpt-5.6-sol`, `gpt-5.6-terra` and `gpt-6-astra` |
| codex | global `model_context_window` in `~/.codex/config.toml` | **872,000** for `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` and `gpt-6-astra`; models with a lower `max_context_window` keep their own ceiling |

Pi's 1,050,000 is a *local* override: it governs pi's own context accounting and
model listing. Codex is different - its 0.153.4 catalog advertises
`max_context_window = 872000` for Sol, Terra, Luna and Astra, and
`models-manager` applies `configured.min(max_context_window)`, so a larger
configured value is silently clamped. 872,000 is what Codex advertises and
enforces for Astra, and it is the value this repo commits. Do not read Codex as
being at parity with pi, and do not read pi's override as evidence that the
upstream service accepts more than Codex's advertised ceiling.

Codex's key is global rather than per-model, and it is the only mechanism Codex
supports, so it is offered to the whole catalog and needs **no change at all** to
cover Astra. The same clamp bounds it per model: in the 0.153.4 catalog it
reaches the full 872,000 on `gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-terra`,
`gpt-5.6-luna`, `gpt-daybreak-blue-latest` and `codex-auto-review`. Models
advertising less keep their own lower ceiling (`gpt-daybreak-red-latest`
372,000; `gpt-5.5`, `gpt-5.4-mini` and `gpt-5.2` 272,000), and `gpt-5.4`, which
advertises 1,000,000, is held to the configured 872,000. Pi's overrides are
per-model, so Luna stays at 272,000 there.

To re-verify against an upgraded Codex, read the catalog the installed binary
embeds rather than trusting this list:

```
strings "$(dirname "$(readlink -f "$(command -v codex)")")"/../node_modules/@openai/codex-linux-x64/vendor/*/bin/codex \
  | grep -E '^      "(slug|max_context_window)"'
```

Requests above 272K total input tokens bill at the model's long-context rates for
the whole request. Neither override changes the selected model or effort.

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
