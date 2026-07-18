# Keybind cheatsheet

One page, every keybind this repo defines. You forgot the key - find it
here, then follow the link for the why.

## Neovim

Leader = **space** (`config/nvim/lua/vim-config.lua`). Press space and
*pause*: which-key pops up with everything you can press next.

Config: [`config/nvim/lua/keys.lua`](../config/nvim/lua/keys.lua) (global),
[`config/nvim/lua/plugins/`](../config/nvim/lua/plugins) (plugin keys).
Detail: [nvim.md](nvim.md), [vim-basics.md](vim-basics.md).

### Find and navigate

| Keys | Does | Source |
|------|------|--------|
| `space f` | fuzzy-find files by name | snacks |
| `space s` | live grep the project | snacks |
| `space b` | switch between open buffers | snacks |
| `gd` | go to definition (needs an LSP attached) | snacks |
| `space e` | file explorer as an editable buffer | oil |

### Editing

| Keys | Does | Source |
|------|------|--------|
| `Esc` | save the file (normal mode only) | keys.lua |
| `Ctrl-a` | select all (normal mode only) | keys.lua |
| `p` | paste WITHOUT clobbering the clipboard (visual mode only) | keys.lua |

### Git

| Keys | Does | Source |
|------|------|--------|
| `space g` | git status / diff / stage / commit UI | neogit |

Gitsigns adds gutter markers and inline blame but binds no keys here.
Plain vim motions (`hjkl`, `dd`, `ciw`, `Ctrl-w` splits) are vim's own -
see [vim-basics.md](vim-basics.md).

## Zsh

Config: [`home/sungin-ct110.nix`](../home/sungin-ct110.nix) (`programs.zsh`
plus the `programs.fzf` integration). No dedicated doc - the nix file is
the reference; see [nix.md](nix.md) for how it is applied.

| Keys | Does | Source |
|------|------|--------|
| `Ctrl-f` | accept the ghost-text autosuggestion | `bindkey` in `initContent` |
| `Ctrl-r` | fuzzy-search command history | fzf zsh integration |
| `Ctrl-t` | fuzzy-pick a file path into the command line | fzf zsh integration |
| `Alt-c` | fuzzy-pick a directory and cd into it | fzf zsh integration |

The fzf three are bound by `programs.fzf.enableZshIntegration = true`, not
written out in this repo - they are fzf's defaults, active because the
integration is on.

Shell aliases (`g`, `gs`, `gd`, `gl`, `gpl`, `v`, `lg`, `rebuild`, `ccd`,
`ccdr`) are commands, not keybinds - read them straight from the nix file.

## Herdr

Config: [`config/herdr/config.toml`](../config/herdr/config.toml).
Detail: [herdr.md](herdr.md).

The config file is deliberately empty of overrides, so herdr runs its
**defaults** (tmux-like): press the prefix, release, then a command key.

| Keys | Does |
|------|------|
| `Ctrl-b` | prefix - starts every herdr command |
| `Ctrl-b` `q` | detach (sessions keep running on the server) |

The full default key table is not duplicated here because this repo does
not define it. Print it with `herdr --default-config`. To override a key,
add it to `config/herdr/config.toml` (symlinked live), then
`herdr server reload-config`.
