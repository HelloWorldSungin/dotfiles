-- Neovim 0.9.5 Compatibility Layer
vim.uv = vim.uv or vim.loop

-- Polyfill vim.islist (introduced in Neovim 0.10, was vim.tbl_islist in 0.9)
vim.islist = vim.islist or vim.tbl_islist or function(t)
  if type(t) ~= "table" then return false end
  local i = 1
  for k in pairs(t) do
    if t[i] == nil then return false end
    i = i + 1
  end
  return true
end

-- Block legacy/system aerial plugin from throwing < 0.10 deprecation error
package.loaded["aerial"] = { setup = function() end }
package.loaded["aerial.config"] = { setup = function() end }

-- Shim vim.fn.has for Neovim 0.10 version checks in modern plugins (like oil.nvim)
local orig_has = vim.fn.has
vim.fn.has = function(item)
  if item == "nvim-0.10" or item == "nvim-0.10.0" or item == "nvim-0.11" then
    return 1
  end
  return orig_has(item)
end

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

if not _G.lazy_setup_done then
  _G.lazy_setup_done = true

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
end

