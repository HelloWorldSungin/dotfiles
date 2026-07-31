# Keybind & Tool Cheatsheet

One page reference for every shortcut configured across **WezTerm**, **Herdr**, **Neovim**, and **Zsh**.

---

## 1. WezTerm (Mac Terminal Client)

Config: [`config/wezterm/wezterm.lua`](../config/wezterm/wezterm.lua) (live-symlinked to `~/.config/wezterm/wezterm.lua`).

### Window, Tab & Clipboard Shortcuts

| Shortcut | Mode / Action | Description |
| :--- | :--- | :--- |
| `Cmd` + `n` | New Window | Opens a new WezTerm window |
| `Cmd` + `t` | New Tab | Opens a new tab |
| `Cmd` + `w` | Close Tab | Closes current tab or window |
| `Cmd` + `1` .. `9` | Switch Tab | Jumps directly to tab 1 through 9 |
| `Cmd` + `c` / `v` | Copy / Paste | Standard macOS text copy and paste |
| `Cmd` + `Shift` + `x` | **QuickSelect Mode** | Highlights URLs, file paths, and IDs on screen for 1-key copying |
| `Cmd` + `Shift` + `f` | **Scrollback Search** | Opens interactive text search overlay for current scrollback |
| `Cmd` + `+` / `Cmd` + `-` | Font Zoom | Increase or decrease font size |
| `Cmd` + `0` | Reset Zoom | Resets font size to 15.0pt |

---

## 2. Herdr (Session Server & Agent Manager)

Config: [`config/herdr/config.toml`](../config/herdr/config.toml) (live-symlinked to `~/.config/herdr/config.toml`).

Herdr uses a **prefix key** (`Ctrl` + `b` by default, tmux-compatible). Press and release `Ctrl+b`, then press the command key.

### Session & Connection

| Command / Shortcut | Action | Description |
| :--- | :--- | :--- |
| `herdr` | Attach | Connect to active session on CT110 |
| `herdr --remote ct110` | Remote Thin Client | Connect from Mac with thin-client clipboard & image paste |
| `Ctrl` + `b`, `q` | **Detach Session** | Detaches screen; all agent sessions keep running on CT110 |
| `herdr agent list` | Agent Status | List status of all running AI agents (working / blocked / idle / done) |
| `herdr status` | Server Overview | Show server uptime and active sessions |

### Window & Pane Navigation (tmux-style)

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl` + `b`, `c` | Create Tab | Opens a new tab |
| `Ctrl` + `b`, `n` / `p` | Next / Prev Tab | Switch to next or previous tab |
| `Ctrl` + `b`, `1` .. `9` | Select Tab | Jump to tab 1 through 9 |
| `Ctrl` + `b`, `v` | Split Vertical | Split current pane side-by-side |
| `Ctrl` + `b`, `-` | Split Horizontal | Split current pane top-and-bottom |
| `Ctrl` + `b`, Arrow / `h`/`j`/`k`/`l` | Move Pane | Move focus between split panes |
| `Ctrl` + `b`, `z` | Zoom Pane | Toggle current pane fullscreen |
| `Ctrl` + `b`, `x` | Close Pane | Kill current pane |

### Herdr Copy Mode & Image Paste

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl` + `b`, `[` | **Enter Copy Mode** | Scroll back through history using vim keys |
| `v` or `Space` (in copy mode) | Start Selection | Begin visual text selection |
| `y` or `Enter` (in copy mode) | Yank / Copy | Copy selected text to clipboard and exit copy mode |
| `q` or `Esc` (in copy mode) | Exit Copy Mode | Return to normal terminal prompt |
| `Ctrl` + `Shift` + `v` | **Remote Image Paste** | Pastes image from Mac clipboard into CT110 remote session (configured in `config.toml`) |

---

## 3. Terminal Prompt Line Editing (Inside TUI Agents)

Used inside agent input prompts (Claude Code, Codex, Pi, Agy, Cursor) and Zsh:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl` + `u` | Erase to Start | Erases input line from cursor to beginning |
| `Ctrl` + `k` | Erase to End | Erases input line from cursor to end |
| `Ctrl` + `a` then `Ctrl` + `k` | **Select All & Delete** | Wipes the entire input prompt box instantly |
| `Option` + `Backspace` or `Ctrl` + `w` | Delete Word | Erases the previous word |
| `Ctrl` + `l` | Clear Screen | Clears the terminal screen buffer |

---

## 4. Neovim (Shared Editor)

Leader key = **`<Space>`** ([`config/nvim/lua/vim-config.lua`](../config/nvim/lua/vim-config.lua)).

### Global Shortcuts

| Shortcut | Mode | Action | Description |
| :--- | :--- | :--- | :--- |
| `Esc` | Normal | **Auto-Save** | Saves current buffer (`:w`) on exit |
| `Ctrl` + `a` | Normal | **Select All** | Selects entire file content (`ggVG`) |
| `p` | Visual | **Non-Clobber Paste** | Pastes over selection without clobbering register (`"_dP`) |
| `gt` / `gT` | Normal | **Next / Prev Tab** | Cycle forward (`gt`) or backward (`gT`) through tabs |
| `1gt` .. `9gt` | Normal | **Select Tab** | Jump directly to Tab 1 through 9 |
| `Ctrl` + `w` + `v` / `s` | Normal | **Split Window** | Split window vertically (`v`) or horizontally (`s`) |
| `Ctrl` + `w` + `h`/`j`/`k`/`l` | Normal | **Navigate Split** | Move focus left (`h`), down (`j`), up (`k`), right (`l`) |

### Plugin Shortcuts

| Shortcut | Feature | Plugin | Description |
| :--- | :--- | :--- | :--- |
| `<Space>` `f` | Find Files | `snacks.nvim` | Fuzzy search files by name (press `<Ctrl-v>` to open in vsplit) |
| `<Space>` `s` | Live Grep | `snacks.nvim` | Grep text across codebase |
| `<Space>` `b` | Buffers | `snacks.nvim` | Switch active buffers |
| `g` `d` | Definition | `snacks.nvim` | Go to LSP symbol definition |
| `<Space>` `e` | File Explorer | `oil.nvim` | Editable buffer file tree (press `v` for vsplit, `s` for split) |
| `<Space>` `g` | Git UI | `neogit` | Git status, diff, staging, and commit dashboard |
| `<Space>` `wc` | Create Worktree | `git-worktree.nvim` | Interactively create git worktree & branch via Telescope |
| `<Space>` `wm` | Manage Worktree | `git-worktree.nvim` | Switch worktree (`<Enter>`) or delete (`<Ctrl-d>` / `d`) |
| `Ctrl` + `n` | Multi-Cursor | `vim-visual-multi` | Select word under cursor & spawn next match cursor |
| `Ctrl` + `Shift` + `Down` / `Up` | Add Cursor | `vim-visual-multi` | Spawn multi-cursor directly below / above |

---

## 5. Zsh & Shell Shortcuts

Config: [`home/common.nix`](../home/common.nix) & [`home/sungin-mac.nix`](../home/sungin-mac.nix).

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl` + `a` / `Ctrl` + `f` | Accept Suggestion | Accepts autosuggested ghost text |
| `Ctrl` + `r` | History Search | Interactive fzf command history search |
| `Ctrl` + `t` | Pick File | Interactive fzf file picker |
| `Alt` + `c` | Pick Directory | Interactive fzf directory picker & `cd` |
