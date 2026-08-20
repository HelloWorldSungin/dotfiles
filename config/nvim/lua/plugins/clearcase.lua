-- IBM Rational ClearCase / cleartool integration for Neovim
local function get_current_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" or vim.bo.buftype ~= "" then
    vim.notify("ClearCase: Buffer has no valid file path", vim.log.levels.WARN)
    return nil
  end
  return file
end

local function run_cleartool(args, on_success)
  if vim.fn.executable("cleartool") == 0 then
    vim.notify("cleartool command not found on PATH. Make sure ClearCase is loaded/installed.", vim.log.levels.ERROR)
    return
  end

  local cmd = vim.list_extend({ "cleartool" }, args)
  local output = {}
  local errors = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(output, line) end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(errors, line) end
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        local msg = #output > 0 and table.concat(output, "\n") or "ClearCase command completed."
        vim.notify(msg, vim.log.levels.INFO)
        if on_success then on_success(output) end
      else
        local err_msg = #errors > 0 and table.concat(errors, "\n") or ("cleartool failed with exit code " .. code)
        vim.notify(err_msg, vim.log.levels.ERROR)
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start cleartool job", vim.log.levels.ERROR)
  end
end

local function clearcase_checkout()
  local file = get_current_file()
  if not file then return end

  run_cleartool({ "checkout", "-nc", file }, function()
    vim.cmd("checktime")
    vim.cmd("edit!")
  end)
end

local function clearcase_checkin()
  local file = get_current_file()
  if not file then return end

  vim.ui.input({ prompt = "ClearCase Checkin Comment (leave empty for -nc): " }, function(comment)
    if comment == nil then return end -- Cancelled
    local args = { "checkin" }
    if comment == "" then
      table.insert(args, "-nc")
    else
      table.insert(args, "-c")
      table.insert(args, comment)
    end
    table.insert(args, file)

    run_cleartool(args, function()
      vim.cmd("checktime")
      vim.cmd("edit!")
    end)
  end)
end

local function clearcase_uncheckout()
  local file = get_current_file()
  if not file then return end

  vim.ui.select({ "Discard changes (-rm)", "Keep private copy (-keep)", "Cancel" }, {
    prompt = "Uncheckout " .. vim.fn.fnamemodify(file, ":t") .. "?",
  }, function(choice)
    if not choice or choice == "Cancel" then return end
    local flag = choice:find("-rm") and "-rm" or "-keep"
    run_cleartool({ "uncheckout", flag, file }, function()
      vim.cmd("checktime")
      vim.cmd("edit!")
    end)
  end)
end

local function show_floating_output(title, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "clearcase"

  local width = math.min(math.floor(vim.o.columns * 0.8), 120)
  local height = math.min(math.max(#lines + 2, 8), math.floor(vim.o.lines * 0.7))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    title = " " .. title .. " ",
    title_pos = "center",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true, nowait = true })
end

local function clearcase_lsco()
  run_cleartool({ "lsco", "-cview", "-me" }, function(lines)
    if #lines == 0 then
      vim.notify("No checked out elements in current view.", vim.log.levels.INFO)
    else
      show_floating_output("ClearCase: My Checkouts in Current View", lines)
    end
  end)
end

local function clearcase_history()
  local file = get_current_file()
  if not file then return end

  run_cleartool({ "lshistory", file }, function(lines)
    show_floating_output("ClearCase History: " .. vim.fn.fnamemodify(file, ":t"), lines)
  end)
end

local function clearcase_describe()
  local file = get_current_file()
  if not file then return end

  run_cleartool({ "describe", file }, function(lines)
    show_floating_output("ClearCase Describe: " .. vim.fn.fnamemodify(file, ":t"), lines)
  end)
end

local function clearcase_diff()
  local file = get_current_file()
  if not file then return end

  if vim.fn.executable("cleartool") == 1 then
    -- Try graphical diff if DISPLAY is present, otherwise text diff in floating window
    if os.getenv("DISPLAY") ~= nil or os.getenv("WAYLAND_DISPLAY") ~= nil then
      run_cleartool({ "diff", "-graphical", "-pred", file })
    else
      run_cleartool({ "diff", "-pred", file }, function(lines)
        show_floating_output("ClearCase Diff: " .. vim.fn.fnamemodify(file, ":t") .. " (vs Predecessor)", lines)
      end)
    end
  end
end

return {
  {
    -- ClearCase plugin mappings
    "folke/which-key.nvim",
    keys = {
      { "<leader>co", clearcase_checkout, desc = "ClearCase: Checkout current file" },
      { "<leader>ci", clearcase_checkin, desc = "ClearCase: Checkin current file" },
      { "<leader>cu", clearcase_uncheckout, desc = "ClearCase: Uncheckout current file" },
      { "<leader>cd", clearcase_diff, desc = "ClearCase: Diff with predecessor" },
      { "<leader>cl", clearcase_lsco, desc = "ClearCase: List my checkouts in view" },
      { "<leader>ch", clearcase_history, desc = "ClearCase: History of current file" },
      { "<leader>cs", clearcase_describe, desc = "ClearCase: Describe element status" },
    },
  },
}
