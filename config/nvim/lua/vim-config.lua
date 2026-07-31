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

vim.opt.clipboard = "unnamedplus" -- yank/paste goes through the system clipboard

vim.opt.scrolloff = 16 -- keep 16 lines visible above/below the cursor

vim.opt.undofile = true -- undo history survives closing and reopening files

vim.opt.diffopt:append("iwhite") -- Ignore whitespace changes in file diffs

vim.opt.termguicolors = true
