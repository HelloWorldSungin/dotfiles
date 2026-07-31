-- Entry point. Kept tiny on purpose: each concern lives in its own module
-- under lua/ (Kun's structure). Load order: options -> keymaps -> plugins.
require("vim-config")
require("keys")

-- Safely wrap nvim_buf_set_name for oil.nvim buffer moves
if vim.api and vim.api.nvim_buf_set_name then
  local orig_set_name = vim.api.nvim_buf_set_name
  vim.api.nvim_buf_set_name = function(bufnr, name)
    local ok, res = pcall(orig_set_name, bufnr, name)
    if ok then return res end
    return nil
  end
end

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
