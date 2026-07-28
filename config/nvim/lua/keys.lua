-- Global keybinds that aren't tied to a plugin. Plugin keybinds live in
-- their plugin spec under lua/plugins/ so each file is self-contained.

-- Esc saves. You press Esc to leave insert mode anyway, and that's exactly
-- the moment you want to save - so spamming Esc after an edit just works.
vim.keymap.set("n", "<Esc>", "<cmd>silent! w<cr>", { desc = "Save file" })

-- Ctrl-A selects all, like every other editor.
vim.keymap.set("n", "<C-a>", "ggVG", { desc = "Select all" })

-- Pasting over a selection normally clobbers the clipboard with the text
-- you just replaced (vim register behavior). This keeps the clipboard
-- intact so you can paste the same thing repeatedly.
vim.keymap.set("x", "p", '"_dP', { desc = "Paste without clobbering clipboard" })

-- Ctrl+Shift+V pastes system clipboard in insert, command, and normal modes
vim.keymap.set({ "i", "c" }, "<C-S-v>", "<C-r>+", { desc = "Paste system clipboard" })
vim.keymap.set("n", "<C-S-v>", '"+p', { desc = "Paste system clipboard" })

-- Ctrl+Shift+C copies selection to system clipboard in visual mode
vim.keymap.set("v", "<C-S-c>", '"+y', { desc = "Copy selection to system clipboard" })

-- Toggle spell check on/off
vim.keymap.set("n", "<leader>us", "<cmd>set spell!<cr>", { desc = "Toggle spell check" })

