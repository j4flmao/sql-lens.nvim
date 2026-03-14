local M = {}

function M.pick()
  local conn_mgr = require("sql-lens.connections")
  local picker = require("sql-lens.ui.picker")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)

  if not conn then
    vim.notify("SqlLens: No active connection", vim.log.levels.WARN)
    return
  end

  conn:list_tables(function(err, tables)
    if err or #tables == 0 then
      vim.notify("SqlLens: No tables found", vim.log.levels.WARN)
      return
    end

    local label = conn.type == "mongodb" and "Collection" or "Table"
    picker.open(tables, {
      prompt = "Select " .. label,
      on_select = function(tbl)
        conn:list_columns(tbl, function(cerr, cols)
          if cerr or not cols or #cols == 0 then
            vim.notify("SqlLens: No columns found", vim.log.levels.WARN)
            return
          end
          local col_names = {}
          for _, c in ipairs(cols) do
            local name = c:match("^(%S+)")
            if name then table.insert(col_names, name) end
          end
          M._multi_select(col_names, cols, tbl, conn, bufnr)
        end)
      end,
    })
  end)
end

function M._multi_select(col_names, col_infos, tbl, conn, bufnr)
  local selected = {}
  for i in ipairs(col_names) do selected[i] = false end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local width = 55
  local height = math.min(#col_names + 4, 20)
  local cursor_idx = 1

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Columns: " .. tbl .. " ",
    title_pos = "center",
    footer = { { " Space=toggle  a=all  Enter=generate  q=cancel ", "SqlLensDim" } },
    footer_pos = "center",
  })

  local ns = vim.api.nvim_create_namespace("sql_lens_colpick")

  local function render()
    local lines = {}
    local count = 0
    for i, name in ipairs(col_names) do
      local check = selected[i] and "☑" or "☐"
      local info = col_infos[i]:match("%s+(.+)$") or ""
      local prefix = i == cursor_idx and " ▸ " or "   "
      local line = string.format("%s%s %s  %s", prefix, check, name, info)
      if #line > width then line = line:sub(1, width - 1) .. "…" end
      table.insert(lines, line)
      if selected[i] then count = count + 1 end
    end
    table.insert(lines, "")
    table.insert(lines, string.format("  %d/%d columns selected", count, #col_names))

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i in ipairs(col_names) do
      local row = i - 1
      if i == cursor_idx then
        vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensWarn", row, 0, -1)
      elseif selected[i] then
        vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
      end
    end
    vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", #col_names + 1, 0, -1)
  end

  render()

  local opts = { buffer = buf, noremap = true, nowait = true, silent = true }

  vim.keymap.set("n", "j", function()
    if cursor_idx < #col_names then cursor_idx = cursor_idx + 1; render() end
  end, opts)
  vim.keymap.set("n", "k", function()
    if cursor_idx > 1 then cursor_idx = cursor_idx - 1; render() end
  end, opts)
  vim.keymap.set("n", "<Space>", function()
    selected[cursor_idx] = not selected[cursor_idx]
    if cursor_idx < #col_names then cursor_idx = cursor_idx + 1 end
    render()
  end, opts)
  vim.keymap.set("n", "a", function()
    local all = true
    for i in ipairs(col_names) do
      if not selected[i] then all = false; break end
    end
    for i in ipairs(col_names) do selected[i] = not all end
    render()
  end, opts)
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, opts)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, opts)

  vim.keymap.set("n", "<CR>", function()
    local chosen = {}
    for i, name in ipairs(col_names) do
      if selected[i] then table.insert(chosen, name) end
    end
    vim.api.nvim_win_close(win, true)
    if #chosen == 0 then
      vim.notify("SqlLens: No columns selected", vim.log.levels.WARN)
      return
    end

    local query
    if conn.type == "mongodb" then
      local proj = {}
      for _, c in ipairs(chosen) do table.insert(proj, c .. ": 1") end
      query = string.format("db.%s.find({}, {%s}).limit(50)", tbl, table.concat(proj, ", "))
    elseif conn.type == "sqlserver" then
      query = string.format("SELECT TOP 50\n  %s\nFROM [%s];", table.concat(chosen, ",\n  "), tbl)
    else
      query = string.format("SELECT\n  %s\nFROM %s\nLIMIT 50;", table.concat(chosen, ",\n  "), tbl)
    end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, row, row, false, vim.split(query, "\n"))
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    vim.notify(string.format("SqlLens: Generated SELECT with %d columns", #chosen), vim.log.levels.INFO)
  end, opts)
end

return M
