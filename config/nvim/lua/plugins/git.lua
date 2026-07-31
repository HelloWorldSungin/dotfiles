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

      -- Direct Neogit Worktree Handler Override
      local ok_wt, wt_actions = pcall(require, "neogit.popups.worktree.actions")
      local ok_async, a = pcall(require, "neogit.lib.async")
      if ok_wt and wt_actions and ok_async and a then
        local async_input = a.wrap(function(input_opts, cb)
          vim.ui.input(input_opts, cb)
        end, 2)

        -- w -> W (Create new worktree with new branch)
        wt_actions.create_worktree = a.void(function()
          local git = require("neogit.lib.git")
          local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

          local cwd = (vim.uv or vim.loop).cwd()
          local parent_dir = vim.fs.normalize(cwd .. "/..")
          local default_path = parent_dir .. "/new-worktree"

          -- Step 1: Prompt Worktree Path
          local path = async_input({ prompt = "Worktree path: ", default = default_path })
          if not path or path == "" then return end

          -- Step 2: Prompt Base Branch / Ref
          local branches = git.refs.list_local_branches()
          local remote_branches = git.refs.list_remote_branches()
          local all_refs = {}
          for _, b in ipairs(branches) do table.insert(all_refs, b) end
          for _, b in ipairs(remote_branches) do table.insert(all_refs, b) end

          local start_ref = FuzzyFinderBuffer.new(all_refs):open_async({
            prompt_prefix = "Create and checkout branch starting at",
          })
          if not start_ref or start_ref == "" then return end

          -- Step 3: Prompt New Branch Name
          local default_branch = vim.fs.basename(path)
          if default_branch == "" or default_branch == ".." then default_branch = "new-branch" end
          local branch_name = async_input({ prompt = "Create new branch: ", default = default_branch })
          if not branch_name or branch_name == "" then return end

          -- Execute Git Worktree Creation
          local success, err = git.worktree.add(branch_name, path)
          if not success then
            git.branch.create(branch_name, start_ref)
            success, err = git.worktree.add(branch_name, path)
          end

          if success then
            require("neogit.lib.notification").info("Added worktree: " .. path)
            local status_mod = require("neogit.buffers.status")
            if status_mod.is_open() then
              status_mod.instance():chdir(path)
            end
          else
            require("neogit.lib.notification").error("Failed to create worktree: " .. tostring(err or "unknown error"))
          end
        end)

        -- w -> c (Checkout existing branch in new worktree)
        wt_actions.checkout_worktree = a.void(function()
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
          if not selected_branch or selected_branch == "" then return end

          local cwd = (vim.uv or vim.loop).cwd()
          local default_path = vim.fs.normalize(cwd .. "/..") .. "/" .. vim.fs.basename(selected_branch)

          local path = async_input({ prompt = "Worktree path: ", default = default_path })
          if not path or path == "" then return end

          local success, err = git.worktree.add(selected_branch, path)
          if success then
            require("neogit.lib.notification").info("Added worktree: " .. path)
            local status_mod = require("neogit.buffers.status")
            if status_mod.is_open() then
              status_mod.instance():chdir(path)
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
  {
    -- Git Worktree: interactive worktree switching & creation with Telescope
    "polarmutex/git-worktree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      require("git-worktree").setup({})
      pcall(function()
        require("telescope").load_extension("git_worktree")
      end)
    end,
    keys = {
      {
        "<leader>wm",
        function()
          local ok, telescope = pcall(require, "telescope")
          if ok and telescope.extensions.git_worktree then
            telescope.extensions.git_worktree.git_worktree()
          else
            require("telescope").load_extension("git_worktree")
            require("telescope").extensions.git_worktree.git_worktree()
          end
        end,
        desc = "Git Worktree: Manage / Switch",
      },
      {
        "<leader>wc",
        function()
          local ok, telescope = pcall(require, "telescope")
          if ok and telescope.extensions.git_worktree then
            telescope.extensions.git_worktree.create_git_worktree()
          else
            require("telescope").load_extension("git_worktree")
            require("telescope").extensions.git_worktree.create_git_worktree()
          end
        end,
        desc = "Git Worktree: Create",
      },
    },
  },
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" },
  },
}
