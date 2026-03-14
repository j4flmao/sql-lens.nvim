local M = {}

local cfg_thresholds

function M.setup(thresholds)
  cfg_thresholds = thresholds
end

---Extract column names from a filter expression
---e.g. "((age > 25) AND (status = 'active'))" → {"age", "status"}
local function extract_filter_columns(filter)
  if not filter then return {} end
  local cols = {}
  local seen = {}
  -- Match patterns like: (column_name operator value)
  -- PostgreSQL: (age > 25), ((name)::text = 'foo'), (status = 'active'::text)
  for col in filter:gmatch("%((%w[%w_]*)%)") do
    if not seen[col] and not col:match("^%d") and not col:match("^[A-Z]+$") then
      seen[col] = true
      table.insert(cols, col)
    end
  end
  -- Also match: column op value patterns
  for col in filter:gmatch("%((%w[%w_]*)%s*[><=!]") do
    if not seen[col] and not col:match("^%d") then
      seen[col] = true
      table.insert(cols, col)
    end
  end
  -- Match column references in simple expressions
  for col in filter:gmatch("(%w[%w_]*)%s*[><=!]") do
    if not seen[col] and not col:match("^%d") and #col > 1 then
      seen[col] = true
      table.insert(cols, col)
    end
  end
  return cols
end

---Extract column names from sort keys
---e.g. {"created_at DESC", "id ASC"} → {"created_at", "id"}
local function extract_sort_columns(sort_key)
  if not sort_key then return {} end
  local cols = {}
  if type(sort_key) == "table" then
    for _, sk in ipairs(sort_key) do
      local col = sk:match("^(%w[%w_%.]*)")
      if col then table.insert(cols, col) end
    end
  elseif type(sort_key) == "string" then
    for col in sort_key:gmatch("(%w[%w_%.]+)") do
      if not col:match("^%d") and col ~= "ASC" and col ~= "DESC"
         and col ~= "NULLS" and col ~= "FIRST" and col ~= "LAST" then
        table.insert(cols, col)
      end
    end
  end
  return cols
end

---Build CREATE INDEX suggestion string
local function build_index_suggestion(table_name, columns, prefix)
  if #columns == 0 or not table_name then return "" end
  prefix = prefix or "idx"
  local safe_cols = {}
  for _, c in ipairs(columns) do
    table.insert(safe_cols, c:gsub("%.", "_"))
  end
  return string.format(
    "\n  💡 CREATE INDEX %s_%s_%s ON %s(%s);",
    prefix, table_name, table.concat(safe_cols, "_"),
    table_name, table.concat(columns, ", ")
  )
end

