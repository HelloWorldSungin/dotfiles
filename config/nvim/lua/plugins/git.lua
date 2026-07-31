-- Git inside the editor - review diffs and stage what you trust.
return {
  {
    -- Neogit: full git UI (status, diffs, staging, commits).
    "NeogitOrg/neogit",
    tag = "v1.0.0",
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
      },
    },
    config = function(_, opts)
      require("neogit").setup(opts)

      -- Shim Neogit input module so prepend uses default instead of nvim_input,
      -- fixing compatibility with Snacks.input / vim.ui.input during worktree creation
      local ok, input = pcall(require, "neogit.lib.input")
      if ok and input then
        local orig_get_user_input = input.get_user_input
        input.get_user_input = function(prompt, input_opts)
          input_opts = input_opts or {}
          if input_opts.prepend then
            if not input_opts.default then
              input_opts.default = input_opts.prepend
            end
            input_opts.prepend = nil
          end
          return orig_get_user_input(prompt, input_opts)
        end
      end
    end,
    keys = {
      { "<leader>g", "<cmd>Neogit<cr>", desc = "Neogit (git status/diff/stage)" },
    },
  },
  {
    -- Gitsigns: change markers in the gutter + inline blame on the current line.
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      current_line_blame = true,
    },
  },
}
