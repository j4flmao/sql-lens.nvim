local M = {}

local cfg_thresholds

function M.setup(thresholds)
  cfg_thresholds = thresholds
end

local function walk(node, hints, depth)
  depth = depth or 0
  local t = cfg_thresholds or {}

  if node.node_type == "Seq Scan" and node.relation_name then
    if t.seq_scan_warn then
      -- Generate index suggestion if filter/join columns detected
      local suggest = ""
      if node.filter then
        local cols = {}
        for col in node.filter:gmatch("%((%w+)") do
          if not col:match("^%d") then table.insert(cols, col) end
        end
        if #cols > 0 then
          suggest = string.format(
            "\n  💡 CREATE INDEX idx_%s_%s ON %s(%s);",
            node.relation_name, table.concat(cols, "_"),
            node.relation_name, table.concat(cols, ", ")
          )
        end
      end
      table.insert(hints, {
        level   = "warn",
        icon    = "󰋽",
        message = string.format("Seq Scan on '%s' — consider adding an index", node.relation_name) .. suggest,
        node    = node,
      })
    end
  end

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

  if node.rows and node.actual_rows then
    local ratio = node.actual_rows / math.max(node.rows, 1)
    if ratio > 10 or ratio < 0.1 then
      table.insert(hints, {
        level   = "warn",
        icon    = "󰈇",
        message = string.format(
          "Row estimate off: expected %d, got %d (%.0fx)",
          node.rows, node.actual_rows, ratio
        ),
        node    = node,
      })
    end
  end

  if node.node_type == "Nested Loop" and node.total_cost > 500 then
    table.insert(hints, {
      level   = "info",
      icon    = "󰌹",
      message = "Nested Loop with high cost — Hash Join may be more efficient",
      node    = node,
    })
  end

  if node.node_type == "Index Scan" and not node.key then
    table.insert(hints, {
      level   = "warn",
      icon    = "󰋽",
      message = "Index Scan but no key used — check index condition",
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
