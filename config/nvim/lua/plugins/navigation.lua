-- Finding and jumping to things. See docs/cheatsheet.md for the keybinds.

local function pick_directory_and_open_in_oil()
  local ok_oil, oil = pcall(require, "oil")
  local ok_tele, builtin = pcall(require, "telescope.builtin")
  if ok_tele and builtin then
    local cmd = vim.fn.executable("fd") == 1 and { "fd", "--type", "d", "--hidden", "--exclude", ".git" }
      or { "find", ".", "-type", "d", "-not", "-path", "*/.*" }
    builtin.find_files({
      prompt_title = "Find Directories (Oil)",
      find_command = cmd,
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          local path = selection and (selection.path or selection.value or selection[1])
          if path then
            if ok_oil then
              local ok = pcall(oil.open, path)
              if not ok then pcall(vim.cmd, "edit! " .. vim.fn.fnameescape(path)) end
            else
              pcall(vim.cmd, "edit! " .. vim.fn.fnameescape(path))
            end
          end
        end)
        return true
      end,
    })
  else
    vim.notify("Telescope plugin is required for directory search", vim.log.levels.WARN)
  end
end

<<<<<<< HEAD
local _is_rg_working = nil
local function is_working_ripgrep()
  if _is_rg_working ~= nil then return _is_rg_working end

  local candidates = {
    vim.fn.expand("~/.local/bin/rg"),
    vim.fn.expand("~/bin/rg"),
    "rg",
    vim.fn.expand("~/bin/ripgrep"),
    vim.fn.expand("~/.local/bin/ripgrep"),
    vim.fn.expand("~/bin/rg-real"),
    vim.fn.expand("~/.local/bin/rg-real"),
  }
  for _, bin in ipairs(candidates) do
    if vim.fn.executable(bin) == 1 then
      local out = vim.fn.system(vim.fn.shellescape(bin) .. " --version")
      if vim.v.shell_error == 0 and out:find("ripgrep") then
        _is_rg_working = bin
        return _is_rg_working
      end
    end
  end

  _is_rg_working = false
  return _is_rg_working
end

-- Prepend working ripgrep path to Neovim PATH environment variable
local rg_bin = is_working_ripgrep()
if rg_bin then
  local bin_dir = vim.fn.fnamemodify(rg_bin, ":h")
  if bin_dir and bin_dir ~= "" and bin_dir ~= "." and not vim.env.PATH:find(bin_dir, 1, true) then
    vim.env.PATH = bin_dir .. ":" .. vim.env.PATH
  end
end

local function work_server_live_grep()
  local ok_tele, builtin = pcall(require, "telescope.builtin")
  if not (ok_tele and builtin) then return end

  local function custom_vimgrep_entry_maker()
    return function(line)
      if not line or type(line) ~= "string" or line == "" then return nil end

      local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
      if not file then
        file, lnum, text = line:match("^(.-):(%d+):(.*)$")
        col = "1"
      end

      if not file or file == "" then return nil end

      return {
        value = line,
        ordinal = file .. " " .. (text or ""),
        display = file .. ":" .. lnum .. ":" .. (text or ""),
        filename = file,
        lnum = tonumber(lnum) or 1,
        col = tonumber(col) or 1,
        text = text or "",
      }
    end
  end

  local cmd
  if rg_bin then
    cmd = {
      rg_bin,
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--smart-case",
      "--hidden",
      "--no-ignore-vcs",
      "--glob=!.git/*",
    }
  elseif vim.fn.isdirectory(".git") == 1 or (vim.fn.executable("git") == 1 and vim.fn.system("git rev-parse --is-inside-work-tree"):find("true")) then
    cmd = { "git", "grep", "-n", "-I", "--no-color" }
  else
    cmd = { "grep", "-HnriI", "--exclude-dir=.git" }
  end

  builtin.live_grep({
    vimgrep_arguments = cmd,
    entry_maker = custom_vimgrep_entry_maker(),
  })
end

