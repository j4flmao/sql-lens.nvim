local M = {}

---Compare schemas between two connections
---@param conn_a table Connection instance
---@param conn_b table Connection instance
---@param cb fun(err?: string, diff?: table)
function M.compare(conn_a, conn_b, cb)
  local result = {
    label_a = (conn_a.config.name or "A") .. "/" .. (conn_a.config.dbname or "?"),
    label_b = (conn_b.config.name or "B") .. "/" .. (conn_b.config.dbname or "?"),
    only_a = {},    -- tables only in A
    only_b = {},    -- tables only in B
    both = {},      -- { table, cols_only_a, cols_only_b, cols_both }
  }

  conn_a:list_tables(function(err_a, tables_a)
    if err_a then return cb("Error fetching tables from A: " .. tostring(err_a)) end
    conn_b:list_tables(function(err_b, tables_b)
      if err_b then return cb("Error fetching tables from B: " .. tostring(err_b)) end

      local set_a = {}
      for _, t in ipairs(tables_a or {}) do set_a[t] = true end
      local set_b = {}
      for _, t in ipairs(tables_b or {}) do set_b[t] = true end

      for _, t in ipairs(tables_a or {}) do
        if not set_b[t] then
          table.insert(result.only_a, t)
        end
      end
      for _, t in ipairs(tables_b or {}) do
        if not set_a[t] then
          table.insert(result.only_b, t)
        end
      end

      -- Find common tables and compare columns
      local common = {}
      for _, t in ipairs(tables_a or {}) do
        if set_b[t] then table.insert(common, t) end
      end

      if #common == 0 then
        return cb(nil, result)
      end

      local done = 0
      for _, tbl in ipairs(common) do
        local tbl_diff = { table = tbl, cols_only_a = {}, cols_only_b = {}, cols_both = {} }
        conn_a:list_columns(tbl, function(_, cols_a)
          conn_b:list_columns(tbl, function(_, cols_b)
            local ca = {}
            for _, c in ipairs(cols_a or {}) do
              local name = c:match("^(%S+)")
              ca[name] = c
            end
            local cb_set = {}
            for _, c in ipairs(cols_b or {}) do
              local name = c:match("^(%S+)")
              cb_set[name] = c
            end

            for name, info in pairs(ca) do
              if not cb_set[name] then
                table.insert(tbl_diff.cols_only_a, info)
              else
                table.insert(tbl_diff.cols_both, { name = name, a = info, b = cb_set[name] })
              end
            end
            for name, info in pairs(cb_set) do
              if not ca[name] then
                table.insert(tbl_diff.cols_only_b, info)
              end
            end

            if #tbl_diff.cols_only_a > 0 or #tbl_diff.cols_only_b > 0 then
              table.insert(result.both, tbl_diff)
            end

            done = done + 1
            if done == #common then
              cb(nil, result)
            end
          end)
        end)
      end
    end)
  end)
end

---Show schema diff in a new buffer
function M.show(diff)
  local lines = {}

  table.insert(lines, "")
  table.insert(lines, "  ╔══ Schema Diff ══╗")
  table.insert(lines, "")
  table.insert(lines, "  A: " .. diff.label_a)
  table.insert(lines, "  B: " .. diff.label_b)
  table.insert(lines, "")

  if #diff.only_a > 0 then
    table.insert(lines, "  ── Only in A ──")
    for _, t in ipairs(diff.only_a) do
      table.insert(lines, "  − " .. t)
    end
    table.insert(lines, "")
  end

  if #diff.only_b > 0 then
    table.insert(lines, "  ── Only in B ──")
    for _, t in ipairs(diff.only_b) do
      table.insert(lines, "  + " .. t)
    end
    table.insert(lines, "")
  end

  if #diff.both > 0 then
    table.insert(lines, "  ── Column Differences ──")
    for _, td in ipairs(diff.both) do
      table.insert(lines, "")
      table.insert(lines, "  Table: " .. td.table)
      for _, c in ipairs(td.cols_only_a) do
        table.insert(lines, "    − " .. c)
      end
      for _, c in ipairs(td.cols_only_b) do
        table.insert(lines, "    + " .. c)
      end
    end
    table.insert(lines, "")
  end

  if #diff.only_a == 0 and #diff.only_b == 0 and #diff.both == 0 then
    table.insert(lines, "  ✓ Schemas are identical")
    table.insert(lines, "")
  end

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

  -- Highlights
  local ns = vim.api.nvim_create_namespace("sql_lens_diff")
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("^%s*╔") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("^%s*[−]") or line:match("^%s+[−]") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensError", row, 0, -1)
    elseif line:match("^%s*[+]") or line:match("^%s+[+]") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("^%s*──") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensWarn", row, 0, -1)
    elseif line:match("^%s*Table:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("✓") then
      vim.api.nvim_buf_add_highlight(buf, ns, "SqlLensOk", row, 0, -1)
    end
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

---Interactive: pick 2 connections and compare
function M.pick_and_compare()
  local conn_mgr = require("sql-lens.connections")
  local conns = conn_mgr._connections

  if #conns < 2 then
    vim.notify("SqlLens: Need at least 2 connections for schema diff", vim.log.levels.WARN)
    return
  end

  vim.ui.select(conns, {
    prompt = "SqlLens — Select connection A:",
    format_item = function(c)
      return c.config.name .. " (" .. c.type .. " → " .. (c.config.dbname or "?") .. ")"
    end,
  }, function(conn_a)
    if not conn_a then return end
    vim.ui.select(conns, {
      prompt = "SqlLens — Select connection B:",
      format_item = function(c)
        return c.config.name .. " (" .. c.type .. " → " .. (c.config.dbname or "?") .. ")"
      end,
    }, function(conn_b)
      if not conn_b then return end
      vim.notify("SqlLens: Comparing schemas...", vim.log.levels.INFO)
      M.compare(conn_a, conn_b, function(err, diff)
        if err then
          vim.notify("SqlLens: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        M.show(diff)
      end)
    end)
  end)
end

return M
