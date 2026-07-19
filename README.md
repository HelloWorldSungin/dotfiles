# dotfiles

Reproducible environment for the ArkNode agent host (CT110), Kun Chen-style:
one repo that can rebuild the whole setup from scratch on any Linux box. A
Mac client target will be added to the same flake later.

## The big picture

```
MacBook / phone  --ssh-->  CT110 (user sungin)
 (thin clients:             herdr server (sessions survive disconnects)
  rendering, fonts,          |- agent sessions (claude / codex / opencode)
  voice input)               |- nvim for reviewing diffs
                            environment built by THIS repo via Nix
```

Nothing important runs on the laptop anymore. The server owns the sessions;
any device can attach to them. Close the lid mid-task, reattach from your
phone at a cafe - the agent never noticed.

## How the machinery works

Three layers, each explained in depth in `docs/`:

1. **Nix + home-manager** (`flake.nix`, `home/`): declares every package and
   dotfile for the user. `./rebuild.sh` makes reality match the declaration.
   -> [docs/nix.md](docs/nix.md)
2. **Live-symlinked configs** (`config/`): home-manager doesn't copy these,
   it symlinks them back into this repo. Editing `~/.config/nvim/...` edits
   the repo, so every tweak is a `git diff` away from being committed. No
   rebuild needed for config changes.
3. **Agent layer** (`agents/AGENTS.md`): one memory file, symlinked into
   every harness's global memory location, so all agents follow the same
   rules. -> [docs/agents.md](docs/agents.md)

## Fresh machine (or fresh user) to fully working

```sh
git clone git@github.com:HelloWorldSungin/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./bootstrap.sh
```

That installs Nix, applies the home-manager config, sets zsh, installs herdr
and the agent harnesses. Then log in to each harness once (`claude`, etc.).

## Daily operations

| You want to...                     | Do this |
|------------------------------------|---------|
| Add/remove a package               | edit `home/sungin-ct110.nix`, then `rebuild` (alias) |
| Change nvim/herdr config           | just edit it - symlinks make it live; commit when happy |
| Update all pinned packages         | `nix flake update && ./rebuild.sh` |
| See what a rebuild would change    | `git diff` before running `rebuild` |
| Start / reattach sessions          | `ssh ct110` then `herdr` -> [docs/herdr.md](docs/herdr.md) |

## Server privilege model (CT110)

Deliberate separation, because agents here run high-agency (often
`--dangerously-skip-permissions`) on a box that also runs live trading:

- **`sungin`** — the developer account, which is ALSO the account agents run
  as. It has **password sudo** (`/etc/sudoers.d/sungin`), never NOPASSWD:
  the human escalates by typing a password; agents can't. `timestamp_timeout=0`
  disables sudo credential caching so an agent process can't ride a password
  the human typed moments earlier. It owns nothing under `researcher`, so even
  before sudo it can read but not write the infra (`/opt/ArkNode-AI` is 755).
- **`researcher`** — the infra identity that owns the training code, GPUs, and
  live services. Untouched by this repo.
- `ct110-root` (root SSH alias) remains the break-glass path and the way to set
  sungin's sudo password: `ssh ct110-root` then `passwd sungin`.

Why password-not-passwordless matters: `sungin` is shared between you and
autonomous agents, so any capability the account has, an agent has too. A
password the agent doesn't know (plus no credential cache) is what keeps sudo
human-only in practice.

Root bootstrap (one-time, run as root — creates the user this repo then configures):

```sh
adduser --disabled-password --gecos "" sungin
install -d -m700 -o sungin -g sungin /home/sungin/.ssh
# add your pubkey to /home/sungin/.ssh/authorized_keys
chsh -s /home/sungin/.nix-profile/bin/zsh sungin   # after nix/home-manager
```

Then, as `sungin`: clone this repo to `~/dotfiles` and run `./bootstrap.sh`.

## Docs

- [docs/nix.md](docs/nix.md) - how the flake and home-manager actually work
- [docs/vim-basics.md](docs/vim-basics.md) - vim from zero (modes, motions, editing)
- [docs/nvim.md](docs/nvim.md) - every plugin and why it's there
- [docs/herdr.md](docs/herdr.md) - sessions explained for non-tmux people
- [docs/agents.md](docs/agents.md) - the shared memory file and harness logins
- [docs/cheatsheet.md](docs/cheatsheet.md) - every keybind (nvim, zsh, herdr) on one page

## Layout

```
flake.nix              inputs (pinned nixpkgs, home-manager) + machine targets
home/sungin-ct110.nix  everything about the CT110 user environment
config/nvim/           neovim: init.lua -> lua/{vim-config,keys}.lua + plugins/
config/herdr/          herdr config (defaults; grows as preferences form)
config/wezterm/        Mac client terminal config (symlink ~/.config/wezterm here)
agents/AGENTS.md       single global memory file for all agent harnesses
bootstrap.sh           zero -> working machine (idempotent)
rebuild.sh             apply nix config after editing home/ or flake.nix
```