local function walk(node, hints, depth)
  depth = depth or 0
  local t = cfg_thresholds or {}

  -- === SEQ SCAN / TABLE SCAN ===
  if (node.node_type == "Seq Scan" or node.node_type == "Table Scan") and node.relation_name then
    if t.seq_scan_warn then
      local suggest = ""
      local cols = extract_filter_columns(node.filter)
      if #cols > 0 then
        suggest = build_index_suggestion(node.relation_name, cols)
      end

      local msg
      if node.filter then
        msg = string.format("Seq Scan on '%s' with filter — add an index", node.relation_name)
      elseif node.rows and node.rows > 1000 then
        msg = string.format("Seq Scan on '%s' (%d rows) — missing WHERE clause?", node.relation_name, node.rows)
      else
        msg = string.format("Seq Scan on '%s' — consider adding an index", node.relation_name)
      end

      table.insert(hints, {
        level   = "warn",
        icon    = "󰋽",
        message = msg .. suggest,
        node    = node,
      })
    end
  end

  -- === SORT with high cost ===
  if (node.node_type == "Sort" or node.node_type == "Sort (Top-N)") and node.total_cost > 100 then
    local sort_cols = extract_sort_columns(node.sort_key)
    local suggest = ""
    -- Find the child relation for the index suggestion
    local child_table = nil
    for _, child in ipairs(node.plans or {}) do
      if child.relation_name then
        child_table = child.relation_name
        break
      end
    end
    if child_table and #sort_cols > 0 then
      suggest = build_index_suggestion(child_table, sort_cols, "idx_sort")
    end
    table.insert(hints, {
      level   = "info",
      icon    = "󰒺",
      message = string.format("Sort (cost=%.1f) — index on sort columns may eliminate sort", node.total_cost) .. suggest,
      node    = node,
    })
  end

  -- === HASH JOIN on large tables ===
  if node.node_type == "Hash Join" and node.total_cost > 500 then
    local join_cols = {}
    if node.hash_cond then
      for col in node.hash_cond:gmatch("(%w[%w_]*)%s*=") do
        if not col:match("^%d") then table.insert(join_cols, col) end
      end
    end
    local suggest = ""
    if #join_cols > 0 then
      -- Try to find the inner table
      for _, child in ipairs(node.plans or {}) do
        if child.relation_name and child.node_type:match("Scan") then
          suggest = build_index_suggestion(child.relation_name, join_cols, "idx_join")
          break
        end
      end
    end
    table.insert(hints, {
      level   = "info",
      icon    = "󰌹",
      message = string.format("Hash Join (cost=%.1f) — index on join columns may improve performance", node.total_cost) .. suggest,
      node    = node,
    })
  end

  -- === HIGH COST ===
  if node.total_cost >= (t.cost_error or 10000) then
    table.insert(hints, {
      level   = "error",
      icon    = "󰀪",
      message = string.format("Very high cost: %.0f (threshold: %d)", node.total_cost, t.cost_error),
      node    = node,
    })
  elseif node.total_cost >= (t.cost_warn or 1000) then
    table.insert(hints, {
      level   = "warn",
      icon    = "󰀦",
      message = string.format("High cost: %.0f", node.total_cost),
      node    = node,
    })
  end

  -- === ROW ESTIMATE DRIFT ===
  if node.rows and node.actual_rows then
    local ratio = node.actual_rows / math.max(node.rows, 1)
    if ratio > 10 or ratio < 0.1 then
      local advice = ""
      if ratio > 100 then
        advice = " — statistics may be stale, run ANALYZE/UPDATE STATISTICS"
      end
      table.insert(hints, {
        level   = "warn",
        icon    = "󰈇",
        message = string.format(
          "Row estimate off: expected %d, got %d (%.0fx)%s",
          node.rows, node.actual_rows, ratio, advice
        ),
        node    = node,
      })
    end
  end

  -- === NESTED LOOP ===
  if node.node_type == "Nested Loop" and node.total_cost > 500 then
    table.insert(hints, {
      level   = "info",
      icon    = "󰌹",
      message = "Nested Loop with high cost — Hash Join may be more efficient",
      node    = node,
    })
  end

  -- === INDEX SCAN without key ===
  if node.node_type == "Index Scan" and not node.key and not node.index_cond then
    table.insert(hints, {
      level   = "warn",
      icon    = "󰋽",
      message = "Index Scan but no key/condition used — check index effectiveness",
      node    = node,
    })
  end

  -- === BITMAP HEAP SCAN (often means partial index match) ===
  if node.node_type == "Bitmap Heap Scan" and node.total_cost > 500 then
    table.insert(hints, {
      level   = "info",
      icon    = "󰋽",
      message = string.format("Bitmap Heap Scan on '%s' — a more selective index may help",
        node.relation_name or "?"),
      node    = node,
    })
  end

  for _, child in ipairs(node.plans or {}) do
    walk(child, hints, depth + 1)
  end
end

function M.analyze(plan_node)
  local hints = {}
  walk(plan_node, hints, 0)
  return hints
end

function M.summary_line(plan, hints)
  local parts = {}

  -- Execution time (actual)
  if plan.execution_time then
    table.insert(parts, string.format("⏱ %dms", plan.execution_time))
  end

  -- CPU time
  if plan.cpu_time and plan.cpu_time > 0 then
    table.insert(parts, string.format("cpu=%dms", plan.cpu_time))
  end

  -- Cost (estimated subtree cost)
  if plan.total_cost > 0 then
    if plan.total_cost < 1 then
      table.insert(parts, string.format("cost=%.4f", plan.total_cost))
    else
      table.insert(parts, string.format("cost=%.1f", plan.total_cost))
    end
  end

  -- Logical reads (IO)
  if plan.logical_reads and plan.logical_reads > 0 then
    table.insert(parts, string.format("reads=%d", plan.logical_reads))
  end

  -- Estimated rows
  if plan.rows and plan.rows > 0 then
    table.insert(parts, string.format("rows≈%.0f", plan.rows))
  end

  local warns = vim.tbl_filter(function(h) return h.level == "warn" or h.level == "error" end, hints)
  if #warns > 0 then
    table.insert(parts, string.format("⚠ %d issue%s", #warns, #warns > 1 and "s" or ""))
  else
    table.insert(parts, "✓ ok")
  end

  return table.concat(parts, "  ")
end

return M
