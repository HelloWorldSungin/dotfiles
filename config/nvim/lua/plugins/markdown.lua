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
    -- Render Markdown: pretty-view markdown files in Neovim instead of raw text.
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      enabled = true,
      file_types = { "markdown" },
      render_modes = { "n", "v", "ic", "c" },
    },
    config = function(_, opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function()
          vim.opt_local.conceallevel = 2
        end,
      })
      pcall(require("render-markdown").setup, opts)
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
