local M = {}

local MAX_VISIBLE = 5
local PREVIEW_LINES = 4

---Open a floating picker with search filtering and optional preview
---@param items string[]
---@param opts { prompt: string, on_select: fun(item: string), details?: string[], on_tab?: fun() }
function M.open(items, opts)
  opts = opts or {}
  local prompt = opts.prompt or "Select:"
  local on_select = opts.on_select or function() end
  local on_tab = opts.on_tab
  local details = opts.details  -- parallel array: details[i] = full text for items[i]

  local all_items = items
  local filtered = {}       -- { idx, label } pairs
  local cursor_idx = 1
  local scroll_offset = 0
  local query = ""
  local has_preview = details ~= nil

  -- Build initial filtered list with original indices
  local function rebuild_filtered()
    filtered = {}
    if query == "" then
      for i, item in ipairs(all_items) do
        table.insert(filtered, { idx = i, label = item })
      end
    else
      local q = query:lower()
      for i, item in ipairs(all_items) do
        if item:lower():find(q, 1, true) then
          table.insert(filtered, { idx = i, label = item })
        end
      end
    end
  end
  rebuild_filtered()

  -- Window size
  local width = has_preview and 70 or 50
  local height = MAX_VISIBLE + 2 -- prompt + separator + items
  if has_preview then
    height = height + 1 + PREVIEW_LINES -- separator + preview
  end

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

  local ns = vim.api.nvim_create_namespace("sql_lens_picker")

  local function render()
    local lines = {}
    local hl_ranges = {}

    -- Line 1: search input
    table.insert(lines, "  " .. query .. "│")

    -- Line 2: separator
    table.insert(lines, string.rep("─", width))

    -- Adjust scroll
    if cursor_idx - 1 < scroll_offset then
      scroll_offset = cursor_idx - 1
    elseif cursor_idx > scroll_offset + MAX_VISIBLE then
      scroll_offset = cursor_idx - MAX_VISIBLE
    end

    -- Items
    for i = 1, MAX_VISIBLE do
      local idx = scroll_offset + i
      if idx <= #filtered then
        local prefix = idx == cursor_idx and " ▸ " or "   "
        local line = prefix .. filtered[idx].label
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

    -- Preview pane
    if has_preview then
      table.insert(lines, string.rep("─", width))
      local preview_start = #lines

      local detail_text = ""
      if #filtered > 0 and cursor_idx <= #filtered then
        local orig_idx = filtered[cursor_idx].idx
        detail_text = details[orig_idx] or ""
      end

      -- Split detail into lines and show up to PREVIEW_LINES
      local detail_lines = vim.split(detail_text, "\n")
      for i = 1, PREVIEW_LINES do
        if detail_lines[i] then
          local dl = "  " .. detail_lines[i]
          if #dl > width then dl = dl:sub(1, width - 1) .. "…" end
          table.insert(lines, dl)
        else
          table.insert(lines, "")
        end
      end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Highlights
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", 1, 0, -1)
    for _, hl in ipairs(hl_ranges) do
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensWarn", hl.line, hl.col_start, hl.col_end)
    end
    -- Preview separator + text highlight
    if has_preview then
      local sep_line = MAX_VISIBLE + 2
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", sep_line, 0, -1)
      for i = 1, PREVIEW_LINES do
        vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", sep_line + i, 0, -1)
      end
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
    rebuild_filtered()
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
      local item = filtered[cursor_idx].label
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

  if on_tab then
    vim.keymap.set("n", "<Tab>", function()
      close()
      vim.schedule(on_tab)
    end, key_opts)
  end

  vim.keymap.set("n", "j", function()
    if cursor_idx < #filtered then cursor_idx = cursor_idx + 1; render() end
  end, key_opts)

  vim.keymap.set("n", "k", function()
    if cursor_idx > 1 then cursor_idx = cursor_idx - 1; render() end
  end, key_opts)

  vim.keymap.set("n", "<Down>", function()
    if cursor_idx < #filtered then cursor_idx = cursor_idx + 1; render() end
  end, key_opts)

  vim.keymap.set("n", "<Up>", function()
    if cursor_idx > 1 then cursor_idx = cursor_idx - 1; render() end
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
