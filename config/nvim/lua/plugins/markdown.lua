-- Markdown rendering: pretty-view markdown files in Neovim instead of
-- staring at raw markup. Treesitter is mandatory per the plugin's docs;
-- the icon provider is optional (we skip it - nvim-web-devicons isn't
-- installed and adding it just for the optional language icon isn't worth
-- the dependency).
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    -- Defaults are fine: render in normal/command/terminal modes on the
    -- 'markdown' filetype, modal toggle between rendered and raw.
    opts = {},
  },
}