local function grep_by_extension()
  vim.ui.input({ prompt = "Filter by file extension (e.g. vhd, py, ts): " }, function(ext)
    if not ext or ext == "" then return end
    ext = ext:gsub("^%*%.", ""):gsub("^%.", "")
    local pattern = "*." .. ext

    local rg_bin = is_working_ripgrep()
    local ok_tele, builtin = pcall(require, "telescope.builtin")
    if ok_tele and builtin then
      local cmd
      if rg_bin then
        cmd = {
          rg_bin,
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
          "--hidden",
          "--no-ignore-vcs",
          "--glob=" .. pattern,
          "--glob=!.git/*",
        }
      elseif vim.fn.isdirectory(".git") == 1 or (vim.fn.executable("git") == 1 and vim.fn.system("git rev-parse --is-inside-work-tree"):find("true")) then
        cmd = { "git", "grep", "-n", "-I", "--no-color" }
      else
        cmd = { "grep", "-HnriI", "--exclude-dir=.git" }
      end

      local function custom_vimgrep_entry_maker()
        return function(line)
          if not line or type(line) ~= "string" or line == "" then return nil end
          local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
          if not file then
            file, lnum, text = line:match("^(.-):(%d+):(.*)$")
            col = "1"
          end
          if not file or file == "" then return nil end
          return {
            value = line,
            ordinal = file .. " " .. (text or ""),
            display = file .. ":" .. lnum .. ":" .. (text or ""),
            filename = file,
            lnum = tonumber(lnum) or 1,
            col = tonumber(col) or 1,
            text = text or "",
          }
        end
      end

      builtin.live_grep({
        vimgrep_arguments = cmd,
        entry_maker = custom_vimgrep_entry_maker(),
      })
      return
    end

    local ok_snacks, snacks = pcall(require, "snacks")
    if ok_snacks and snacks.picker then
      snacks.picker.grep({ glob = pattern })
    end
  end)
end

local function quickfix_replace()
  local qf_list = vim.fn.getqflist()
  if #qf_list == 0 then
    vim.notify("Quickfix list is empty. Run <leader>s and press <Ctrl-q> first!", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Find text to replace in Quickfix: " }, function(target)
    if not target or target == "" then return end
    vim.ui.input({ prompt = "Replace with: " }, function(replacement)
      if replacement == nil then return end
      local cmd = string.format("cfdo %%s/%s/%s/g | update", vim.fn.escape(target, "/"), vim.fn.escape(replacement, "/"))
      local ok, err = pcall(vim.cmd, cmd)
      if ok then
        vim.notify(string.format("Replaced '%s' -> '%s' across quickfix files", target, replacement), vim.log.levels.INFO)
      else
        vim.notify("Replace failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function toggle_quickfix()
  local qf_open = false
  for _, win in ipairs(vim.fn.getwininfo()) do
    if win.quickfix == 1 then
      qf_open = true
      break
    end
  end
  if qf_open then
    vim.cmd("cclose")
  else
    vim.cmd("copen")
  end
end

return {
  {
    -- Snacks: a grab-bag of utilities by folke. We use its pickers -
    -- fuzzy-find files, live grep, open buffers - plus nicer notifications
    -- and input prompts.
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        icons = {
          files = { enabled = false },
        },
        sources = {
          grep = rg_bin and { cmd = rg_bin } or nil,
        },
      },
      notifier = { enabled = false }, -- Disabled for Neovim 0.9.5 compatibility
      input = { enabled = true },
    },
    keys = {
      { "<leader>f", function() Snacks.picker.files() end, desc = "Find files" },
      { "<leader>fd", pick_directory_and_open_in_oil, desc = "Find directory & open in Oil" },
      { "<leader>s", work_server_live_grep, desc = "Grep project" },
      { "<leader>se", grep_by_extension, desc = "Grep by file extension (e.g. vhd)" },
      { "<leader>sr", quickfix_replace, desc = "Search & replace in Quickfix" },
      { "<leader>q", toggle_quickfix, desc = "Toggle Quickfix window" },
      { "<leader>b", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "gd", function() Snacks.picker.lsp_definitions() end, desc = "Goto definition" },
    },
  },
  {
    -- Oil: the file tree as an editable buffer. Replaces netrw for directory browsing.
    "stevearc/oil.nvim",
    lazy = false,
    opts = {
      default_file_explorer = true,
      lsp_file_methods = { enabled = false },
      columns = {}, -- Clean ASCII file list without missing icon boxes
      view_options = { show_hidden = true },
      keymaps = {
        ["<C-v>"] = "actions.select_vsplit",
        ["<C-s>"] = "actions.select_split",
        ["v"] = "actions.select_vsplit",
        ["-"] = "actions.select_split",
        ["f"] = pick_directory_and_open_in_oil,
        ["<C-f>"] = pick_directory_and_open_in_oil,
      },
    },
    keys = {
      { "<leader>e", "<cmd>Oil<cr>", desc = "File explorer (oil)" },
    },
  },
}
