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

      -- Reliable Neogit Worktree Handler with Debug Logger (/tmp/neogit_worktree.log)
      local ok_wt, wt_actions = pcall(require, "neogit.popups.worktree.actions")
      local ok_async, a = pcall(require, "neogit.lib.async")
      if ok_wt and wt_actions and ok_async and a then
        local function log_debug(msg)
          local f = io.open("/tmp/neogit_worktree.log", "a")
          if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg) .. "\n")
            f:close()
          end
        end

        local async_input = a.wrap(function(opts, cb)
          vim.ui.input(opts, cb)
        end, 2)

        -- w -> W (Create new worktree with new branch)
        wt_actions.create_worktree = a.void(function()
          log_debug("=== Starting create_worktree ===")
          local git = require("neogit.lib.git")
          local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

          local cwd = (vim.uv or vim.loop).cwd()
          local default_path = vim.fs.normalize(cwd .. "/..") .. "/new-worktree"

          log_debug("Step 1: Prompting Worktree Path (default: " .. default_path .. ")")
          local path = async_input({ prompt = "Worktree Path: ", default = default_path })
          log_debug("Step 1 Result: path = " .. tostring(path))

          if not path or path == "" then
            log_debug("Aborting: path was empty or cancelled")
            return
          end

          log_debug("Fetching branch refs for Step 2...")
          local branches = git.refs.list_local_branches()
          local remote_branches = git.refs.list_remote_branches()
          local all_refs = {}
          for _, b in ipairs(branches) do table.insert(all_refs, b) end
          for _, b in ipairs(remote_branches) do table.insert(all_refs, b) end
          log_debug("Step 2: Opening FuzzyFinder with " .. #all_refs .. " refs...")

          local start_ref = FuzzyFinderBuffer.new(all_refs):open_async({
            prompt_prefix = "Start branch/commit at",
          })
          log_debug("Step 2 Result: start_ref = " .. tostring(start_ref))

          if not start_ref then
            log_debug("Aborting: start_ref was empty or cancelled")
            return
          end

          local default_branch = vim.fs.basename(path)
          if default_branch == "" or default_branch == ".." then default_branch = "new-branch" end

          log_debug("Step 3: Prompting New Branch Name (default: " .. default_branch .. ")")
          local branch_name = async_input({ prompt = "New Branch Name: ", default = default_branch })
          log_debug("Step 3 Result: branch_name = " .. tostring(branch_name))

          if not branch_name or branch_name == "" then
            log_debug("Aborting: branch_name was empty or cancelled")
            return
          end

          log_debug("Adding worktree: branch=" .. branch_name .. ", path=" .. path)
          local success, err = git.worktree.add(branch_name, path)
          if not success then
            log_debug("git.worktree.add initial attempt failed, creating branch " .. branch_name .. " at " .. start_ref)
            git.branch.create(branch_name, start_ref)
            success, err = git.worktree.add(branch_name, path)
          end

          log_debug("Worktree Add Result: success=" .. tostring(success) .. ", err=" .. tostring(err))
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
          log_debug("=== Starting checkout_worktree ===")
          local git = require("neogit.lib.git")
          local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

          local branches = git.refs.list_local_branches()
          local remote_branches = git.refs.list_remote_branches()
          local all_refs = {}
          for _, b in ipairs(branches) do table.insert(all_refs, b) end
          for _, b in ipairs(remote_branches) do table.insert(all_refs, b) end

          log_debug("Step 1: Opening FuzzyFinder for branch to checkout (" .. #all_refs .. " refs)...")
          local selected_branch = FuzzyFinderBuffer.new(all_refs):open_async({
            prompt_prefix = "Checkout branch in new worktree",
          })
          log_debug("Step 1 Result: selected_branch = " .. tostring(selected_branch))

          if not selected_branch then
            log_debug("Aborting: selected_branch was empty or cancelled")
            return
          end

          local cwd = (vim.uv or vim.loop).cwd()
          local default_path = vim.fs.normalize(cwd .. "/..") .. "/" .. vim.fs.basename(selected_branch)

          log_debug("Step 2: Prompting Worktree Path (default: " .. default_path .. ")")
          local path = async_input({ prompt = "Worktree Path: ", default = default_path })
          log_debug("Step 2 Result: path = " .. tostring(path))

          if not path or path == "" then
            log_debug("Aborting: path was empty or cancelled")
            return
          end

          log_debug("Adding worktree: branch=" .. selected_branch .. ", path=" .. path)
          local success, err = git.worktree.add(selected_branch, path)
          log_debug("Worktree Add Result: success=" .. tostring(success) .. ", err=" .. tostring(err))

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
