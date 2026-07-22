export interface DotfileCommand {
  key: string;
  desc: string;
  category: "WezTerm" | "Herdr" | "TUI Prompt" | "Neovim" | "Zsh";
  subcategory?: string;
  config?: string;
  mode?: string;
  keywords: string[];
}

export const DOTFILE_CONFIGS = {
  WezTerm: "config/wezterm/wezterm.lua",
  Herdr: "config/herdr/config.toml",
  "TUI Prompt": "Claude, Codex, Pi, Agy, Cursor",
  Neovim: "config/nvim/lua/vim-config.lua",
  Zsh: "home/common.nix & home/sungin-mac.nix",
};

export const DOTFILE_CHEATSHEET_DATA: DotfileCommand[] = [
  // 1. WEZTERM
  {
    key: "Cmd + n",
    desc: "Opens a new WezTerm window",
    category: "WezTerm",
    subcategory: "Window & Tab",
    config: "wezterm.lua",
    keywords: ["new", "window", "wezterm", "open", "create"]
  },
  {
    key: "Cmd + t",
    desc: "Opens a new tab",
    category: "WezTerm",
    subcategory: "Window & Tab",
    config: "wezterm.lua",
    keywords: ["new", "tab", "open", "create"]
  },
  {
    key: "Cmd + w",
    desc: "Closes current tab or window",
    category: "WezTerm",
    subcategory: "Window & Tab",
    config: "wezterm.lua",
    keywords: ["close", "tab", "window", "exit", "kill"]
  },
  {
    key: "Cmd + 1 .. 9",
    desc: "Jumps directly to tab 1 through 9",
    category: "WezTerm",
    subcategory: "Window & Tab",
    config: "wezterm.lua",
    keywords: ["switch", "tab", "jump", "number"]
  },
  {
    key: "Cmd + c / v",
    desc: "Standard macOS text copy and paste",
    category: "WezTerm",
    subcategory: "Clipboard",
    config: "wezterm.lua",
    keywords: ["copy", "paste", "clipboard", "text"]
  },
  {
    key: "Cmd + Shift + x",
    desc: "QuickSelect Mode: Highlights URLs, file paths, and IDs on screen for 1-key copying",
    category: "WezTerm",
    subcategory: "Search & Selection",
    config: "wezterm.lua",
    keywords: ["quickselect", "url", "path", "copy", "select", "highlight"]
  },
  {
    key: "Cmd + Shift + f",
    desc: "Scrollback Search: Opens interactive text search overlay for current scrollback",
    category: "WezTerm",
    subcategory: "Search & Selection",
    config: "wezterm.lua",
    keywords: ["scrollback", "search", "find", "history", "overlay"]
  },
  {
    key: "Cmd + + / Cmd + -",
    desc: "Increase or decrease font size",
    category: "WezTerm",
    subcategory: "Display",
    config: "wezterm.lua",
    keywords: ["font", "zoom", "size", "increase", "decrease", "text"]
  },
  {
    key: "Cmd + 0",
    desc: "Resets font size to 15.0pt",
    category: "WezTerm",
    subcategory: "Display",
    config: "wezterm.lua",
    keywords: ["reset", "zoom", "font", "default", "size"]
  },

  // 2. HERDR - Session & Connection
  {
    key: "herdr",
    desc: "Connect to active session on CT110",
    category: "Herdr",
    subcategory: "Session & Connection",
    config: "config.toml",
    keywords: ["attach", "herdr", "connect", "ct110", "session"]
  },
  {
    key: "herdr --remote ct110",
    desc: "Connect from Mac with thin-client clipboard & image paste",
    category: "Herdr",
    subcategory: "Session & Connection",
    config: "config.toml",
    keywords: ["remote", "thin", "client", "mac", "clipboard", "image", "paste"]
  },
  {
    key: "Ctrl + b, q",
    desc: "Detach Session: Detaches screen; all agent sessions keep running on CT110",
    category: "Herdr",
    subcategory: "Session & Connection",
    config: "config.toml",
    keywords: ["detach", "session", "disconnect", "bg", "background"]
  },
  {
    key: "herdr agent list",
    desc: "List status of all running AI agents (working / blocked / idle / done)",
    category: "Herdr",
    subcategory: "Session & Connection",
    config: "config.toml",
    keywords: ["agent", "list", "status", "ai", "working", "idle"]
  },
  {
    key: "herdr status",
    desc: "Show server uptime and active sessions",
    category: "Herdr",
    subcategory: "Session & Connection",
    config: "config.toml",
    keywords: ["server", "status", "overview", "uptime", "sessions"]
  },

  // HERDR - Window & Pane Navigation
  {
    key: "Ctrl + b, c",
    desc: "Opens a new tab",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["create", "tab", "new", "tmux"]
  },
  {
    key: "Ctrl + b, n / p",
    desc: "Switch to next or previous tab",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["next", "prev", "tab", "switch"]
  },
  {
    key: "Ctrl + b, 1 .. 9",
    desc: "Jump to tab 1 through 9",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["select", "tab", "jump", "number"]
  },
  {
    key: "Ctrl + b, v",
    desc: "Split current pane side-by-side (vertical split)",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["split", "vertical", "pane", "side"]
  },
  {
    key: "Ctrl + b, -",
    desc: "Split current pane top-and-bottom (horizontal split)",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["split", "horizontal", "pane", "top", "bottom"]
  },
  {
    key: "Ctrl + b, Arrow / h/j/k/l",
    desc: "Move focus between split panes",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["move", "pane", "focus", "arrow", "vim", "hjkl"]
  },
  {
    key: "Ctrl + b, z",
    desc: "Toggle current pane fullscreen (zoom)",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["zoom", "pane", "fullscreen", "toggle", "expand"]
  },
  {
    key: "Ctrl + b, x",
    desc: "Close / kill current pane",
    category: "Herdr",
    subcategory: "Navigation (tmux)",
    config: "config.toml",
    keywords: ["close", "kill", "pane", "remove"]
  },

  // HERDR - Copy Mode & Image Paste
  {
    key: "Ctrl + b, [",
    desc: "Enter Copy Mode: Scroll back through history using vim keys",
    category: "Herdr",
    subcategory: "Copy Mode",
    config: "config.toml",
    keywords: ["copy", "mode", "scroll", "history", "vim"]
  },
  {
    key: "v / Space",
    desc: "Start visual text selection (in copy mode)",
    category: "Herdr",
    subcategory: "Copy Mode",
    config: "config.toml",
    keywords: ["select", "visual", "start", "selection"]
  },
  {
    key: "y / Enter",
    desc: "Yank selected text to clipboard and exit copy mode",
    category: "Herdr",
    subcategory: "Copy Mode",
    config: "config.toml",
    keywords: ["yank", "copy", "clipboard", "enter"]
  },
  {
    key: "q / Esc",
    desc: "Exit copy mode and return to normal terminal prompt",
    category: "Herdr",
    subcategory: "Copy Mode",
    config: "config.toml",
    keywords: ["exit", "cancel", "copy", "esc", "prompt"]
  },
  {
    key: "Ctrl + Shift + v",
    desc: "Remote Image Paste: Pastes image from Mac clipboard into CT110 remote session",
    category: "Herdr",
    subcategory: "Copy Mode",
    config: "config.toml",
    keywords: ["remote", "image", "paste", "mac", "ct110", "clipboard"]
  },

  // 3. TERMINAL PROMPT LINE EDITING (TUI AGENTS)
  {
    key: "Ctrl + u",
    desc: "Erases input line from cursor to beginning",
    category: "TUI Prompt",
    subcategory: "Line Editing",
    config: "Agent Prompts & Zsh",
    keywords: ["erase", "line", "beginning", "start", "delete", "clear"]
  },
  {
    key: "Ctrl + k",
    desc: "Erases input line from cursor to end",
    category: "TUI Prompt",
    subcategory: "Line Editing",
    config: "Agent Prompts & Zsh",
    keywords: ["erase", "line", "end", "delete", "kill"]
  },
  {
    key: "Ctrl + a then Ctrl + k",
    desc: "Select All & Delete: Wipes the entire input prompt box instantly",
    category: "TUI Prompt",
    subcategory: "Line Editing",
    config: "Agent Prompts & Zsh",
    keywords: ["select", "all", "delete", "clear", "wipe", "prompt", "box"]
  },
  {
    key: "Option + Backspace / Ctrl + w",
    desc: "Erases the previous word",
    category: "TUI Prompt",
    subcategory: "Line Editing",
    config: "Agent Prompts & Zsh",
    keywords: ["delete", "word", "backspace", "erase"]
  },
  {
    key: "Ctrl + l",
    desc: "Clears the terminal screen buffer",
    category: "TUI Prompt",
    subcategory: "Line Editing",
    config: "Agent Prompts & Zsh",
    keywords: ["clear", "screen", "buffer", "terminal", "cls"]
  },

  // 4. NEOVIM - Global
  {
    key: "Esc",
    desc: "Auto-Save: Saves current buffer (:w) on exit",
    category: "Neovim",
    subcategory: "Global",
    mode: "Normal",
    config: "vim-config.lua",
    keywords: ["esc", "save", "auto-save", "write", "normal"]
  },
  {
    key: "Ctrl + a",
    desc: "Select All: Selects entire file content (ggVG)",
    category: "Neovim",
    subcategory: "Global",
    mode: "Normal",
    config: "vim-config.lua",
    keywords: ["select", "all", "file", "normal"]
  },
  {
    key: "p",
    desc: "Non-Clobber Paste: Pastes over selection without clobbering register (\"_dP)",
    category: "Neovim",
    subcategory: "Global",
    mode: "Visual",
    config: "vim-config.lua",
    keywords: ["paste", "non-clobber", "visual", "register", "replace"]
  },

  // NEOVIM - Plugins
  {
    key: "<Space> f",
    desc: "Find Files: Fuzzy search files by name (snacks.nvim)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["find", "files", "fuzzy", "search", "snacks"]
  },
  {
    key: "<Space> s",
    desc: "Live Grep: Grep text across codebase (snacks.nvim)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["grep", "search", "codebase", "text", "snacks"]
  },
  {
    key: "<Space> b",
    desc: "Buffers: Switch active buffers (snacks.nvim)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["buffers", "switch", "open", "snacks"]
  },
  {
    key: "g d",
    desc: "Definition: Go to LSP symbol definition (snacks.nvim)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["definition", "lsp", "goto", "symbol", "snacks"]
  },
  {
    key: "<Space> e",
    desc: "File Explorer: Editable buffer file tree (oil.nvim)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["explorer", "oil", "tree", "file", "dir"]
  },
  {
    key: "<Space> g",
    desc: "Git UI: Git status, diff, staging, and commit dashboard (neogit)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["git", "ui", "neogit", "status", "diff", "commit", "stage"]
  },
  {
    key: "Ctrl + n",
    desc: "Multi-Cursor: Select word under cursor & spawn next match cursor (vim-visual-multi)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["multi", "cursor", "select", "match", "vim-visual-multi"]
  },
  {
    key: "Ctrl + Shift + Down / Up",
    desc: "Add Cursor: Spawn multi-cursor directly below / above (vim-visual-multi)",
    category: "Neovim",
    subcategory: "Plugins",
    config: "vim-config.lua",
    keywords: ["multi", "cursor", "below", "above", "add", "vertical"]
  },

  // 5. ZSH & SHELL
  {
    key: "Ctrl + f",
    desc: "Accept Suggestion: Accepts autosuggested ghost text",
    category: "Zsh",
    subcategory: "Shell Shortcuts",
    config: "common.nix",
    keywords: ["accept", "suggestion", "autosuggest", "ghost", "completion"]
  },
  {
    key: "Ctrl + r",
    desc: "History Search: Interactive fzf command history search",
    category: "Zsh",
    subcategory: "Shell Shortcuts",
    config: "common.nix",
    keywords: ["history", "search", "fzf", "command", "reverse"]
  },
  {
    key: "Ctrl + t",
    desc: "Pick File: Interactive fzf file picker",
    category: "Zsh",
    subcategory: "Shell Shortcuts",
    config: "common.nix",
    keywords: ["pick", "file", "fzf", "find", "select"]
  },
  {
    key: "Alt + c",
    desc: "Pick Directory: Interactive fzf directory picker & cd",
    category: "Zsh",
    subcategory: "Shell Shortcuts",
    config: "common.nix",
    keywords: ["pick", "directory", "dir", "fzf", "cd", "folder"]
  }
];
