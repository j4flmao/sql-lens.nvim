local M = {}

local last_plan = nil
local last_hints = nil

function M.store(plan, hints)
  last_plan  = plan
  last_hints = hints
end

function M.show_last()
  if not last_plan then
    vim.notify("SqlLens: No plan data available. Run :SqlLensExplain first.", vim.log.levels.WARN)
    return
  end

  local lines = {}
  table.insert(lines, "╔══ SQL Lens — Query Plan Detail ══╗")
  table.insert(lines, "")

  -- Plan tree
  local function render_node(node, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    local line = prefix .. "→ " .. (node.node_type or "Unknown")
    if node.relation_name then
      line = line .. " on " .. node.relation_name
    end
    table.insert(lines, line)

    local detail = prefix .. "  "
    local parts = {}
    if node.total_cost then table.insert(parts, string.format("cost=%.1f", node.total_cost)) end
    if node.rows then table.insert(parts, string.format("rows=%d", node.rows)) end
    if node.actual_rows then table.insert(parts, string.format("actual=%d", node.actual_rows)) end
    if node.actual_time then table.insert(parts, string.format("time=%.1fms", node.actual_time)) end
    if #parts > 0 then
      table.insert(lines, detail .. table.concat(parts, "  "))
    end

    for _, child in ipairs(node.plans or {}) do
      render_node(child, indent + 1)
    end
  end

  render_node(last_plan)

  table.insert(lines, "")
  table.insert(lines, "── Execution Stats ──")
  if last_plan.execution_time then
    table.insert(lines, string.format("  Elapsed Time:    %dms", last_plan.execution_time))
  end
  if last_plan.cpu_time then
    table.insert(lines, string.format("  CPU Time:        %dms", last_plan.cpu_time))
  end
  if last_plan.planning_time then
    table.insert(lines, string.format("  Planning Time:   %.1fms", last_plan.planning_time))
  end
  if last_plan.total_cost and last_plan.total_cost > 0 then
    table.insert(lines, string.format("  Est. Cost:       %.4f", last_plan.total_cost))
  end
  if last_plan.logical_reads and last_plan.logical_reads > 0 then
    table.insert(lines, string.format("  Logical Reads:   %d pages", last_plan.logical_reads))
  end
  if last_plan.io_stats then
    for _, io in ipairs(last_plan.io_stats) do
      table.insert(lines, string.format(
        "    Table '%s': scan=%d, logical=%d, physical=%d",
        io.table_name, io.scan_count, io.logical_reads, io.physical_reads
      ))
    end
  end

  -- Hints
  if last_hints and #last_hints > 0 then
    table.insert(lines, "")
    table.insert(lines, "── Hints ──")
    for _, hint in ipairs(last_hints) do
      table.insert(lines, string.format("  %s [%s] %s", hint.icon, hint.level, hint.message))
    end
  end

  -- Create float window
  local width = 70
  local height = math.min(#lines, 25)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    col      = math.floor((vim.o.columns - width) / 2),
    row      = math.floor((vim.o.lines - height) / 2),
    style    = "minimal",
    border   = "rounded",
  })

  vim.api.nvim_set_option_value("winhl", "Normal:SqlLensBg,FloatBorder:SqlLensInfo", { win = win })

  -- Close on q or Escape
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

return M
