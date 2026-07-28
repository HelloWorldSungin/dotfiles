-- WezTerm (Mac client) - the window into CT110. Config is plain Lua and
-- hot-reloads on save, so tweak values and watch them apply instantly.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Same theme as nvim on the server: one continuous visual surface.
config.color_scheme = "rose-pine-moon"

-- Glyphs (herdr sidebar, starship prompt, claude spinner) render on THIS
-- machine, which is why the nerd font lives here and not on the server.
config.font = wezterm.font_with_fallback({ "Hack Nerd Font", "Menlo" })
config.font_size = 15.0

-- Frameless-but-resizable window. The translucency look depends as much on
-- your desktop WALLPAPER as on these numbers - a colorful wallpaper glows
-- through; a dark one reads nearly solid. Tune opacity to taste.
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.82
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true

-- The servers have xterm-256color terminfo but not wezterm's own.
config.term = "xterm-256color"

-- Keybindings for Mac (QuickSelect, Search, and Copy Mode)
config.keys = {
  -- QuickSelect (Cmd+Shift+X or Ctrl+Shift+X)
  { key = "x", mods = "CMD|SHIFT", action = wezterm.action.QuickSelect },
  { key = "x", mods = "CTRL|SHIFT", action = wezterm.action.QuickSelect },

  -- Search scrollback (Cmd+F or Cmd+Shift+F)
  { key = "f", mods = "CMD|SHIFT", action = wezterm.action.Search({ CaseSensitiveString = "" }) },
  { key = "f", mods = "CMD", action = wezterm.action.Search({ CaseSensitiveString = "" }) },
  { key = "f", mods = "CTRL|SHIFT", action = wezterm.action.Search({ CaseSensitiveString = "" }) },

  -- WezTerm Copy mode (Cmd+Shift+C)
  { key = "c", mods = "CMD|SHIFT", action = wezterm.action.ActivateCopyMode },

  -- Map Cmd+Shift+V to send Ctrl+Shift+V to Herdr for remote image paste
  { key = "v", mods = "CMD|SHIFT", action = wezterm.action.SendKey({ key = "V", mods = "CTRL|SHIFT" }) },
}

return config
