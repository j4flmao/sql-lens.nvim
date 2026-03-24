local M = {}

local DEP_QUERIES = {
  postgres = [[
    SELECT DISTINCT
      dependent_ns.nspname || '.' || dependent_view.relname AS dependent,
      source_ns.nspname || '.' || source_table.relname AS dependency,
      CASE source_table.relkind
        WHEN 'r' THEN 'table'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'matview'
        ELSE 'other'
      END AS dep_type
    FROM pg_depend
    JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
    JOIN pg_class AS dependent_view ON pg_rewrite.ev_class = dependent_view.oid
    JOIN pg_class AS source_table ON pg_depend.refobjid = source_table.oid
    JOIN pg_namespace AS dependent_ns ON dependent_view.relnamespace = dependent_ns.oid
    JOIN pg_namespace AS source_ns ON source_table.relnamespace = source_ns.oid
    WHERE dependent_ns.nspname = 'public'
      AND source_ns.nspname = 'public'
      AND source_table.relname != dependent_view.relname
    ORDER BY dependent, dependency
  ]],
  sqlserver = [[
    SET NOCOUNT ON;
    SELECT
      OBJECT_NAME(referencing_id) AS dependent,
      referenced_entity_name AS dependency,
      CASE
        WHEN o.type = 'V' THEN 'view'
        WHEN o.type IN ('P', 'PC') THEN 'proc'
        WHEN o.type IN ('FN', 'IF', 'TF') THEN 'func'
        ELSE 'other'
      END AS dep_type
    FROM sys.sql_expression_dependencies d
    JOIN sys.objects o ON d.referencing_id = o.object_id
    WHERE referenced_entity_name IS NOT NULL
    ORDER BY dependent, dependency
  ]],
  mysql = [[
    SELECT
      TABLE_NAME AS dependent,
      REFERENCED_TABLE_NAME AS dependency,
      'view' AS dep_type
    FROM INFORMATION_SCHEMA.VIEW_TABLE_USAGE
    WHERE TABLE_SCHEMA = DATABASE()
    ORDER BY dependent, dependency
  ]],
}

