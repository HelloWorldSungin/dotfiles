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

return {
  {
    -- Snacks: a grab-bag of utilities by folke. We use its pickers -
    -- fuzzy-find files, live grep, open buffers - plus nicer notifications
    -- and input prompts.
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      picker = { enabled = true },
      notifier = { enabled = true },
      input = { enabled = true },
    },
    keys = {
      { "<leader>f", function() Snacks.picker.files() end, desc = "Find files" },
      { "<leader>fd", pick_directory_and_open_in_oil, desc = "Find directory & open in Oil" },
      {
        "<leader>s",
        function()
          local ok_tele, builtin = pcall(require, "telescope.builtin")
          if ok_tele and builtin then
            builtin.live_grep()
          else
            local ok_snacks, snacks = pcall(require, "snacks")
            if ok_snacks and snacks.picker then
              snacks.picker.grep()
            end
          end
        end,
        desc = "Grep project",
      },
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
