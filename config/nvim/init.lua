-- Neovim 0.9.5 Compatibility Layer
vim.uv = vim.uv or vim.loop

-- Polyfill vim.fs.joinpath (introduced in Neovim 0.10)
if vim.fs and not vim.fs.joinpath then
  vim.fs.joinpath = function(...)
    return (table.concat({ ... }, "/"):gsub("//+", "/"))
  end
end

-- Shim vim.api.nvim_get_hl to strip 'create' key (invalid in Neovim 0.9.5)
if vim.api and vim.api.nvim_get_hl then
  local orig_get_hl = vim.api.nvim_get_hl
  vim.api.nvim_get_hl = function(ns, opts)
    if type(opts) == "table" and opts.create ~= nil then
      local clean_opts = {}
      for k, v in pairs(opts) do
        if k ~= "create" then clean_opts[k] = v end
      end
      return orig_get_hl(ns, clean_opts)
    end
    return orig_get_hl(ns, opts)
  end
end

-- Entry point. Kept tiny on purpose: each concern lives in its own module
-- under lua/ (Kun's structure). Load order: options -> keymaps -> plugins.
require("vim-config")
require("keys")

-- Bootstrap the lazy.nvim plugin manager if it isn't installed yet.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load every file in lua/plugins/ as a plugin spec.
require("lazy").setup("plugins")