function M.generate()
  local conn_mgr = require("sql-lens.connections")
  local async = require("sql-lens.utils.async")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)

  if not conn then
    vim.notify("SqlLens: No active connection", vim.log.levels.WARN)
    return
  end

  local query = DEP_QUERIES[conn.type]
  if not query then
    vim.notify("SqlLens: Dependency graph not supported for " .. conn.type, vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Building dependency graph...", vim.log.levels.INFO)

  conn:execute(query, function(err, stdout)
    if err then
      vim.notify("SqlLens: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    local result_ui = require("sql-lens.ui.result")
    local data = result_ui._extract_data(stdout)

    if not data or #data.rows == 0 then
      vim.notify("SqlLens: No dependencies found", vim.log.levels.INFO)
      return
    end

    M._build(data, conn)
  end)
end

local function sanitize(s)
  if not s or s == "" then return "unknown" end
  return s:gsub("[^%w_]", "_"):gsub("^_+", ""):gsub("_+$", ""):gsub("__+", "_")
end

function M._build(data, conn)
  local mermaid = { "graph LR" }

  -- Collect nodes and edges
  local nodes = {}
  local edges = {}

  for _, row in ipairs(data.rows) do
    local dependent = sanitize(row[1] or "")
    local dependency = sanitize(row[2] or "")
    local dep_type = (row[3] or ""):lower()
    if dependent ~= "" and dependency ~= "" then
      if not nodes[dependent] then
        local shape = dep_type == "view" and { "[[", "]]" }
                   or dep_type == "proc" and { "((", "))" }
                   or dep_type == "func" and { ">", "]" }
                   or { "[", "]" }
        nodes[dependent] = { name = dependent, shape = shape, type = dep_type }
      end
      if not nodes[dependency] then
        nodes[dependency] = { name = dependency, shape = { "[(", ")]" }, type = "table" }
      end
      table.insert(edges, { from = dependent, to = dependency })
    end
  end

  -- Build mermaid
  -- Style classes
  table.insert(mermaid, '  classDef tbl fill:#238636,stroke:#30363d,color:#fff')
  table.insert(mermaid, '  classDef vw fill:#1f6feb,stroke:#30363d,color:#fff')
  table.insert(mermaid, '  classDef prc fill:#8957e5,stroke:#30363d,color:#fff')

  for id, node in pairs(nodes) do
    table.insert(mermaid, string.format("  %s%s%s%s",
      id, node.shape[1], node.name, node.shape[2]))
  end

  for _, edge in ipairs(edges) do
    table.insert(mermaid, string.format("  %s --> %s", edge.from, edge.to))
  end

  -- Apply classes
  for id, node in pairs(nodes) do
    if node.type == "table" then
      table.insert(mermaid, "  class " .. id .. " tbl")
    elseif node.type == "view" or node.type == "matview" then
      table.insert(mermaid, "  class " .. id .. " vw")
    elseif node.type == "proc" or node.type == "func" then
      table.insert(mermaid, "  class " .. id .. " prc")
    end
  end

  local mermaid_code = table.concat(mermaid, "\n")
  local db_name = conn.config.dbname or conn.config.name or "database"

  vim.fn.setreg("+", mermaid_code)

  local safe_db = db_name:gsub("[^%w_]", "_")
  local html = table.concat({
    '<!DOCTYPE html>',
    '<html><head><meta charset="UTF-8">',
    '<title>Dependencies - ' .. db_name .. '</title>',
    '<style>',
    'body { background: #0d1117; color: #c9d1d9; font-family: sans-serif; margin: 0; display: flex; flex-direction: column; min-height: 100vh; }',
    'header { background: #161b22; border-bottom: 1px solid #30363d; padding: 16px 24px; display: flex; align-items: center; gap: 12px; }',
    'header h1 { font-size: 20px; }',
    '.badge { background: #238636; color: white; padding: 2px 8px; border-radius: 12px; font-size: 12px; }',
    '.legend { background: #161b22; border-bottom: 1px solid #30363d; padding: 8px 24px; display: flex; gap: 16px; font-size: 13px; }',
    '.legend span { display: flex; align-items: center; gap: 4px; }',
    '.dot { width: 12px; height: 12px; border-radius: 3px; display: inline-block; }',
    '.dot-tbl { background: #238636; } .dot-vw { background: #1f6feb; } .dot-prc { background: #8957e5; }',
    '#container { flex: 1; display: flex; align-items: center; justify-content: center; padding: 24px; }',
    '.mermaid { background: #161b22; border-radius: 8px; padding: 24px; border: 1px solid #30363d; }',
    '</style></head><body>',
    '<header><h1>Dependency Graph</h1><span class="badge">' .. db_name .. '</span></header>',
    '<div class="legend">',
    '<span><span class="dot dot-tbl"></span> Table</span>',
    '<span><span class="dot dot-vw"></span> View</span>',
    '<span><span class="dot dot-prc"></span> Procedure/Function</span>',
    '</div>',
    '<div id="container"><pre class="mermaid">',
    mermaid_code,
    '</pre></div>',
    '<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>',
    '<script>mermaid.initialize({ startOnLoad: true, theme: "dark", themeVariables: { primaryColor: "#238636", primaryTextColor: "#c9d1d9", lineColor: "#58a6ff" } });</script>',
    '</body></html>',
  }, "\n")

  local tmpfile = vim.fn.tempname() .. ".html"
  local f = io.open(tmpfile, "w")
  if not f then
    vim.notify("SqlLens: Cannot create temp file", vim.log.levels.ERROR)
    return
  end
  f:write(html)
  f:close()

  local open_cmd
  if vim.fn.has("win32") == 1 then
    open_cmd = { "cmd", "/c", "start", "", tmpfile }
  elseif vim.fn.has("mac") == 1 then
    open_cmd = { "open", tmpfile }
  else
    open_cmd = { "xdg-open", tmpfile }
  end
  vim.fn.jobstart(open_cmd, { detach = true })

  vim.notify(string.format("SqlLens: Dependency graph opened (%d nodes, %d edges)",
    vim.tbl_count(nodes), #edges), vim.log.levels.INFO)
end

return M
