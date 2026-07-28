return {
  {
    -- Which-key: press <space> (the leader) and pause - a popup shows every
    -- keybind you can press next. This is how you learn the keymaps without
    -- memorizing docs up front.
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },
  {
    -- Rose Pine (moon variant) - same theme as the WezTerm client, so the
    -- editor and terminal read as one surface.
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    config = function()
      require("rose-pine").setup({ variant = "moon" })
      vim.cmd.colorscheme("rose-pine")
    end,
  },
}
