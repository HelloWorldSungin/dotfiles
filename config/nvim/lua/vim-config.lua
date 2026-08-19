-- Core editor behavior. Anything about how vim itself behaves goes here,
-- so it's all centralized and easy to find (never inside plugin specs).

vim.g.mapleader = " " -- leader = space; every custom keybind hangs off this

-- Disable netrw in favor of oil.nvim
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.expandtab = true   -- tabs become spaces
vim.opt.shiftwidth = 2     -- one indent level = 2 spaces
vim.opt.tabstop = 2
vim.opt.softtabstop = 2    -- pressing <Tab> in insert mode inserts 2 spaces

vim.opt.number = true          -- current line shows its absolute number...
vim.opt.relativenumber = true  -- ...other lines show distance from cursor,
                               -- so `5k` / `3j` jumps read straight off the gutter

vim.opt.ignorecase = true -- searches ignore case...
vim.opt.smartcase = true  -- ...unless the query contains a capital letter

-- Configure OSC 52 clipboard provider for remote/headless sessions
local has_osc52, osc52 = pcall(require, "vim.ui.clipboard.osc52")
local use_osc52 = false

if has_osc52 then
  if vim.fn.has("mac") == 0 and os.getenv("WAYLAND_DISPLAY") == nil and os.getenv("DISPLAY") == nil then
    -- Headless Linux remote session (even if wl-copy/xclip are wrapper-installed, they will fail)
    use_osc52 = true
  elseif vim.fn.executable("pbcopy") == 0 and vim.fn.executable("xclip") == 0 and vim.fn.executable("xsel") == 0 and vim.fn.executable("wl-copy") == 0 then
    -- No clipboard tools available at all
    use_osc52 = true
  end
end

if use_osc52 then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = function() return {} end,
      ["*"] = function() return {} end,
    },
  }
end


vim.opt.clipboard = "unnamedplus" -- yank/paste goes through the system clipboard

vim.opt.scrolloff = 16 -- keep 16 lines visible above/below the cursor

vim.opt.undofile = true -- undo history survives closing and reopening files

vim.opt.hidden = true -- allow switching buffers without throwing E37 unsaved changes errors

vim.opt.diffopt:append("iwhite") -- Ignore whitespace changes in file diffs

vim.opt.termguicolors = true
