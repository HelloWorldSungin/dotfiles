-- Markdown rendering and Treesitter parsing
return {
  {
    -- Treesitter: syntax highlighting and AST parser generator.
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "markdown", "markdown_inline", "lua", "vim", "bash", "json", "yaml" },
    },
  },
  {
    -- Render Markdown: pretty-view markdown files in Neovim instead of raw text.
    "MeanderingProgrammer/render-markdown.nvim",
    tag = "v5.0.0",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      enabled = true,
      file_types = { "markdown" },
      render_modes = true,
    },
    init = function()
      vim.opt.conceallevel = 2
    end,
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
