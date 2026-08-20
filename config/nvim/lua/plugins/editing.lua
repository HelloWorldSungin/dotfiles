-- Editing and search-and-replace plugins
return {
  {
    -- grug-far: modern, interactive visual find-and-replace with live diffs and file filtering
    "MagicDuck/grug-far.nvim",
    opts = { headerMaxWidth = 80 },
    cmd = "GrugFar",
    keys = {
      {
        "<leader>sr",
        function()
          local grug = require("grug-far")
          local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
          grug.open({
            transient = true,
            prefills = {
              filesFilter = ext and ext ~= "" and ("*." .. ext) or nil,
            },
          })
        end,
        mode = { "n", "v" },
        desc = "Search & Replace (grug-far)",
      },
      {
        "<leader>sw",
        function()
          local grug = require("grug-far")
          local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
          grug.open({
            transient = true,
            prefills = {
              search = vim.fn.expand("<cword>"),
              filesFilter = ext and ext ~= "" and ("*." .. ext) or nil,
            },
          })
        end,
        desc = "Search & Replace current word (grug-far)",
      },
      {
        "<leader>sf",
        function()
          local grug = require("grug-far")
          grug.open({
            transient = true,
            prefills = {
              paths = vim.fn.expand("%"),
            },
          })
        end,
        desc = "Search & Replace in current file (grug-far)",
      },
    },
  },
  {
    -- vim-visual-multi: VS Code-style multi-cursor selection.
    -- Press Ctrl-N on a word to select it and spawn cursors on subsequent matches.
    -- Press Ctrl-Shift-Down / Ctrl-Shift-Up to add cursors directly above or below.
    "mg979/vim-visual-multi",
    lazy = false,
    init = function()
      vim.g.VM_theme = "nord"
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>",
        ["Find Subword Under"] = "<C-n>",
        ["Select Cursor Down"] = "<C-S-Down>",
        ["Select Cursor Up"] = "<C-S-Up>",
      }
    end,
  },
  {
    -- nvim-autopairs: automatically insert closing brackets (), [], {}, "", ''
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },
}
