-- Git inside the editor - review diffs and stage what you trust.
return {
  {
    -- Neogit: full git UI (status, diffs, staging, commits).
    "NeogitOrg/neogit",
    tag = "v1.0.0",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    opts = {
      disable_context_highlighting = true,
      commit_editor = {
        kind = "split",
        show_staged_diff = false,
      },
      console_timeout = 60000,   -- Allow up to 60 seconds for git operations on large repositories
      auto_show_console = false, -- Disable auto-popping NeogitConsole box (press $ inside Neogit to view log manually)
      integrations = {
        snacks = false,          -- Disable Neogit's internal snacks finder wrapper bug on item selection
      },
    },
    keys = {
      { "<leader>g", "<cmd>Neogit<cr>", desc = "Neogit (git status/diff/stage)" },
      { "<leader>gv", "<cmd>Neogit vsplit<cr>", desc = "Neogit (vertical split)" },
      { "<leader>gs", "<cmd>Neogit split<cr>", desc = "Neogit (horizontal split)" },
    },
  },
  {
    -- Diffview: full side-by-side Git file diff & commit history viewer
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  },
  {
    -- Gitsigns: change markers in the gutter + inline blame + change navigation.
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      current_line_blame = true,
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Jump to next/previous git change (hunk)
        map("n", "]c", function()
          if vim.wo.diff then return "]c" end
          vim.schedule(function() gs.next_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Next git change" })

        map("n", "[c", function()
          if vim.wo.diff then return "[c" end
          vim.schedule(function() gs.prev_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Previous git change" })

        -- Git change actions
        map("n", "<leader>h", gs.preview_hunk, { desc = "Preview git change hunk" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview git change hunk" })
        map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage git change hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset git change hunk" })
      end,
    },
  },
  {
    -- Git Worktree: interactive worktree switching & creation with Telescope
    "ThePrimeagen/git-worktree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      local ok, wt = pcall(require, "git-worktree")
      if ok and wt and type(wt.setup) == "function" then
        wt.setup({})
      end
      pcall(function()
        require("telescope").load_extension("git_worktree")
      end)
    end,
    keys = {
      {
        "<leader>wm",
        function()
          local ok_tele, telescope = pcall(require, "telescope")
          if ok_tele then
            pcall(telescope.load_extension, "git_worktree")
            local ext = telescope.extensions and telescope.extensions.git_worktree
            local picker_fn = ext and (ext.git_worktrees or ext.git_worktree)
            if type(picker_fn) == "function" then
              picker_fn({
                attach_mappings = function(prompt_bufnr, map)
                  local actions = require("telescope.actions")
                  local action_state = require("telescope.actions.state")

                  local function safe_delete_worktree(path, force)
                    local worktree = require("git-worktree")
                    local current_cwd = vim.fs.normalize((vim.uv or vim.loop).cwd() or "")
                    local target_path = vim.fs.normalize(path or "")

                    if current_cwd == target_path or current_cwd:find(target_path, 1, true) then
                      local lines = vim.fn.systemlist("git worktree list")
                      local main_path = lines[1] and lines[1]:match("^(%S+)")
                      if main_path and (vim.uv or vim.loop).fs_stat(main_path) and main_path ~= target_path then
                        pcall(vim.api.nvim_set_current_dir, main_path)
                      else
                        local parent = vim.fs.normalize(target_path .. "/..")
                        pcall(vim.api.nvim_set_current_dir, parent)
                      end
                    end

                    worktree.delete_worktree(target_path, force)
                  end

                  map("i", "<C-d>", function()
                    local selection = action_state.get_selected_entry()
                    if selection then
                      actions.close(prompt_bufnr)
                      local path = selection.path or selection.value or selection[1]
                      if path then safe_delete_worktree(path, false) end
                    end
                  end)
                  map("n", "d", function()
                    local selection = action_state.get_selected_entry()
                    if selection then
                      actions.close(prompt_bufnr)
                      local path = selection.path or selection.value or selection[1]
                      if path then safe_delete_worktree(path, false) end
                    end
                  end)
                  return true
                end,
              })
              return
            end
          end
          vim.cmd("Telescope git_worktree git_worktrees")
        end,
        desc = "Git Worktree: Manage / Switch / Delete",
      },
      {
        "<leader>wc",
        function()
          local ok, telescope = pcall(require, "telescope")
          if ok then
            pcall(telescope.load_extension, "git_worktree")
            if telescope.extensions and telescope.extensions.git_worktree then
              telescope.extensions.git_worktree.create_git_worktree()
              return
            end
          end
          vim.cmd("Telescope git_worktree create_git_worktree")
        end,
        desc = "Git Worktree: Create",
      },
    },
  },
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" },
  },
}
