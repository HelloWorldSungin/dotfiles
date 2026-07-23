-- Entry point. Kept tiny on purpose: each concern lives in its own module
-- under lua/ (Kun's structure). Load order: options -> keymaps -> plugins.
require("vim-config")
require("keys")

-- Bootstrap the lazy.nvim plugin manager if it isn't installed yet.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load every file in lua/plugins/ as a plugin spec.
require("lazy").setup("plugins")
