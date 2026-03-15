local M = {}

---Fetch schema info and generate ER diagram
function M.generate()
  local conn_mgr = require("sql-lens.connections")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No active connection", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Building ER diagram...", vim.log.levels.INFO)

  conn:list_tables(function(err, tables)
    if err or #tables == 0 then
      vim.notify("SqlLens: No tables found", vim.log.levels.WARN)
      return
    end

    -- Fetch columns for all tables
    local table_cols = {}
    local done_cols = 0
    local total = #tables

    for _, tbl in ipairs(tables) do
      conn:list_columns(tbl, function(_, cols)
        table_cols[tbl] = cols or {}
        done_cols = done_cols + 1
        if done_cols == total then
          -- Now fetch foreign keys
          if conn.list_foreign_keys then
            conn:list_foreign_keys(function(_, fks)
              M._build(tables, table_cols, fks or {}, conn)
            end)
          else
            M._build(tables, table_cols, {}, conn)
          end
        end
      end)
    end
  end)
end

---Build Mermaid ER diagram and open in browser
function M._build(tables, table_cols, fks, conn)
  local mermaid = { "erDiagram" }

  ---Sanitize a name for Mermaid (only alphanumeric + underscore)
  local function sanitize(s)
    if not s or s == "" then return "unknown" end
    return s:gsub("[^%w_]", "_"):gsub("^_+", ""):gsub("_+$", ""):gsub("__+", "_")
  end

  ---Sanitize column type: strip parens content, no special chars
  local function clean_type(t)
    if not t or t == "" then return "unknown" end
    -- Keep just the base type name: "nvarchar(50) NOT NULL" → "nvarchar"
    local base = t:match("^([%w_]+)") or t
    return sanitize(base)
  end

  -- Build FK lookup
  local fk_set = {}
  for _, fk in ipairs(fks) do
    fk_set[fk.from_table .. "." .. fk.from_column] = true
  end

  -- Add tables with columns (skip tables with no columns)
  for _, tbl in ipairs(tables) do
    local cols = table_cols[tbl] or {}
    local safe_tbl = sanitize(tbl)
    if safe_tbl == "" then goto next_table end

    local col_lines = {}
    for _, col_info in ipairs(cols) do
      local col_name = col_info:match("^(%S+)")
      if not col_name or col_name == "" then goto next_col end
      local col_type = col_info:match("%s+(.+)$") or ""
      local safe_name = sanitize(col_name)
      local safe_type = clean_type(col_type)
      if safe_name == "" then goto next_col end

      local attr = ""
      if safe_name == "id" then
        attr = " PK"
      elseif fk_set[tbl .. "." .. col_name] then
        attr = " FK"
      end
      table.insert(col_lines, string.format("    %s %s%s", safe_type, safe_name, attr))
      ::next_col::
    end

    if #col_lines > 0 then
      table.insert(mermaid, "  " .. safe_tbl .. " {")
      for _, line in ipairs(col_lines) do
        table.insert(mermaid, line)
      end
      table.insert(mermaid, "  }")
    else
      -- Empty table: just declare it without braces
      table.insert(mermaid, "  " .. safe_tbl)
    end
    ::next_table::
  end

  -- Add relationships from foreign keys
  local seen_rels = {}
  for _, fk in ipairs(fks) do
    local safe_from = sanitize(fk.from_table)
    local safe_to = sanitize(fk.to_table)
    if safe_from == "" or safe_to == "" then goto next_fk end
    local key = safe_from .. "->" .. safe_to
    if not seen_rels[key] then
      seen_rels[key] = true
      local label = sanitize(fk.from_column)
      table.insert(mermaid, string.format(
        '  %s }o--|| %s : "%s"',
        safe_from, safe_to, label
      ))
    end
    ::next_fk::
  end

  local mermaid_code = table.concat(mermaid, "\n")
  local db_name = (conn.config.dbname or conn.config.name or "database")

  -- Debug: copy mermaid code to clipboard
  vim.fn.setreg("+", mermaid_code)

  -- Generate HTML using concatenation (not string.format, to avoid % issues)
  local safe_db = db_name:gsub("[^%w_]", "_")
  local html = table.concat({
    '<!DOCTYPE html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="UTF-8">',
    '<title>ER Diagram - ' .. db_name .. '</title>',
    '<style>',
    '* { margin: 0; padding: 0; box-sizing: border-box; }',
    'body { background: #0d1117; color: #c9d1d9; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; display: flex; flex-direction: column; min-height: 100vh; }',
    'header { background: #161b22; border-bottom: 1px solid #30363d; padding: 16px 24px; display: flex; align-items: center; gap: 12px; }',
    'header h1 { font-size: 20px; font-weight: 600; }',
    '.badge { background: #238636; color: white; padding: 2px 8px; border-radius: 12px; font-size: 12px; }',
    '.info { color: #8b949e; font-size: 14px; margin-left: auto; }',
    '.toolbar { background: #161b22; border-bottom: 1px solid #30363d; padding: 8px 24px; display: flex; gap: 8px; }',
    '.toolbar button { background: #21262d; color: #c9d1d9; border: 1px solid #30363d; padding: 5px 16px; border-radius: 6px; cursor: pointer; font-size: 13px; }',
    '.toolbar button:hover { background: #30363d; }',
    '#diagram-container { flex: 1; display: flex; align-items: center; justify-content: center; padding: 24px; overflow: auto; }',
    '.mermaid { background: #161b22; border-radius: 8px; padding: 24px; border: 1px solid #30363d; }',
    '</style>',
    '</head>',
    '<body>',
    '<header>',
    '<h1>ER Diagram</h1>',
    '<span class="badge">' .. db_name .. '</span>',
    '<span class="info">' .. #tables .. ' tables - ' .. #fks .. ' relationships - Generated by sql-lens.nvim</span>',
    '</header>',
    '<div class="toolbar">',
    '<button onclick="zoomIn()">Zoom In</button>',
    '<button onclick="zoomOut()">Zoom Out</button>',
    '<button onclick="resetZoom()">Reset</button>',
    '<button onclick="downloadSVG()">Save SVG</button>',
    '</div>',
    '<div id="diagram-container">',
    '<pre class="mermaid">',
    mermaid_code,
    '</pre>',
    '</div>',
    '<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>',
    '<script>',
    'mermaid.initialize({ startOnLoad: true, theme: "dark", er: { useMaxWidth: false, layoutDirection: "TB" }, themeVariables: { primaryColor: "#238636", primaryTextColor: "#c9d1d9", primaryBorderColor: "#30363d", lineColor: "#58a6ff", secondaryColor: "#21262d", tertiaryColor: "#161b22" } });',
    'let scale = 1;',
    'function zoomIn() { scale *= 1.2; applyZoom(); }',
    'function zoomOut() { scale /= 1.2; applyZoom(); }',
    'function resetZoom() { scale = 1; applyZoom(); }',
    'function applyZoom() { var s = document.querySelector(".mermaid svg"); if(s){ s.style.transform = "scale("+scale+")"; s.style.transformOrigin = "top left"; } }',
    'function downloadSVG() { var s = document.querySelector(".mermaid svg"); if(!s) return; var d = new XMLSerializer().serializeToString(s); var b = new Blob([d], {type:"image/svg+xml"}); var a = document.createElement("a"); a.href = URL.createObjectURL(b); a.download = "' .. safe_db .. '_er_diagram.svg"; a.click(); }',
    '</script>',
    '</body>',
    '</html>',
  }, "\n")

  -- Save to temp file and open in browser
  local tmpfile = vim.fn.tempname() .. ".html"
  local f = io.open(tmpfile, "w")
  if not f then
    vim.notify("SqlLens: Cannot create temp file", vim.log.levels.ERROR)
    return
  end
  f:write(html)
  f:close()

  -- Open in browser (cross-platform)
  local open_cmd
  if vim.fn.has("win32") == 1 then
    open_cmd = { "cmd", "/c", "start", "", tmpfile }
  elseif vim.fn.has("mac") == 1 then
    open_cmd = { "open", tmpfile }
  else
    open_cmd = { "xdg-open", tmpfile }
  end
  vim.fn.jobstart(open_cmd, { detach = true })

  vim.notify(string.format("SqlLens: ER diagram opened (%d tables, %d relationships)", #tables, #fks), vim.log.levels.INFO)
end

return M
