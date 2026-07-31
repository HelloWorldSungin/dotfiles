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
      local function log_debug(msg)
        local f = io.open("/tmp/neogit_debug.log", "a")
        if f then
          f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg) .. "\n")
          f:close()
        end
      end

      -- 1. Shim neogit.lib.input to eliminate pcall coroutine yield bug on Neovim 0.9.5
      local ok_input, neogit_input = pcall(require, "neogit.lib.input")
      if ok_input and neogit_input then
        neogit_input.get_user_input = function(prompt, input_opts)
          log_debug("[INPUT START] prompt=" .. tostring(prompt))
          local a = require("neogit.lib.async")
          local async_input = a.wrap(vim.ui.input, 2)
          input_opts = vim.tbl_extend("keep", input_opts or {}, { strip_spaces = false, separator = ": " })

          local result = async_input({
            prompt = ("%s%s"):format(prompt, input_opts.separator),
            default = input_opts.default or input_opts.prepend,
            cancelreturn = input_opts.cancel,
          })

          log_debug("[INPUT END] prompt=" .. tostring(prompt) .. ", result=" .. tostring(result))
          if not result then return nil end
          if input_opts.strip_spaces then result, _ = result:gsub("%s", "-") end
          if result == "" then return nil end
          return result
        end
      end

      -- 2. Shim neogit.lib.finder to use vim.ui.select for clean snacks.picker integration
      local ok_finder, neogit_finder = pcall(require, "neogit.lib.finder")
      if ok_finder and neogit_finder then
        neogit_finder.find = function(self, on_select)
          log_debug("[FINDER START] prompt=" .. tostring(self.opts.prompt_prefix) .. ", #entries=" .. #self.entries)
          vim.ui.select(self.entries, {
            prompt = string.format("%s", self.opts.prompt_prefix or "Select"),
            format_item = function(entry) return tostring(entry) end,
          }, function(item)
            log_debug("[FINDER SELECTED] item=" .. tostring(item))
            vim.schedule(function()
              on_select(self.opts.allow_multi and { item } or item)
            end)
          end)
        end
      end

      require("neogit").setup(opts)
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
