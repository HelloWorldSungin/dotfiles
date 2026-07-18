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

return config
