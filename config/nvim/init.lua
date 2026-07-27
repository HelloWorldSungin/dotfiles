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

-- Shim vim.validate for Neovim 0.10 positional argument syntax (e.g. gitsigns.nvim)
if vim.validate then
  local orig_validate = vim.validate
  vim.validate = function(opt, ...)
    if type(opt) == "string" then
      local val, validator, optional = ...
      return orig_validate({ [opt] = { val, validator, optional } })
    end
    return orig_validate(opt, ...)
  end
end

-- Configure OSC 52 clipboard provider for headless Linux SSH connections
if vim.g.clipboard == nil then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok and osc52 then
    vim.g.clipboard = {
      name = "OSC 52",
      copy = {
        ["+"] = osc52.copy("+"),
        ["*"] = osc52.copy("*"),
      },
      paste = {
        ["+"] = osc52.paste("+"),
        ["*"] = osc52.paste("*"),
      },
    }
  end
end

-- Shim vim.treesitter query functions for Neovim 0.9.5 compatibility (used by neogit diff_highlights)
if vim.treesitter then
  local fallback_query = { text = "", captures = {}, info = { patterns = {} } }
  local ts_query = rawget(vim.treesitter, "query") or vim.treesitter.query
  if type(ts_query) == "table" then
    if ts_query.get then
      local orig_get = ts_query.get
      ts_query.get = function(...)
        local res = orig_get(...)
        return res or fallback_query
      end
    end
    if ts_query.get_query then
      local orig_get_q = ts_query.get_query
      ts_query.get_query = function(...)
        local res = orig_get_q(...)
        return res or fallback_query
      end
    end
  end
end



-- Polyfill vim.lsp.protocol.Methods & vim.lsp.ms for Neovim 0.9.5 (used by oil.nvim LSP workspace.lua)
if vim.lsp then
  vim.lsp.protocol = vim.lsp.protocol or {}
  vim.lsp.protocol.Methods = vim.lsp.protocol.Methods or setmetatable({}, {
    __index = function()
      return function() end
    end,
  })
  vim.lsp.ms = vim.lsp.ms or vim.lsp.protocol.Methods
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

