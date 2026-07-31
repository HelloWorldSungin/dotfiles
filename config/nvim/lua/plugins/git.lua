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
    config = function(_, opts)
      require("neogit").setup(opts)

      -- Reliable Neogit Worktree Creation & Checkout Handler (Coroutines)
      local ok_wt, wt_actions = pcall(require, "neogit.popups.worktree.actions")
      local ok_async, a = pcall(require, "neogit.lib.async")
      if ok_wt and wt_actions and ok_async and a then
        -- w -> W (Create new worktree with new branch)
        wt_actions.create_worktree = a.void(function()
          local input = require("neogit.lib.input")
          local git = require("neogit.lib.git")
          local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

          local cwd = (vim.uv or vim.loop).cwd()
          local default_path = vim.fs.normalize(cwd .. "/..") .. "/new-worktree"

          local path = input.get_user_input("Worktree Path", {
            default = default_path,
          })
          if not path or path == "" then return end

          local branches = git.refs.list_local_branches()
          local remote_branches = git.refs.list_remote_branches()
          local all_refs = {}
          for _, b in ipairs(branches) do table.insert(all_refs, b) end
          for _, b in ipairs(remote_branches) do table.insert(all_refs, b) end

          local start_ref = FuzzyFinderBuffer.new(all_refs):open_async({
            prompt_prefix = "Start branch/commit at",
          })
          if not start_ref then return end

          local default_branch = vim.fs.basename(path)
          if default_branch == "" or default_branch == ".." then default_branch = "new-branch" end

          local branch_name = input.get_user_input("New Branch Name", {
            default = default_branch,
            strip_spaces = true,
          })
          if not branch_name or branch_name == "" then return end

          local success, err = git.worktree.add(branch_name, path)
          if not success then
            git.branch.create(branch_name, start_ref)
            success, err = git.worktree.add(branch_name, path)
          end

          if success then
            require("neogit.lib.notification").info("Added worktree: " .. path)
            local status = require("neogit.buffers.status")
            if status.is_open() then
              status.instance():chdir(path)
            end
          else
            require("neogit.lib.notification").error("Failed to create worktree: " .. tostring(err or "unknown error"))
          end
        end)

        -- w -> c (Checkout existing branch in new worktree)
        wt_actions.checkout_worktree = a.void(function()
          local input = require("neogit.lib.input")
          local git = require("neogit.lib.git")
          local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

          local branches = git.refs.list_local_branches()
          local remote_branches = git.refs.list_remote_branches()
          local all_refs = {}
          for _, b in ipairs(branches) do table.insert(all_refs, b) end
          for _, b in ipairs(remote_branches) do table.insert(all_refs, b) end

          local selected_branch = FuzzyFinderBuffer.new(all_refs):open_async({
            prompt_prefix = "Checkout branch in new worktree",
          })
          if not selected_branch then return end

          local cwd = (vim.uv or vim.loop).cwd()
          local default_path = vim.fs.normalize(cwd .. "/..") .. "/" .. vim.fs.basename(selected_branch)
          local path = input.get_user_input("Worktree Path", {
            default = default_path,
          })
          if not path or path == "" then return end

          local success, err = git.worktree.add(selected_branch, path)
          if success then
            require("neogit.lib.notification").info("Added worktree: " .. path)
            local status = require("neogit.buffers.status")
            if status.is_open() then
              status.instance():chdir(path)
            end
          else
            require("neogit.lib.notification").error("Failed to checkout worktree: " .. tostring(err or "unknown error"))
          end
        end)
      end
    end,
    keys = {
      { "<leader>g", "<cmd>Neogit<cr>", desc = "Neogit (git status/diff/stage)" },
    },
  },
  {
    -- Gitsigns: change markers in the gutter + inline blame on the current line.
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      current_line_blame = true,
    },
  },
}
