-- Git inside the editor - the main reason to open nvim in the agent era is
-- reviewing diffs and staging what you trust.
return {
  {
    -- Neogit: full git UI (status, diffs, staging, commits). The main tool
    -- for reviewing what an agent changed before it gets committed.
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    keys = {
      { "<leader>g", "<cmd>Neogit<cr>", desc = "Neogit (git status/diff/stage)" },
    },
  },
  {
    -- Gitsigns: change markers in the gutter + inline blame on the current
    -- line, so you always see who/what last touched the code under cursor.
    "lewis6991/gitsigns.nvim",
    event = "BufWinEnter", -- lazy-load only when a buffer is actually opened
    opts = {
      current_line_blame = true,
    },
  },
}
