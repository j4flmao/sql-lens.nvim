local M = {}

M._file = vim.fn.stdpath("data") .. "/sql-lens-cost-trend.json"
M._data = nil  -- lazy loaded

function M._load()
  if M._data then return end
  local f = io.open(M._file, "r")
  if not f then M._data = {}; return end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  M._data = (ok and type(data) == "table") and data or {}
end

function M._save()
  if not M._data then return end
  local ok, json = pcall(vim.json.encode, M._data)
  if not ok then return end
  local f = io.open(M._file, "w")
  if not f then return end
  f:write(json)
  f:close()
end

---Generate a simple hash for a SQL query (normalize whitespace)
function M._hash(sql)
  local normalized = sql:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local h = 0
  for i = 1, #normalized do
    h = (h * 31 + normalized:byte(i)) % 2147483647
  end
  return tostring(h)
end

---Record a cost measurement for a query
function M.record(sql, cost, execution_time, connection_name)
  M._load()
  local key = M._hash(sql)
  if not M._data[key] then
    M._data[key] = {
      sql_preview = sql:gsub("%s+", " "):sub(1, 80),
      entries = {},
    }
  end
  table.insert(M._data[key].entries, {
    cost = cost,
    time = execution_time,
    connection = connection_name or "",
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    epoch = os.time(),
  })
  -- Keep last 50 entries per query
  local entries = M._data[key].entries
  if #entries > 50 then
    local trimmed = {}
    for i = #entries - 49, #entries do
      table.insert(trimmed, entries[i])
    end
    M._data[key].entries = trimmed
  end
  M._save()
end

---Get trend for a query: returns { direction, percentage, latest, previous, entries }
function M.get_trend(sql)
  M._load()
  local key = M._hash(sql)
  local data = M._data[key]
  if not data or #data.entries < 2 then
    return nil
  end

  local entries = data.entries
  local latest = entries[#entries]
  local previous = entries[#entries - 1]

  local trend = {
    entries = entries,
    latest = latest,
    previous = previous,
    sql_preview = data.sql_preview,
  }

  if latest.cost and previous.cost and previous.cost > 0 then
    local change = ((latest.cost - previous.cost) / previous.cost) * 100
    trend.cost_change = change
    if change > 5 then
      trend.direction = "up"
    elseif change < -5 then
      trend.direction = "down"
    else
      trend.direction = "stable"
    end
  end

  if latest.time and previous.time and previous.time > 0 then
    local change = ((latest.time - previous.time) / previous.time) * 100
    trend.time_change = change
  end

  return trend
end

---Format trend as a short string for virtual text
function M.trend_text(trend)
  if not trend then return nil end
  local parts = {}
  if trend.direction == "up" then
    parts = { "📈" }
    if trend.cost_change then
      table.insert(parts, string.format("cost +%.0f%%", trend.cost_change))
    end
  elseif trend.direction == "down" then
    parts = { "📉" }
    if trend.cost_change then
      table.insert(parts, string.format("cost %.0f%%", trend.cost_change))
    end
  else
    parts = { "📊 stable" }
  end
  if trend.time_change and trend.latest.time then
    local arrow = trend.time_change > 5 and "↑" or trend.time_change < -5 and "↓" or "→"
    table.insert(parts, string.format("time %s%dms", arrow, trend.latest.time))
  end
  return table.concat(parts, " ")
end

---Show full trend history in a float
function M.show_trend(sql)
  local trend = M.get_trend(sql)
  if not trend then
    vim.notify("SqlLens: No cost history for this query", vim.log.levels.INFO)
    return
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "  ╔══ Cost Trend ══╗")
  table.insert(lines, "")
  table.insert(lines, "  SQL: " .. trend.sql_preview)
  table.insert(lines, "")

  -- Sparkline-style chart
  local costs = {}
  local max_cost = 0
  for _, e in ipairs(trend.entries) do
    local c = e.cost or 0
    table.insert(costs, c)
    max_cost = math.max(max_cost, c)
  end

  if max_cost > 0 then
    local bar_width = 30
    table.insert(lines, "  Cost over time:")
    for i, e in ipairs(trend.entries) do
      local bar_len = math.floor((e.cost / max_cost) * bar_width)
      local bar = string.rep("█", bar_len) .. string.rep("░", bar_width - bar_len)
      local time_str = e.time and string.format(" %dms", e.time) or ""
      table.insert(lines, string.format("  %s │%s│ %.1f%s",
        e.timestamp:sub(6, 16), bar, e.cost, time_str))
    end
    table.insert(lines, "")
  end

  -- Summary
  if trend.direction then
    local icon = trend.direction == "up" and "📈 Higher" or
                 trend.direction == "down" and "📉 Lower" or "📊 Stable"
    table.insert(lines, "  Trend: " .. icon)
    if trend.cost_change then
      table.insert(lines, string.format("  Cost change: %+.1f%%", trend.cost_change))
    end
    if trend.time_change then
      table.insert(lines, string.format("  Time change: %+.1f%%", trend.time_change))
    end
  end
  table.insert(lines, "")

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

  local ns = vim.api.nvim_create_namespace("sql_lens_trend")
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("╔") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("📈") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensError", row, 0, -1)
    elseif line:match("📉") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("SQL:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", row, 0, -1)
    elseif line:match("█") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    end
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

return M
