-- Markdown rendering and Treesitter parsing
return {
  {
    -- Treesitter: syntax highlighting and AST parser generator.
    "nvim-treesitter/nvim-treesitter",
    priority = 1000,
    lazy = false,
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "markdown", "markdown_inline", "lua", "vim", "bash", "json", "yaml" },
    },
  },
  {
    -- Render Markdown: disabled on Neovim 0.9.5 work server to prevent missing C parser errors
    "MeanderingProgrammer/render-markdown.nvim",
    enabled = false,
  },
  {
    -- img-clip.nvim: paste screenshot images directly from clipboard into markdown
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    opts = {
      default = {
        embed_image_as_base64 = false,
        prompt_for_file_name = false,
        drag_and_drop = {
          insert_mode = true,
        },
      },
    },
    keys = {
      { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
      { "<C-S-v>", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
      { "<D-S-v>", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
      { "<D-v>", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
    },
  },
}
