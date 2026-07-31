-- Git inside the editor - review diffs and stage what you trust.
return {
  {
    -- Neogit: full git UI (status, diffs, staging, commits).
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    opts = {
      disable_context_highlighting = true,
      commit_editor = {
        kind = "split",
        show_staged_diff = false,
      },
      console_timeout = 60000,   -- Allow up to 60 seconds for git operations on large repositories
      auto_show_console = false, -- Disable auto-popping NeogitConsole box (press $ inside Neogit to view log manually)
      integrations = {
        snacks = false,          -- Disable Neogit's internal snacks finder wrapper bug on item selection
        diffview = false,        -- Use Neogit's native built-in diff buffer to prevent diffview adapter errors
      },
    },
    keys = {
      { "<leader>g", "<cmd>Neogit<cr>", desc = "Neogit (git status/diff/stage)" },
      { "<leader>gv", "<cmd>Neogit kind=vsplit<cr>", desc = "Neogit (vertical split)" },
      { "<leader>g-", "<cmd>Neogit kind=split<cr>", desc = "Neogit (horizontal split)" },
    },
  },
  {
    -- Diffview: full side-by-side Git file diff & commit history viewer
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  },
  {
    -- Gitsigns: change markers in the gutter + inline blame + change navigation.
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      current_line_blame = true,
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Jump to next/previous git change (hunk)
        map("n", "]c", function()
          if vim.wo.diff then return "]c" end
          vim.schedule(function() gs.next_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Next git change" })

        map("n", "[c", function()
          if vim.wo.diff then return "[c" end
          vim.schedule(function() gs.prev_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Previous git change" })

        -- Git change actions
        map("n", "<leader>h", gs.preview_hunk, { desc = "Preview git change hunk" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview git change hunk" })
        map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage git change hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset git change hunk" })
        map("n", "<leader>hw", gs.toggle_ignore_whitespace, { desc = "Toggle ignore whitespace in git diff" })
      end,
    },
  },
}
