local M = {}

local QUERY_SRC = [[
  (statement) @stmt
  (select_statement) @stmt
  (insert_statement) @stmt
  (update_statement) @stmt
  (delete_statement) @stmt
]]

function M.get_statement_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "sql")
  if not ok or not parser then
    return M.fallback_get_statement(bufnr)
  end

  local tree = parser:parse()[1]
  if not tree then return nil end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row    = cursor[1] - 1
  local col    = cursor[2]

  local ok2, query = pcall(vim.treesitter.query.parse, "sql", QUERY_SRC)
  if not ok2 then return M.fallback_get_statement(bufnr) end

  local root = tree:root()
  local best_node = nil
  local best_size = math.huge

  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    local sr, sc, er, ec = node:range()
    local in_range = (row > sr or (row == sr and col >= sc))
                  and (row < er or (row == er and col <= ec))
    if in_range then
      local size = (er - sr) * 10000 + (ec - sc)
      if size < best_size then
        best_size = size
        best_node = node
      end
    end
  end

  if not best_node then return nil end

  local sr = best_node:range()
  local text = vim.treesitter.get_node_text(best_node, bufnr)
  return text, sr
end

---Lấy tất cả SQL statements trong buffer
---@param bufnr number
---@return table[] list of {sql=string, start_line=number}
function M.get_all_statements(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, ts_parser = pcall(vim.treesitter.get_parser, bufnr, "sql")
  if ok and ts_parser then
    local tree = ts_parser:parse()[1]
    if tree then
      local ok2, query = pcall(vim.treesitter.query.parse, "sql", QUERY_SRC)
      if ok2 then
        local root = tree:root()
        local results = {}
        local seen = {}
        for _, node in query:iter_captures(root, bufnr, 0, -1) do
          local sr = node:range()
          if not seen[sr] then
            seen[sr] = true
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text and #text >= 5 then
              table.insert(results, { sql = text, start_line = sr })
            end
          end
        end
        if #results > 0 then return results end
      end
    end
  end

  return M.fallback_get_all_statements(bufnr)
end

---Fallback: split buffer by semicolons
function M.fallback_get_all_statements(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}
  local current = {}
  local start_line = nil

  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^%-%-") then
      if start_line == nil then
        start_line = i - 1  -- 0-indexed
      end
      table.insert(current, line)
      if line:match(";%s*$") then
        local sql = table.concat(current, "\n"):gsub(";%s*$", "")
        if #sql >= 5 then
          table.insert(results, { sql = sql, start_line = start_line })
        end
        current = {}
        start_line = nil
      end
    elseif #current == 0 then
      start_line = nil
    end
  end

  return results
end

function M.fallback_get_statement(bufnr)
  local lines   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor  = vim.api.nvim_win_get_cursor(0)
  local cur_row = cursor[1] - 1

  local start_row = cur_row
  while start_row > 0 do
    local line = lines[start_row]
    if line and (line:match("^%s*$") or lines[start_row-1] and lines[start_row-1]:match(";%s*$")) then
      break
    end
    start_row = start_row - 1
  end

  local sql_lines = {}
  for i = start_row + 1, #lines do
    local line = lines[i]
    table.insert(sql_lines, line)
    if line and line:match(";%s*$") then break end
  end

  local sql = table.concat(sql_lines, "\n"):gsub(";%s*$", "")
  if #sql < 5 then return nil end
  return sql, start_row
end

return M
