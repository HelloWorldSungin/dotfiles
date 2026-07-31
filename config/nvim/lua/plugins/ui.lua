return {
  {
    -- Which-key: press <space> (the leader) and pause - a popup shows every
    -- keybind you can press next. This is how you learn the keymaps without
    -- memorizing docs up front.
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      icons = {
        breadcrumb = ">>",
        separator = "->",
        group = "+",
        mappings = false,
        rules = false,
      },
    },
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
  {
    -- Codewindow: VS Code-style code minimap on the right side
    "gorbit99/codewindow.nvim",
    config = function()
      local ok, codewindow = pcall(require, "codewindow")
      if ok and codewindow then
        codewindow.setup({
          active_in_term = false,
          auto_enable = false,
          exclude_filetypes = { "oil", "neogitstatus", "help", "NvimTree", "snacks_picker_input" },
          side = "right",
          width = 14,
        })
      end
    end,
    keys = {
      {
        "<leader>um",
        function()
          local ok, codewindow = pcall(require, "codewindow")
          if ok and codewindow then
            codewindow.toggle_minimap()
          end
        end,
        desc = "Toggle code minimap",
      },
    },
  },
}
