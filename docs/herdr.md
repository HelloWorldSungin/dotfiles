# Herdr - sessions explained (no tmux background assumed)

## The one concept that matters

When you SSH somewhere and run a program, the program's lifetime is tied to
your connection: WiFi drops, laptop sleeps -> program dies. A **session
server** breaks that tie. Herdr runs a small background server on CT110
that owns the real terminals; what you see over SSH is just a *view* of
them. Disconnect and the sessions keep running. Reconnect - from the Mac,
from your phone, from anywhere - and you're looking at the same screen
again, mid-scroll, as if you never left.

That's the entire magic. Everything else is layout and navigation.

Herdr is "tmux built for the agent era": unlike tmux it *understands* agent
harnesses - the sidebar shows each agent's state (working / blocked / idle /
done) so you know who needs you without cycling through windows.

## Vocabulary

| Term | Meaning |
|------|---------|
| session | a named group of terminals living on the server |
| workspace | herdr's organizational unit (top-left panel) - e.g. one per project |
| tab | like browser tabs inside a workspace |
| pane | a split within a tab (agent left, nvim right) |
| attach / detach | connect your screen to a session / disconnect leaving it running |
| prefix key | `ctrl+b` by default - press it, release, then a command key |

## Daily flow

```sh
ssh ct110        # from Mac, phone, anywhere
herdr            # attach (creates a session the first time)
# ... work: launch claude in a pane, split another for nvim ...
# detach (or just close the terminal window - same effect)
```

Useful commands:

```sh
herdr                       # attach to your session
herdr session attach NAME   # attach a specific session
herdr agent list            # what agents are running, and their states
herdr status                # server overview
herdr server reload-config  # apply config.toml edits to a live server
herdr --default-config      # print every option + default (see config/herdr/)
```

From the Mac there's an upgrade over plain SSH: `herdr --remote ct110`
runs a local thin client that bridges your clipboard (including image
paste) into the remote session. Plain `ssh ct110` + `herdr` is the
lowest-common-denominator path and what you'll use from the phone.

## Keys

Defaults are tmux-like: `ctrl+b` prefix, then a command key (`q` detaches;
keys for new tab / split / navigate are listed by `herdr --default-config`).
As muscle memory forms, put overrides in `config/herdr/config.toml` - it's
symlinked live, then `herdr server reload-config`.

## If characters ever look broken again

That's never fonts on the server (glyphs render on YOUR device) - it's the
locale. The server must have a UTF-8 locale (`locale` should say
`en_US.UTF-8`, set via `/etc/default/locale`) and your SSH config forwards
yours (`SendEnv LANG LC_*` in the Mac's ~/.ssh/config). A session server
captures its locale AT START - after fixing the locale, restart the herdr
server before expecting clean rendering.

## Phone setup

1. Twingate on, SSH app (Termius/Blink/etc.) -> `sungin@192.168.68.110`.
2. Run `herdr`. Same session, same state, smaller window.
3. Detach or just close the app - nothing dies.

## Updating from 0.8.2 to 0.9.0

The repository already pins 0.9.0 and its publisher checksums in
`config/dev-tools-versions.sh`. Confirm the current stable version against
[Herdr's manifest](https://herdr.dev/latest.json) before any later update.
The pinned installer installs only when absent; Home Manager activation does
not upgrade an existing Herdr binary.

Check the installed client and the running server separately:

```sh
herdr update --help
herdr status client --json
herdr status server --json
```

Repeat server checks for each named session with a trailing `--session NAME`.
Workers under a Firstmate lab contract must use its guarded helper for these
commands and all lab lifecycle operations.

**Keep the 0.8.2 client while active servers still run 0.8.2.** The 0.9.0
client uses protocol 22; the 0.8.2 server uses protocol 20. A named-session
test confirmed that `pane list` returns `protocol_mismatch` with this pairing.
Even replacing only the executable would break subsequent fleet CLI calls.
The compatible-server update behavior described in the
[0.9.0 release notes](https://github.com/herdrdev/herdr/releases/tag/v0.9.0)
does not make this older server compatible.

In 0.8.2, `herdr update` refuses to run inside Herdr. Outside Herdr, a plain
update with a running target asks to stop its sessions and pane processes;
noninteractive input declines installation. `--handoff` opts into server
lifecycle changes and is not proof that active work will survive. Do not
bypass the inside-Herdr guard or accept a stop while fleet work is active.

The [publisher installer](https://herdr.dev/install.sh) supports
`HERDR_INSTALL_DIR` for staging a checksum-verified binary separately. Its
inspected installation path downloads and installs the executable without
starting, stopping, or updating a server. Review the script again before
using a later revision. Staging does not activate the new version: leave the
staged directory off the fleet's PATH until client/server compatibility is
established.

Completing this transition requires an attended server upgrade after active
work has safely finished, or a separately authorized preservation procedure
proven for this exact version pair. Stopping the old server exits its pane
processes; saved layouts and resumable agent histories do not preserve those
processes. A lab test never authorizes stopping or handing off a live session.
