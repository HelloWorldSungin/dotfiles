-- Entry point. Kept tiny on purpose: each concern lives in its own module
-- under lua/ (Kun's structure). Load order: options -> keymaps -> plugins.
require("vim-config")
require("keys")

-- Bootstrap the lazy.nvim plugin manager if it isn't installed yet.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  local ok, lock = pcall(function()
    return vim.fn.json_decode(table.concat(vim.fn.readfile(lockfile), "\n"))
  end)
  local commit = ok and type(lock) == "table" and type(lock["lazy.nvim"]) == "table"
    and lock["lazy.nvim"].commit or nil
  assert(type(commit) == "string" and #commit == 40 and commit:match("^[0-9a-f]+$"), "Invalid lazy.nvim lock commit")
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--no-checkout", "https://github.com/folke/lazy.nvim.git", lazypath })
  assert(vim.v.shell_error == 0, "Failed to clone lazy.nvim")
  vim.fn.system({ "git", "-C", lazypath, "checkout", "--detach", commit })
  assert(vim.v.shell_error == 0, "Failed to check out locked lazy.nvim commit")
end
vim.opt.rtp:prepend(lazypath)

-- Load every file in lua/plugins/ as a plugin spec.
require("lazy").setup("plugins")
