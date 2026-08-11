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
}
