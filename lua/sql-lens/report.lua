local M = {}

local extractor = require("sql-lens.analyzer.extractor")
local parser    = require("sql-lens.analyzer.parser")
local hints_mod = require("sql-lens.analyzer.hints")
local conn_mgr  = require("sql-lens.connections")

---Escape HTML special chars
local function esc(s)
  if not s then return "" end
  return tostring(s)
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
end

---Severity color
local function severity_color(level)
  if level == "error" then return "#f87171"
  elseif level == "warn" then return "#facc15"
  elseif level == "info" then return "#60a5fa"
  else return "#4ade80" end
end

---Severity badge
local function badge(level)
  local colors = { error = "#991b1b", warn = "#854d0e", info = "#1e40af", ok = "#166534" }
  local labels = { error = "ERROR", warn = "WARN", info = "INFO", ok = "OK" }
  local bg = colors[level] or colors.ok
  local label = labels[level] or "OK"
  return string.format('<span class="badge" style="background:%s">%s</span>', bg, label)
end

---Build plan tree HTML recursively
local function render_plan_tree(node, depth)
  depth = depth or 0
  local lines = {}
  local indent = string.rep("  ", depth)
  local cost_class = ""
  if node.total_cost and node.total_cost > 0.5 then cost_class = ' class="high-cost"' end

  local row = indent .. '<div class="plan-node">'
  row = row .. '<span class="node-type">' .. esc(node.physical_op or node.node_type or "?") .. '</span>'
  if node.relation_name then
    row = row .. ' <span class="relation">on ' .. esc(node.relation_name) .. '</span>'
  end

  local meta = {}
  if node.total_cost and node.total_cost > 0 then
    table.insert(meta, string.format("cost=%.4f", node.total_cost))
  end
  if node.rows and node.rows > 0 then
    table.insert(meta, string.format("rows≈%.0f", node.rows))
  end
  if node.actual_rows then
    table.insert(meta, string.format("actual=%d", node.actual_rows))
  end
  if node.actual_time then
    table.insert(meta, string.format("time=%.1fms", node.actual_time))
  end
  if #meta > 0 then
    row = row .. ' <span class="meta">' .. table.concat(meta, " · ") .. '</span>'
  end
  row = row .. '</div>'
  table.insert(lines, row)

  for _, child in ipairs(node.plans or {}) do
    vim.list_extend(lines, render_plan_tree(child, depth + 1))
  end
  return lines
end

---Build IO stats HTML
local function render_io_stats(plan)
  if not plan.io_stats or #plan.io_stats == 0 then return "" end
  local rows = {}
  for _, io in ipairs(plan.io_stats) do
    table.insert(rows, string.format(
      '<tr><td>%s</td><td>%d</td><td>%d</td><td>%d</td></tr>',
      esc(io.table_name), io.scan_count or 0, io.logical_reads or 0, io.physical_reads or 0
    ))
  end
  return [[
    <table class="io-table">
      <tr><th>Table</th><th>Scans</th><th>Logical Reads</th><th>Physical Reads</th></tr>
  ]] .. table.concat(rows, "\n") .. "</table>"
end

