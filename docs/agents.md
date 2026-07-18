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
