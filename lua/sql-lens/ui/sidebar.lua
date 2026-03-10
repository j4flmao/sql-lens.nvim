local M = {}

local sidebar_buf = nil
local sidebar_win = nil

function M.open(plan, hints)
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    M.update(plan, hints)
    return
  end

  vim.cmd("vsplit")
  sidebar_win = vim.api.nvim_get_current_win()
  sidebar_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(sidebar_win, sidebar_buf)
  vim.api.nvim_win_set_width(sidebar_win, 50)

  vim.bo[sidebar_buf].buftype    = "nofile"
  vim.bo[sidebar_buf].bufhidden  = "wipe"
  vim.bo[sidebar_buf].filetype   = "sqllens"

  M.update(plan, hints)
end

function M.update(plan, hints)
  if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then return end

  local lines = { "── SqlLens Plan ──", "" }

  local function render_node(node, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    table.insert(lines, prefix .. "→ " .. (node.node_type or "Unknown"))
    if node.relation_name then
      table.insert(lines, prefix .. "  table: " .. node.relation_name)
    end
    if node.total_cost then
      table.insert(lines, prefix .. string.format("  cost: %.1f", node.total_cost))
    end
    for _, child in ipairs(node.plans or {}) do
      render_node(child, indent + 1)
    end
  end

  if plan then render_node(plan) end

  if hints and #hints > 0 then
    table.insert(lines, "")
    table.insert(lines, "── Hints ──")
    for _, h in ipairs(hints) do
      table.insert(lines, string.format("  %s [%s] %s", h.icon, h.level, h.message))
    end
  end

  vim.bo[sidebar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
  vim.bo[sidebar_buf].modifiable = false
end

function M.close()
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    vim.api.nvim_win_close(sidebar_win, true)
  end
  sidebar_win = nil
  sidebar_buf = nil
end

function M.toggle(plan, hints)
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    M.close()
  else
    M.open(plan, hints)
  end
end

return M