---Generate full HTML report
---@param results table[] list of { sql, plan, hints, conn_name, conn_type, error }
---@param filename string source file name
function M.generate_html(results, filename)
  local total_queries = #results
  local total_warnings = 0
  local total_errors = 0
  local total_ok = 0

  for _, r in ipairs(results) do
    if r.error then
      total_errors = total_errors + 1
    else
      local errs = vim.tbl_filter(function(h) return h.level == "error" end, r.hints or {})
      local warns = vim.tbl_filter(function(h) return h.level == "warn" end, r.hints or {})
      total_errors = total_errors + #errs
      total_warnings = total_warnings + #warns
      if #errs == 0 and #warns == 0 then total_ok = total_ok + 1 end
    end
  end

  -- Group by connection
  local by_conn = {}
  for _, r in ipairs(results) do
    local key = (r.conn_name or "unknown") .. " (" .. (r.conn_type or "?") .. ")"
    by_conn[key] = by_conn[key] or {}
    table.insert(by_conn[key], r)
  end

  local html_parts = {}

  -- Build query cards
  local query_cards = {}
  for idx, r in ipairs(results) do
    local card = {}
    local level = "ok"
    if r.error then
      level = "error"
    elseif r.hints then
      if #vim.tbl_filter(function(h) return h.level == "error" end, r.hints) > 0 then level = "error"
      elseif #vim.tbl_filter(function(h) return h.level == "warn" end, r.hints) > 0 then level = "warn"
      end
    end

    table.insert(card, string.format('<div class="query-card %s-border" id="q%d">', level, idx))
    table.insert(card, string.format('<div class="card-header">'))
    table.insert(card, string.format('<h3>Query #%d %s</h3>', idx, badge(level)))
    table.insert(card, string.format(
      '<span class="conn-badge">%s · %s</span>',
      esc(r.conn_name or "?"), esc(r.conn_type or "?")
    ))
    table.insert(card, '</div>')

    -- SQL
    table.insert(card, '<div class="sql-block"><pre><code>' .. esc(r.sql) .. '</code></pre></div>')

    if r.error then
      table.insert(card, '<div class="error-msg">❌ ' .. esc(r.error) .. '</div>')
    else
      -- Stats bar
      local stats = {}
      if r.plan.execution_time then
        table.insert(stats, string.format('<div class="stat"><span class="stat-val">%dms</span><span class="stat-label">Elapsed</span></div>', r.plan.execution_time))
      end
      if r.plan.cpu_time then
        table.insert(stats, string.format('<div class="stat"><span class="stat-val">%dms</span><span class="stat-label">CPU</span></div>', r.plan.cpu_time))
      end
      if r.plan.total_cost > 0 then
        local cost_str = r.plan.total_cost < 1 and string.format("%.4f", r.plan.total_cost) or string.format("%.2f", r.plan.total_cost)
        table.insert(stats, string.format('<div class="stat"><span class="stat-val">%s</span><span class="stat-label">Est. Cost</span></div>', cost_str))
      end
      if r.plan.logical_reads and r.plan.logical_reads > 0 then
        table.insert(stats, string.format('<div class="stat"><span class="stat-val">%d</span><span class="stat-label">Logical Reads</span></div>', r.plan.logical_reads))
      end
      if #stats > 0 then
        table.insert(card, '<div class="stats-bar">' .. table.concat(stats) .. '</div>')
      end

      -- Plan tree
      if r.plan and #(r.plan.plans or {}) > 0 then
        table.insert(card, '<details open><summary class="section-title">Execution Plan</summary>')
        table.insert(card, '<div class="plan-tree">')
        for _, node in ipairs(r.plan.plans) do
          vim.list_extend(card, render_plan_tree(node))
        end
        table.insert(card, '</div></details>')
      end

      -- IO stats
      local io_html = render_io_stats(r.plan)
      if io_html ~= "" then
        table.insert(card, '<details><summary class="section-title">IO Statistics</summary>')
        table.insert(card, io_html)
        table.insert(card, '</details>')
      end

      -- Hints/Warnings
      if r.hints and #r.hints > 0 then
        table.insert(card, '<details open><summary class="section-title">Warnings & Hints (' .. #r.hints .. ')</summary>')
        table.insert(card, '<div class="hints">')
        for _, h in ipairs(r.hints) do
          table.insert(card, string.format(
            '<div class="hint %s"><span class="hint-icon">%s</span> %s</div>',
            h.level, esc(h.icon), esc(h.message)
          ))
        end
        table.insert(card, '</div></details>')
      end
    end

    table.insert(card, '</div>')
    table.insert(query_cards, table.concat(card, "\n"))
  end

  -- TOC
  local toc = {}
  for idx, r in ipairs(results) do
    local level = "ok"
    if r.error then level = "error"
    elseif r.hints then
      if #vim.tbl_filter(function(h) return h.level == "error" end, r.hints) > 0 then level = "error"
      elseif #vim.tbl_filter(function(h) return h.level == "warn" end, r.hints) > 0 then level = "warn" end
    end
    local sql_preview = r.sql:gsub("\n", " "):sub(1, 60)
    table.insert(toc, string.format(
      '<a href="#q%d" class="toc-item %s-bg"><span class="toc-num">#%d</span> %s %s</a>',
      idx, level, idx, badge(level), esc(sql_preview)
    ))
  end

  -- Assemble full HTML
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local html = string.format([[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SqlLens Report — %s</title>
<style>
:root { --bg: #0d1117; --card: #161b22; --border: #30363d; --text: #e6edf3; --dim: #8b949e; --blue: #58a6ff; --green: #3fb950; --yellow: #d29922; --red: #f85149; --purple: #bc8cff; }
* { margin:0; padding:0; box-sizing:border-box; }
body { background:var(--bg); color:var(--text); font-family:'Segoe UI','SF Pro',system-ui,sans-serif; line-height:1.6; padding:2rem; }
.container { max-width:1200px; margin:0 auto; }
header { text-align:center; margin-bottom:2rem; padding:2rem; background:linear-gradient(135deg,#161b22 0%%,#1c2333 100%%); border-radius:16px; border:1px solid var(--border); }
header h1 { font-size:2rem; background:linear-gradient(90deg,var(--blue),var(--purple)); -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
header p { color:var(--dim); margin-top:0.5rem; }
.overview { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:1rem; margin-bottom:2rem; }
.overview-card { background:var(--card); border:1px solid var(--border); border-radius:12px; padding:1.5rem; text-align:center; }
.overview-card .num { font-size:2.5rem; font-weight:700; }
.overview-card .label { color:var(--dim); font-size:0.85rem; text-transform:uppercase; letter-spacing:1px; }
.num-ok { color:var(--green); }
.num-warn { color:var(--yellow); }
.num-error { color:var(--red); }
.num-total { color:var(--blue); }
.toc { background:var(--card); border:1px solid var(--border); border-radius:12px; padding:1.5rem; margin-bottom:2rem; }
.toc h2 { margin-bottom:1rem; font-size:1.1rem; color:var(--dim); }
.toc-item { display:block; padding:0.5rem 0.75rem; margin:0.25rem 0; border-radius:6px; text-decoration:none; color:var(--text); font-size:0.9rem; font-family:monospace; transition:background 0.15s; }
.toc-item:hover { background:rgba(255,255,255,0.05); }
.toc-num { color:var(--dim); margin-right:0.5rem; }
.ok-bg { border-left:3px solid var(--green); }
.warn-bg { border-left:3px solid var(--yellow); }
.error-bg { border-left:3px solid var(--red); }
.query-card { background:var(--card); border:1px solid var(--border); border-radius:12px; margin-bottom:1.5rem; overflow:hidden; }
.ok-border { border-left:4px solid var(--green); }
.warn-border { border-left:4px solid var(--yellow); }
.error-border { border-left:4px solid var(--red); }
.card-header { display:flex; justify-content:space-between; align-items:center; padding:1rem 1.5rem; border-bottom:1px solid var(--border); }
.card-header h3 { font-size:1.1rem; display:flex; align-items:center; gap:0.75rem; }
.conn-badge { background:rgba(88,166,255,0.15); color:var(--blue); padding:0.2rem 0.6rem; border-radius:20px; font-size:0.8rem; }
.badge { display:inline-block; padding:0.15rem 0.5rem; border-radius:4px; font-size:0.7rem; font-weight:700; color:white; text-transform:uppercase; letter-spacing:0.5px; }
.sql-block { padding:1rem 1.5rem; background:rgba(0,0,0,0.3); border-bottom:1px solid var(--border); }
.sql-block pre { overflow-x:auto; }
.sql-block code { color:#79c0ff; font-family:'Cascadia Code','Fira Code','Consolas',monospace; font-size:0.85rem; white-space:pre-wrap; }
.stats-bar { display:flex; gap:0; border-bottom:1px solid var(--border); }
.stat { flex:1; padding:1rem; text-align:center; border-right:1px solid var(--border); }
.stat:last-child { border-right:none; }
.stat-val { display:block; font-size:1.5rem; font-weight:700; color:var(--blue); }
.stat-label { font-size:0.75rem; color:var(--dim); text-transform:uppercase; letter-spacing:1px; }
.section-title { padding:0.75rem 1.5rem; cursor:pointer; font-weight:600; color:var(--dim); font-size:0.9rem; user-select:none; }
.section-title:hover { color:var(--text); }
.plan-tree { padding:0.5rem 1.5rem 1rem; font-family:monospace; font-size:0.85rem; }
.plan-node { padding:0.3rem 0; padding-left:1.5rem; border-left:2px solid var(--border); margin-left:0.5rem; }
.plan-node:first-child { border-left:2px solid var(--blue); }
.node-type { color:var(--purple); font-weight:600; }
.relation { color:var(--green); }
.meta { color:var(--dim); font-size:0.8rem; }
.io-table { width:100%%; border-collapse:collapse; margin:0.5rem 1.5rem 1rem; font-size:0.85rem; }
.io-table th { text-align:left; padding:0.5rem; border-bottom:2px solid var(--border); color:var(--dim); font-size:0.8rem; text-transform:uppercase; }
.io-table td { padding:0.5rem; border-bottom:1px solid var(--border); }
.hints { padding:0.5rem 1.5rem 1rem; }
.hint { padding:0.4rem 0.6rem; margin:0.3rem 0; border-radius:6px; font-size:0.85rem; }
.hint.warn { background:rgba(210,153,34,0.1); color:var(--yellow); }
.hint.error { background:rgba(248,81,73,0.1); color:var(--red); }
.hint.info { background:rgba(88,166,255,0.1); color:var(--blue); }
.hint-icon { margin-right:0.5rem; }
.error-msg { padding:1rem 1.5rem; color:var(--red); background:rgba(248,81,73,0.05); }
footer { text-align:center; padding:2rem; color:var(--dim); font-size:0.8rem; }
</style>
</head>
<body>
<div class="container">
<header>
  <h1>⚡ SqlLens — Query Analysis Report</h1>
  <p>%s · Generated %s</p>
</header>

<div class="overview">
  <div class="overview-card"><div class="num num-total">%d</div><div class="label">Total Queries</div></div>
  <div class="overview-card"><div class="num num-ok">%d</div><div class="label">OK</div></div>
  <div class="overview-card"><div class="num num-warn">%d</div><div class="label">Warnings</div></div>
  <div class="overview-card"><div class="num num-error">%d</div><div class="label">Errors</div></div>
</div>

<div class="toc">
  <h2>📋 Query Index</h2>
  %s
</div>

%s

<footer>Generated by sql-lens.nvim · %s</footer>
</div>
</body>
</html>]],
    esc(filename),
    esc(filename), timestamp,
    total_queries, total_ok, total_warnings, total_errors,
    table.concat(toc, "\n"),
    table.concat(query_cards, "\n"),
    timestamp
  )

  return html
end

---Run report: analyze all queries across all connections, generate HTML
function M.run(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  local statements = extractor.get_all_statements(bufnr)

  if not statements or #statements == 0 then
    vim.notify("SqlLens Report: No SQL statements found", vim.log.levels.WARN)
    return
  end

  -- Get all connections
  local connections = conn_mgr._connections
  if #connections == 0 then
    vim.notify("SqlLens Report: No connections configured", vim.log.levels.WARN)
    return
  end

  local total_jobs = #statements * #connections
  local results = {}
  local done = 0

  vim.notify(string.format(
    "SqlLens Report: Analyzing %d queries × %d connections...",
    #statements, #connections
  ), vim.log.levels.INFO)

  for _, conn in ipairs(connections) do
    for stmt_idx, stmt in ipairs(statements) do
      if #stmt.sql < 5 then
        done = done + 1
      else
        conn:explain(stmt.sql, function(err, raw_data)
          done = done + 1

          local entry = {
            sql       = stmt.sql,
            conn_name = conn.config.name,
            conn_type = conn.type,
          }

          if err then
            entry.error = tostring(err)
            entry.hints = {}
            entry.plan = { total_cost = 0, plans = {} }
          else
            entry.plan  = parser.parse(raw_data, conn.type)
            entry.hints = hints_mod.analyze(entry.plan)
          end

          table.insert(results, entry)

          -- All done?
          if done >= total_jobs then
            -- Sort by connection then by original order
            table.sort(results, function(a, b)
              if a.conn_name ~= b.conn_name then return a.conn_name < b.conn_name end
              return a.sql < b.sql
            end)

            local html = M.generate_html(results, filename)
            local report_path = vim.fn.tempname() .. "_sqllens_report.html"
            local f = io.open(report_path, "w")
            if f then
              f:write(html)
              f:close()

              -- Open in browser
              local open_cmd
              if vim.fn.has("win32") == 1 then
                open_cmd = { "cmd", "/c", "start", "", report_path }
              elseif vim.fn.has("mac") == 1 then
                open_cmd = { "open", report_path }
              else
                open_cmd = { "xdg-open", report_path }
              end

              vim.fn.jobstart(open_cmd, { detach = true })
              vim.notify("SqlLens Report: Opened " .. report_path, vim.log.levels.INFO)
            else
              vim.notify("SqlLens Report: Failed to write file", vim.log.levels.ERROR)
            end
          end
        end)
      end
    end
  end
end

return M
