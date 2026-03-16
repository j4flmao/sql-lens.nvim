local M = {}

local BARS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" }

---Detect numeric columns from parsed data
---@param headers string[]
---@param rows string[][]
---@return number[] indices of numeric columns
local function find_numeric_cols(headers, rows)
  local numeric = {}
  for col_idx = 1, #headers do
    local is_num = true
    local count = 0
    for _, row in ipairs(rows) do
      local val = row[col_idx]
      if val and val ~= "" and val ~= "NULL" then
        if not tonumber(val) then
          is_num = false
          break
        end
        count = count + 1
      end
    end
    if is_num and count > 0 then
      table.insert(numeric, col_idx)
    end
  end
  return numeric
end

---Detect label column (first non-numeric column)
local function find_label_col(headers, numeric_set)
  for i = 1, #headers do
    if not numeric_set[i] then return i end
  end
  return 1
end

---Render a horizontal bar
local function render_bar(value, max_val, bar_width)
  if max_val == 0 then return "" end
  local ratio = value / max_val
  local full = math.floor(ratio * bar_width)
  local frac = (ratio * bar_width) - full
  local frac_idx = math.floor(frac * 8) + 1
  frac_idx = math.min(frac_idx, 8)

  local bar = string.rep("█", full)
  if full < bar_width and frac_idx > 1 then
    bar = bar .. BARS[frac_idx]
  end
  return bar
end

---Format a number for display
local function fmt_num(n)
  if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  if n == math.floor(n) then return string.format("%d", n) end
  return string.format("%.2f", n)
end

---Build chart lines from parsed data
---@param data { headers: string[], rows: string[][] }
---@param opts? { col?: number, bar_width?: number, chart_type?: "bar"|"horizontal" }
function M.build(data, opts)
  opts = opts or {}
  local bar_width = opts.bar_width or 30

  if not data or not data.headers or #data.rows == 0 then
    return { "", "  No data to chart", "" }
  end

  local numeric_cols = find_numeric_cols(data.headers, data.rows)
  if #numeric_cols == 0 then
    return { "", "  No numeric columns found for charting", "" }
  end

  local numeric_set = {}
  for _, idx in ipairs(numeric_cols) do numeric_set[idx] = true end

  local value_col = opts.col or numeric_cols[1]
  local label_col = find_label_col(data.headers, numeric_set)

  -- Collect values
  local items = {}
  local max_val = 0
  local min_val = math.huge
  local max_label_len = 0

  for _, row in ipairs(data.rows) do
    local val = tonumber(row[value_col]) or 0
    local label = row[label_col] or ""
    if #label > 20 then label = label:sub(1, 18) .. ".." end
    max_val = math.max(max_val, val)
    min_val = math.min(min_val, val)
    max_label_len = math.max(max_label_len, #label)
    table.insert(items, { label = label, value = val })
  end

  local lines = {}
  table.insert(lines, "")
  table.insert(lines, string.format("  ╔══ Chart: %s by %s ══╗",
    data.headers[value_col] or "value", data.headers[label_col] or "label"))
  table.insert(lines, "")

  -- Stats
  local sum = 0
  for _, item in ipairs(items) do sum = sum + item.value end
  local avg = #items > 0 and sum / #items or 0
  table.insert(lines, string.format("  %d items  min=%s  max=%s  avg=%s  total=%s",
    #items, fmt_num(min_val), fmt_num(max_val), fmt_num(avg), fmt_num(sum)))
  table.insert(lines, "")

  -- Bars (show max 30 items)
  local show_count = math.min(#items, 30)
  for i = 1, show_count do
    local item = items[i]
    local padded_label = item.label .. string.rep(" ", max_label_len - #item.label)
    local bar = render_bar(item.value, max_val, bar_width)
    local val_str = fmt_num(item.value)
    table.insert(lines, string.format("  %s │%s %s", padded_label, bar, val_str))
  end

  if #items > show_count then
    table.insert(lines, string.format("  ... and %d more rows", #items - show_count))
  end

  table.insert(lines, "")

  -- If multiple numeric columns, show selector hint
  if #numeric_cols > 1 then
    local col_names = {}
    for _, idx in ipairs(numeric_cols) do
      table.insert(col_names, data.headers[idx])
    end
    table.insert(lines, "  Numeric columns: " .. table.concat(col_names, ", "))
    table.insert(lines, "")
  end

  return lines
end

---Show chart from last query result
function M.show()
  local result_ui = require("sql-lens.ui.result")
  local data = result_ui._last_parsed
  if not data then
    vim.notify("SqlLens: No result data for charting — run a query first", vim.log.levels.WARN)
    return
  end

  local numeric_cols = find_numeric_cols(data.headers, data.rows)
  if #numeric_cols == 0 then
    vim.notify("SqlLens: No numeric columns found in result", vim.log.levels.WARN)
    return
  end

  -- If multiple numeric columns, let user pick
  if #numeric_cols > 1 then
    local picker = require("sql-lens.ui.picker")
    local col_labels = {}
    for _, idx in ipairs(numeric_cols) do
      table.insert(col_labels, data.headers[idx])
    end
    picker.open(col_labels, {
      prompt = "Chart column",
      on_select = function(choice)
        for _, idx in ipairs(numeric_cols) do
          if data.headers[idx] == choice then
            M._render(data, idx)
            return
          end
        end
      end,
    })
  else
    M._render(data, numeric_cols[1])
  end
end

function M._render(data, col_idx)
  local lines = M.build(data, { col = col_idx })

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

  local ns = vim.api.nvim_create_namespace("sql_lens_chart")
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("╔") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("│") and line:match("█") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("items") and line:match("min=") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", row, 0, -1)
    elseif line:match("Numeric columns:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensDim", row, 0, -1)
    end
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

return M
