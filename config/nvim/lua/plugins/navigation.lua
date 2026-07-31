-- Finding and jumping to things. See docs/cheatsheet.md for the keybinds.
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
      },
      notifier = { enabled = false }, -- Disabled for Neovim 0.9.5 compatibility
      input = { enabled = true },
    },
    keys = {
      { "<leader>f", function() Snacks.picker.files() end, desc = "Find files" },
      { "<leader>s", function() Snacks.picker.grep() end, desc = "Grep project" },
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
        ["s"] = "actions.select_split",
      },
    },
    keys = {
      { "<leader>e", "<cmd>Oil<cr>", desc = "File explorer (oil)" },
    },
  },
}
