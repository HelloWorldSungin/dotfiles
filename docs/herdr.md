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
