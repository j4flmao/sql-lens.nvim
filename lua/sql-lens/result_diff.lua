local M = {}

M._snapshots = {}

local function hash(sql)
  return sql:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

function M.snapshot(raw, sql)
  local result_ui = require("sql-lens.ui.result")
  local data = result_ui._extract_data(raw)
  if not data then return end

  local key = hash(sql)
  local existing = M._snapshots[key]
  M._snapshots[key] = {
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    headers = data.headers,
    rows = data.rows,
    sql = sql,
  }

  if existing then
    vim.notify("SqlLens: Snapshot updated (previous saved for diff)", vim.log.levels.INFO)
    M._snapshots[key .. "_prev"] = existing
  else
    vim.notify("SqlLens: Snapshot saved — run again to compare", vim.log.levels.INFO)
  end
end

function M.diff(raw, sql)
  local result_ui = require("sql-lens.ui.result")
  local current_data = result_ui._extract_data(raw)
  if not current_data then
    vim.notify("SqlLens: No tabular data to compare", vim.log.levels.WARN)
    return
  end

  local key = hash(sql)
  local prev = M._snapshots[key .. "_prev"] or M._snapshots[key]
  if not prev then
    M.snapshot(raw, sql)
    return
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "  ╔══ Result Diff ══╗")
  table.insert(lines, "")

  local sql_display = sql:gsub("\n", " "):gsub("%s+", " "):sub(1, 80)
  table.insert(lines, "  SQL: " .. sql_display)
  table.insert(lines, "")
  table.insert(lines, "  Before: " .. prev.timestamp .. " (" .. #prev.rows .. " rows)")
  table.insert(lines, "  After:  " .. os.date("%Y-%m-%d %H:%M:%S") .. " (" .. #current_data.rows .. " rows)")
  table.insert(lines, "")

  local row_diff = #current_data.rows - #prev.rows
  if row_diff > 0 then
    table.insert(lines, string.format("  + %d new rows", row_diff))
  elseif row_diff < 0 then
    table.insert(lines, string.format("  − %d removed rows", -row_diff))
  else
    table.insert(lines, "  = Same row count")
  end
  table.insert(lines, "")

  local prev_set = {}
  for _, row in ipairs(prev.rows) do
    prev_set[table.concat(row, "|")] = true
  end
  local curr_set = {}
  for _, row in ipairs(current_data.rows) do
    curr_set[table.concat(row, "|")] = true
  end

  local added = {}
  for _, row in ipairs(current_data.rows) do
    if not prev_set[table.concat(row, "|")] then table.insert(added, row) end
  end
  local removed = {}
  for _, row in ipairs(prev.rows) do
    if not curr_set[table.concat(row, "|")] then table.insert(removed, row) end
  end

  if #added > 0 then
    table.insert(lines, string.format("  ── Added (%d) ──", #added))
    for i, row in ipairs(added) do
      if i > 10 then
        table.insert(lines, string.format("  ... and %d more", #added - 10))
        break
      end
      table.insert(lines, "  + " .. table.concat(row, " | "))
    end
    table.insert(lines, "")
  end

  if #removed > 0 then
    table.insert(lines, string.format("  ── Removed (%d) ──", #removed))
    for i, row in ipairs(removed) do
      if i > 10 then
        table.insert(lines, string.format("  ... and %d more", #removed - 10))
        break
      end
      table.insert(lines, "  − " .. table.concat(row, " | "))
    end
    table.insert(lines, "")
  end

  if #added == 0 and #removed == 0 then
    table.insert(lines, "  ✓ Results are identical")
    table.insert(lines, "")
  end

  M._snapshots[key .. "_prev"] = M._snapshots[key]
  M._snapshots[key] = {
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    headers = current_data.headers,
    rows = current_data.rows,
    sql = sql,
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.5))
  vim.cmd("botright " .. height .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  local ns = vim.api.nvim_create_namespace("sql_lens_rdiff")
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("╔") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("^%s+[+]") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("^%s+[−]") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensError", row, 0, -1)
    elseif line:match("^%s+[=]") or line:match("✓") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("──") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", row, 0, -1)
    end
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

return M
