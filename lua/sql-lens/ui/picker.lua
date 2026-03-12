local M = {}

local MAX_VISIBLE = 5

---Open a floating picker with search filtering
---@param items string[]
---@param opts { prompt: string, on_select: fun(item: string) }
function M.open(items, opts)
  opts = opts or {}
  local prompt = opts.prompt or "Select:"
  local on_select = opts.on_select or function() end

  local all_items = items
  local filtered = vim.list_slice(all_items, 1, #all_items)
  local cursor_idx = 1
  local scroll_offset = 0
  local query = ""

  -- Window size
  local width = 50
  local height = MAX_VISIBLE + 2 -- prompt + separator + items

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " ",
    title_pos = "center",
  })

  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false

  -- Highlight groups for the picker
  local ns = vim.api.nvim_create_namespace("sql_lens_picker")

  local function render()
    local lines = {}
    local hl_ranges = {}

    -- Line 1: search input
    local input_line = "  " .. query .. "│"
    table.insert(lines, input_line)

    -- Line 2: separator
    table.insert(lines, string.rep("─", width))

    -- Items (with scroll)
    local visible_count = math.min(MAX_VISIBLE, #filtered)
    -- Adjust scroll_offset so cursor is always visible
    if cursor_idx - 1 < scroll_offset then
      scroll_offset = cursor_idx - 1
    elseif cursor_idx > scroll_offset + MAX_VISIBLE then
      scroll_offset = cursor_idx - MAX_VISIBLE
    end

    for i = 1, MAX_VISIBLE do
      local idx = scroll_offset + i
      if idx <= #filtered then
        local prefix = idx == cursor_idx and " ▸ " or "   "
        local line = prefix .. filtered[idx]
        if #line > width then
          line = line:sub(1, width - 1) .. "…"
        end
        table.insert(lines, line)
        if idx == cursor_idx then
          table.insert(hl_ranges, { line = #lines - 1, col_start = 0, col_end = #line })
        end
      else
        table.insert(lines, "")
      end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Apply highlights
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    -- Search input highlight
    vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", 0, 0, -1)
    -- Separator
    vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", 1, 0, -1)
    -- Selected item highlight
    for _, hl in ipairs(hl_ranges) do
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensWarn", hl.line, hl.col_start, hl.col_end)
    end

    -- Scroll indicator
    if #filtered > MAX_VISIBLE then
      local info = string.format(" %d/%d ", cursor_idx, #filtered)
      vim.api.nvim_win_set_config(win, {
        footer = { { info, "SqlLensDim" } },
        footer_pos = "right",
      })
    end
  end

  local function filter()
    if query == "" then
      filtered = vim.list_slice(all_items, 1, #all_items)
    else
      filtered = {}
      local q = query:lower()
      for _, item in ipairs(all_items) do
        if item:lower():find(q, 1, true) then
          table.insert(filtered, item)
        end
      end
    end
    cursor_idx = 1
    scroll_offset = 0
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function confirm()
    if #filtered > 0 and cursor_idx <= #filtered then
      local item = filtered[cursor_idx]
      close()
      on_select(item)
    end
  end

  render()

  -- Keymaps
  local key_opts = { buffer = buf, noremap = true, nowait = true, silent = true }

  vim.keymap.set("n", "<Esc>", close, key_opts)
  vim.keymap.set("n", "q", close, key_opts)

  vim.keymap.set("n", "<CR>", confirm, key_opts)

  vim.keymap.set("n", "j", function()
    if cursor_idx < #filtered then
      cursor_idx = cursor_idx + 1
      render()
    end
  end, key_opts)

  vim.keymap.set("n", "k", function()
    if cursor_idx > 1 then
      cursor_idx = cursor_idx - 1
      render()
    end
  end, key_opts)

  vim.keymap.set("n", "<Down>", function()
    if cursor_idx < #filtered then
      cursor_idx = cursor_idx + 1
      render()
    end
  end, key_opts)

  vim.keymap.set("n", "<Up>", function()
    if cursor_idx > 1 then
      cursor_idx = cursor_idx - 1
      render()
    end
  end, key_opts)

  vim.keymap.set("n", "<C-d>", function()
    cursor_idx = math.min(cursor_idx + MAX_VISIBLE, #filtered)
    render()
  end, key_opts)

  vim.keymap.set("n", "<C-u>", function()
    cursor_idx = math.max(cursor_idx - MAX_VISIBLE, 1)
    render()
  end, key_opts)

  -- Typing characters to filter
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
  for i = 1, #chars do
    local ch = chars:sub(i, i)
    vim.keymap.set("n", ch, function()
      query = query .. ch
      filter()
      render()
    end, key_opts)
  end

  vim.keymap.set("n", "<BS>", function()
    if #query > 0 then
      query = query:sub(1, -2)
      filter()
      render()
    end
  end, key_opts)

  vim.keymap.set("n", "<C-w>", function()
    query = ""
    filter()
    render()
  end, key_opts)
end

return M
