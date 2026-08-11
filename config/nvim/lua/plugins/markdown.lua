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
  },
}
