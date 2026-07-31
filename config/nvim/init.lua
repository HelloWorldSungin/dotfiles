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

-- Ensure .md files are detected as markdown filetype in Neovim 0.9.5
vim.filetype.add({
  extension = {
    md = "markdown",
  },
})

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


-- Polyfill vim.system (introduced in Neovim 0.10, used by neogit process.lua / cli.lua)
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

    local dummy_handle = {
      is_closing = function() return false end,
      close = function() end,
      is_active = function() return false end,
    }

    local completed = {
      code = exit_code,
      stdout = stdout_str,
      stderr = "",
      pid = 12345,
      handle = dummy_handle,
      wait = function(self)
        return self
      end,
      kill = function(self)
        return self
      end,
      write = function(self)
        return self
      end,
    }

    setmetatable(completed, {
      __index = function(_, k)
        if k == "code" then return exit_code end
        if k == "stdout" then return stdout_str end
        if k == "stderr" then return "" end
        if k == "pid" then return 12345 end
        if k == "handle" then return dummy_handle end
        return function(self) return self end
      end,
    })

    if on_exit then
      vim.schedule(function()
        on_exit(completed)
      end)
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

-- Shim vim.treesitter.language for Neovim 0.9.5 compatibility (suppress no parser errors)
if vim.treesitter then
  vim.treesitter.language = vim.treesitter.language or {}
  local orig_add = vim.treesitter.language.add
  vim.treesitter.language.add = function(lang, opts)
    if orig_add then
      local ok, res = pcall(orig_add, lang, opts)
      if ok then return res end
    end
    return false
  end
  local orig_req = vim.treesitter.language.require_language
  if orig_req then
    vim.treesitter.language.require_language = function(lang, path, silent)
      local ok, res = pcall(orig_req, lang, path, silent)
      if ok then return res end
      return false
    end
  end
end

-- Shim vim.treesitter.query for Neovim 0.9.5 compatibility (where vim.treesitter.query is a function)
if vim.treesitter then
  local orig_query = vim.treesitter.query
  if type(orig_query) == "function" then
    local query_mod = setmetatable({
      get = function(lang, query_name)
        if vim.treesitter.get_query then
          local q = vim.treesitter.get_query(lang, query_name)
          if q then return q end
        end
        local files = vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", lang, query_name), true)
        if #files > 0 then
          local query_text = {}
          for _, f in ipairs(files) do
            local lines = vim.fn.readfile(f)
            if lines and #lines > 0 then
              table.insert(query_text, table.concat(lines, "\n"))
            end
          end
          local text = table.concat(query_text, "\n")
          if #text > 0 and vim.treesitter.parse_query then
            local ok, parsed = pcall(vim.treesitter.parse_query, lang, text)
            if ok and parsed then return parsed end
          end
        end
        return nil
      end,
      get_query = function(lang, query_name)
        if vim.treesitter.get_query then
          local q = vim.treesitter.get_query(lang, query_name)
          if q then return q end
        end
        local files = vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", lang, query_name), true)
        if #files > 0 then
          local query_text = {}
          for _, f in ipairs(files) do
            local lines = vim.fn.readfile(f)
            if lines and #lines > 0 then
              table.insert(query_text, table.concat(lines, "\n"))
            end
          end
          local text = table.concat(query_text, "\n")
          if #text > 0 and vim.treesitter.parse_query then
            local ok, parsed = pcall(vim.treesitter.parse_query, lang, text)
            if ok and parsed then return parsed end
          end
        end
        return nil
      end,
      parse = function(...)
        local ok, res = pcall(vim.treesitter.parse_query or function() return nil end, ...)
        return ok and res or nil
      end,
      parse_query = function(...)
        local ok, res = pcall(vim.treesitter.parse_query or function() return nil end, ...)
        return ok and res or nil
      end,
    }, {
      __call = function(_, ...)
        return orig_query(...)
      end,
      __index = function(t, k)
        return rawget(t, k)
      end,
    })
    vim.treesitter.query = query_mod
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

-- Shim neogit.lib.input to eliminate pcall coroutine yield bug on Neovim 0.9.5
package.preload["neogit.lib.input"] = function()
  local M = {}

  function M.get_confirmation(msg, options)
    options = options or {}
    options.values = options.values or { "&Yes", "&No" }
    options.default = options.default or 1
    return vim.fn.confirm(msg, table.concat(options.values, "\n"), options.default) == 1
  end

  function M.get_permission(msg, options)
    options = options or {}
    options.values = options.values or { "&Yes", "&No" }
    options.default = options.default or 2
    return vim.fn.confirm(msg, table.concat(options.values, "\n"), options.default) == 1
  end

  function M.get_choice(msg, options)
    local choice = vim.fn.confirm(msg, table.concat(options.values, "\n"), options.default)
    vim.cmd("redraw")
    if choice == 0 then choice = options.default end
    return choice
  end

  function M.get_user_input(prompt, opts)
    local a = require("neogit.lib.async")
    local async_input = a.wrap(vim.ui.input, 2)
    opts = vim.tbl_extend("keep", opts or {}, { strip_spaces = false, separator = ": " })

    local result = async_input({
      prompt = ("%s%s"):format(prompt, opts.separator),
      default = opts.default or opts.prepend,
      cancelreturn = opts.cancel,
    })

    if not result then
      return nil
    end

    if opts.strip_spaces then
      result, _ = result:gsub("%s", "-")
    end

    if result == "" then
      return nil
    end

    return result
  end

  function M.get_user_input_blocking(prompt, opts)
    opts = opts or {}
    local result = vim.fn.input({
      prompt = prompt .. (opts.separator or ": "),
      default = opts.default or opts.prepend or "",
      completion = opts.completion,
      cancelreturn = opts.cancel,
    })
    if opts.strip_spaces and result then
      result, _ = result:gsub("%s", "-")
    end
    return result
  end

  return M
end

-- Shim neogit.lib.finder to use vim.ui.select for clean snacks.picker integration
package.preload["neogit.lib.finder"] = function()
  local Finder = {}
  Finder.__index = Finder

  function Finder:new(opts)
    return setmetatable({
      entries = {},
      opts = opts or {},
    }, Finder)
  end

  function Finder.create(opts)
    return Finder:new(opts or {})
  end

  function Finder:add_entries(entries)
    if type(entries) == "table" then
      for _, entry in ipairs(entries) do
        table.insert(self.entries, entry)
      end
    end
    return self
  end

  function Finder:find(on_select)
    vim.ui.select(self.entries, {
      prompt = string.format("%s", self.opts.prompt_prefix or "Select"),
      format_item = function(entry)
        return tostring(entry)
      end,
    }, function(item)
      vim.schedule(function()
        on_select(self.opts.allow_multi and { item } or item)
      end)
    end)
  end

  local a = require("neogit.lib.async")
  Finder.find_async = a.wrap(Finder.find, 2)

  return Finder
end
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
