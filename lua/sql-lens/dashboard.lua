local M = {}

---Format bytes to human readable
local function fmt_size(bytes)
  if not bytes or bytes == 0 then return "-" end
  if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
  if bytes >= 1e6 then return string.format("%.1f MB", bytes / 1e6) end
  if bytes >= 1e3 then return string.format("%.1f KB", bytes / 1e3) end
  return string.format("%d B", bytes)
end

---Format number with commas
local function fmt_count(n)
  if not n then return "-" end
  local s = string.format("%d", n)
  local pos = #s % 3
  if pos == 0 then pos = 3 end
  local parts = { s:sub(1, pos) }
  for i = pos + 1, #s, 3 do
    table.insert(parts, s:sub(i, i + 2))
  end
  return table.concat(parts, ",")
end

function M.show()
  local conn_mgr = require("sql-lens.connections")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)

  if not conn then
    vim.notify("SqlLens: No active connection", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Loading table sizes...", vim.log.levels.INFO)

  conn:list_table_sizes(function(err, sizes)
    if err or not sizes or #sizes == 0 then
      -- Fallback: just list tables
      conn:list_tables(function(terr, tables)
        if terr or #tables == 0 then
          vim.notify("SqlLens: No tables found", vim.log.levels.WARN)
          return
        end
        local fallback_sizes = {}
        for _, t in ipairs(tables) do
          table.insert(fallback_sizes, { name = t, row_count = 0, bytes = 0 })
        end
        M._render(fallback_sizes, conn)
      end)
      return
    end
    M._render(sizes, conn)
  end)
end

function M._render(sizes, conn)
  local lines = {}
  local db = conn.config.dbname or conn.config.name or "?"

  table.insert(lines, "")
  table.insert(lines, "  ╔══ Table Size Dashboard ══╗")
  table.insert(lines, "  Database: " .. db)
  table.insert(lines, "")

  -- Aggregate stats
  local total_rows = 0
  local total_bytes = 0
  local max_bytes = 0

  for _, t in ipairs(sizes) do
    total_rows = total_rows + (t.row_count or 0)
    total_bytes = total_bytes + (t.bytes or 0)
    max_bytes = math.max(max_bytes, t.bytes or 0)
  end

  -- Summary
  table.insert(lines, string.format("  %d tables  %s total rows  %s total size",
    #sizes, fmt_count(total_rows), fmt_size(total_bytes)))
  table.insert(lines, "")

  -- Header
  local bar_width = 20
  local name_width = 0
  for _, t in ipairs(sizes) do
    name_width = math.max(name_width, #t.name)
  end
  name_width = math.min(name_width, 25)

  local header = string.format("  %-" .. name_width .. "s  %12s  %10s  %s",
    "Table", "Rows", "Size", "Distribution")
  table.insert(lines, header)
  table.insert(lines, "  " .. string.rep("─", #header - 2))

  -- Rows
  for _, t in ipairs(sizes) do
    local name = t.name or "?"
    if #name > name_width then name = name:sub(1, name_width - 2) .. ".." end

    local bar = ""
    if max_bytes > 0 and (t.bytes or 0) > 0 then
      local ratio = t.bytes / max_bytes
      local len = math.max(1, math.floor(ratio * bar_width))
      bar = string.rep("█", len)
    end

    table.insert(lines, string.format("  %-" .. name_width .. "s  %12s  %10s  %s",
      name, fmt_count(t.row_count), fmt_size(t.bytes), bar))
  end

  table.insert(lines, "")

  -- Display
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.6))
  vim.cmd("botright " .. height .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  local ns = vim.api.nvim_create_namespace("sql_lens_dashboard")
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("╔") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("Database:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", row, 0, -1)
    elseif line:match("^%s+%d+ tables") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("^%s+──") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", row, 0, -1)
    elseif line:match("Table") and line:match("Rows") and line:match("Size") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensWarn", row, 0, -1)
    elseif line:match("█") then
      -- Color based on size relative to max
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    end
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

return M
