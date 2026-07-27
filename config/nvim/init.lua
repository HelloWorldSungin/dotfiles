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

-- Polyfill vim.iter (introduced in Neovim 0.10, used by neogit diff.lua)
if not vim.iter then
  local function create_iter(list)
    local t = {}
    if type(list) == "table" then
      local is_arr = true
      for k in pairs(list) do
        if type(k) ~= "number" then is_arr = false break end
      end
      if is_arr then
        for _, v in ipairs(list) do table.insert(t, v) end
      else
        for _, v in pairs(list) do table.insert(t, v) end
      end
    end
    local iter_obj = {}
    function iter_obj:totable() return t end
    function iter_obj:flatten(level)
      local flat = {}
      local function do_flatten(arr, depth)
        for _, item in ipairs(arr) do
          if type(item) == "table" and (not depth or depth > 0) then
            do_flatten(item, depth and (depth - 1))
          else
            table.insert(flat, item)
          end
        end
      end
      do_flatten(t, level)
      return create_iter(flat)
    end
    function iter_obj:map(fn)
      local mapped = {}
      for i, v in ipairs(t) do
        local res = fn(v, i)
        if res ~= nil then table.insert(mapped, res) end
      end
      return create_iter(mapped)
    end
    function iter_obj:filter(fn)
      local filtered = {}
      for i, v in ipairs(t) do
        if fn(v, i) then table.insert(filtered, v) end
      end
      return create_iter(filtered)
    end
    function iter_obj:each(fn)
      for i, v in ipairs(t) do fn(v, i) end
    end
    function iter_obj:slice(start, finish)
      local sliced = {}
      start = start or 1
      finish = finish or #t
      for i = start, finish do
        if t[i] ~= nil then table.insert(sliced, t[i]) end
      end
      return create_iter(sliced)
    end
    setmetatable(iter_obj, {
      __call = function()
        local idx = 0
        return function()
          idx = idx + 1
          return t[idx]
        end
      end,
    })
    return iter_obj
  end
  vim.iter = function(list) return create_iter(list or {}) end
end


-- Polyfill vim.system (introduced in Neovim 0.10, used by neogit cli.lua)
if not vim.system then
  vim.system = function(cmd, opts, on_exit)
    if type(opts) == "function" then
      on_exit = opts
      opts = nil
    end
    opts = opts or {}

    local res = vim.fn.systemlist(cmd)
    local exit_code = vim.v.shell_error
    local stdout_str = table.concat(res, "\n")
    if #res > 0 then stdout_str = stdout_str .. "\n" end

    local completed = {
      code = exit_code,
      stdout = stdout_str,
      stderr = "",
      wait = function(self)
        return self
      end,
    }

    if on_exit then
      on_exit(completed)
    end

    return completed
  end
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
  local fallback_query = setmetatable({
    text = "",
    captures = {},
    info = { patterns = {} },
  }, {
    __index = function(_, k)
      if k == "text" then return "" end
      return function() return {} end
    end,
  })

  if vim.treesitter.query then
    for _, fn_name in ipairs({ "get", "get_query", "parse", "parse_query" }) do
      if type(vim.treesitter.query[fn_name]) == "function" then
        local orig_fn = vim.treesitter.query[fn_name]
        vim.treesitter.query[fn_name] = function(...)
          local ok, res = pcall(orig_fn, ...)
          if not ok or res == nil then
            return fallback_query
          end
          return res
        end
      end
    end
  end
end

-- Shim neogit diff_highlights module for Neovim 0.9.5 compatibility
package.loaded["neogit.lib.diff_highlights"] = setmetatable({
  get = function() return {} end,
  attach = function() end,
  detach = function() end,
  setup = function() end,
}, {
  __index = function()
    return function() return {} end
  end,
})





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

-- Shim vim.version() for Neovim 0.10 version checks in modern plugins (like neogit)
if vim.version then
  local orig_version = vim.version
  vim.version = setmetatable({
    major = 0,
    minor = 10,
    patch = 0,
  }, {
    __call = function()
      return { major = 0, minor = 10, patch = 0 }
    end,
    __index = function(t, k)
      if type(orig_version) == "table" and orig_version[k] then
        return orig_version[k]
      end
      return nil
    end,
  })
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

-- Shim vim.api.nvim_set_option_value to remove conflicting 'scope' when 'buf' is present (invalid in 0.9.5)
if vim.api and vim.api.nvim_set_option_value then
  local orig_set_opt = vim.api.nvim_set_option_value
  vim.api.nvim_set_option_value = function(name, value, opts)
    if type(opts) == "table" and opts.buf ~= nil and opts.scope ~= nil then
      local clean_opts = {}
      for k, v in pairs(opts) do
        if k ~= "scope" then clean_opts[k] = v end
      end
      return orig_set_opt(name, value, clean_opts)
    end
    return orig_set_opt(name, value, opts)
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
