-- WezTerm Client Configuration (Windows 11 & macOS)
-- Hot-reloads on save, so tweak values and watch them apply instantly.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local is_windows = wezterm.target_triple:find("windows") ~= nil

-- Prefer EGL rendering for maximum performance and GPU compatibility on Windows / Linux
config.prefer_egl = true
config.front_end = "WebGpu"

-- Same theme as nvim on the server: one continuous visual surface.
config.color_scheme = "rose-pine-moon"

-- Platform-specific visual & font settings
if is_windows then
  config.font = wezterm.font_with_fallback({ "Hack Nerd Font", "Cascadia Code", "Consolas" })
  config.font_size = 12.0
  -- On Windows 11, Acrylic / Mica requires window_background_opacity to be 0.0
  -- so the Desktop Window Manager (DWM) can blur the wallpaper behind it.
  config.win32_system_backdrop = "Acrylic"
  config.window_background_opacity = 0.0
else
  config.font = wezterm.font_with_fallback({ "Hack Nerd Font", "Menlo" })
  config.font_size = 15.0
  config.window_background_opacity = 0.82
  config.macos_window_background_blur = 50
end

-- Frameless-but-resizable window.
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true

-- The servers have xterm-256color terminfo but not wezterm's own.
config.term = "xterm-256color"

-- SSH Domain Configuration for Ubuntu VM (skim-ub24-1)
config.ssh_domains = {
  {
    name = "skim-ub24-1",
    remote_address = "skim-ub24-1",
    username = "skim",
    assume_shell = "Posix",
  },
}

-- Keybindings (Windows & macOS compatible)
config.keys = {
  -- QuickSelect (Cmd+Shift+X or Ctrl+Shift+X) - pick URLs, git hashes, filepaths
  { key = "x", mods = "CMD|SHIFT", action = wezterm.action.QuickSelect },
  { key = "x", mods = "CTRL|SHIFT", action = wezterm.action.QuickSelect },

  -- Search scrollback (Cmd+F, Cmd+Shift+F, Ctrl+Shift+F)
  { key = "f", mods = "CMD|SHIFT", action = wezterm.action.Search({ CaseSensitiveString = "" }) },
  { key = "f", mods = "CMD", action = wezterm.action.Search({ CaseSensitiveString = "" }) },
  { key = "f", mods = "CTRL|SHIFT", action = wezterm.action.Search({ CaseSensitiveString = "" }) },

  -- Clipboard Copy / Paste
  { key = "v", mods = "CTRL|SHIFT", action = wezterm.action.PasteFrom("Clipboard") },
  { key = "c", mods = "CTRL|SHIFT", action = wezterm.action.CopyTo("Clipboard") },
  { key = "v", mods = "CMD|SHIFT", action = wezterm.action.SendKey({ key = "V", mods = "CTRL|SHIFT" }) },

  -- WezTerm Copy mode (Cmd+Shift+C on Mac, Alt+Shift+C on Windows)
  { key = "c", mods = "CMD|SHIFT", action = wezterm.action.ActivateCopyMode },
  { key = "c", mods = "ALT|SHIFT", action = wezterm.action.ActivateCopyMode },

  -- Font zoom controls (Ctrl+Shift+Plus / Minus / 0)
  { key = "+", mods = "CTRL|SHIFT", action = wezterm.action.IncreaseFontSize },
  { key = "_", mods = "CTRL|SHIFT", action = wezterm.action.DecreaseFontSize },
  { key = ")", mods = "CTRL|SHIFT", action = wezterm.action.ResetFontSize },
}

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = is_windows and 0.0 or 0.62

local function same_text_hsb(actual, expected)
  if actual == nil or expected == nil then
    return actual == expected
  end
  return actual.hue == expected.hue
    and actual.saturation == expected.saturation
    and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
  local overrides = window:get_config_overrides() or {}
  local text_hsb = nil
  local opacity = is_windows and 0.0 or 0.82
  if not window:is_focused() then
    text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
    opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
  end

  if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
    return
  end

  overrides.foreground_text_hsb = text_hsb
  overrides.window_background_opacity = opacity
  window:set_config_overrides(overrides)
end)

return config
