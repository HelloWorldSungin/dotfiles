-- Multi-cursor editing plugins
return {
  {
    -- vim-visual-multi: VS Code-style multi-cursor selection.
    -- Press Ctrl-N on a word to select it and spawn cursors on subsequent matches.
    -- Press Ctrl-Shift-Down / Ctrl-Shift-Up to add cursors directly above or below.
    "mg979/vim-visual-multi",
    event = "BufReadPost",
    init = function()
      vim.g.VM_theme = "nord"
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>",
        ["Find Subword Under"] = "<C-n>",
        ["Select Cursor Down"] = "<C-S-Down>",
        ["Select Cursor Up"] = "<C-S-Up>",
      }
    end,
  },
}
