# Neovim setup

> New to real vim (not just VS Code keybindings)? Start with
> [vim-basics.md](vim-basics.md) and nvim's built-in `:Tutor` first -
> this file covers the plugin layer on top.

Structure (Kun's modular layout - each concern in its own file):

```
config/nvim/
  init.lua                requires the modules below, bootstraps lazy.nvim
  lua/vim-config.lua      editor behavior (options only - no keybinds)
  lua/keys.lua            global keybinds not tied to a plugin
  lua/plugins/*.lua       one file per topic; every file = plugin specs
  lazy-lock.json          generated: the commit each plugin is pinned to
```

Plugins are managed by **lazy.nvim**: on first launch it clones everything
from GitHub automatically, so a fresh machine just works. `:Lazy` opens its
UI (update/clean plugins from there). `lazy-lock.json` is written by lazy.nvim
and committed, so a fresh machine gets the same plugin commits this one runs -
never hand-edit it; update plugins via `:Lazy` and commit the resulting diff.

## How you discover keybinds

Leader = **space**. Press space and *pause* - which-key pops up and shows
what you can press next. That popup is how you learn the bindings.

The full list lives in [cheatsheet.md](cheatsheet.md), which indexes every
keybind in this repo (nvim, zsh, herdr) on one page.

## Why each plugin is here

- **snacks** (folke): the pickers. `space f` / `space s` replace 90% of
  file-tree browsing - you jump straight to what you already know exists.
- **oil**: for the other 10%, when you need to *browse*. It renders a
  directory as a normal text buffer: `dd` a line and `:w` = delete that
  file; `yy` + `p` + rename the line + `:w` = copy the file. Editing the
  filesystem with vim motions.
- **neogit + gitsigns + diffview**: the agent-review workflow. An agent
  did a pile of changes -> `space g` -> browse the diff hunk by hunk,
  stage what you trust. Gitsigns adds gutter markers + inline blame.
- **which-key**: the discoverability layer (the space-pause popup).
- **rose-pine** (moon): same colorscheme as WezTerm - one visual surface.
- **render-markdown + treesitter**: replaces raw Markdown punctuation with a
  readable rendered view while editing Markdown files.

## Relative line numbers (if they look weird at first)

The gutter shows how far each line is from your cursor. To jump to a line
5 above, type `5k`; 12 below, `12j`. You read the jump distance straight
off the gutter instead of counting. A few days of use and it's automatic.

## Extending

Add a new file under `lua/plugins/` returning a plugin spec - lazy.nvim
picks it up on restart. Keep the pattern: options in the spec's `opts`,
keybinds in its `keys`, one topic per file. Deliberately NOT installed yet
(add when the need is felt, not before): LSP config, completion.
