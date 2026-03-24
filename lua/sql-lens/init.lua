local M = {}

local config_mod  = require("sql-lens.config")
local conn_mgr    = require("sql-lens.connections")
local extractor   = require("sql-lens.analyzer.extractor")
local parser      = require("sql-lens.analyzer.parser")
local hints_mod   = require("sql-lens.analyzer.hints")
local lint_mod    = require("sql-lens.analyzer.lint")
local vt          = require("sql-lens.ui.virtual_text")
local float       = require("sql-lens.ui.float")
local highlights  = require("sql-lens.ui.highlights")
local debounce    = require("sql-lens.utils.debounce")
local secrets     = require("sql-lens.utils.secrets")

M._config  = {}
M._enabled = true

function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", config_mod.defaults, opts or {})
  config_mod.validate(M._config)

  local secrets_cfg = M._config.secrets or {}
  if secrets_cfg.use_dotenv then
    secrets.load_dotenv()
  end

  highlights.setup()
  hints_mod.setup(M._config.thresholds)
  conn_mgr.setup(M._config.connections, secrets_cfg)

  local km = M._config.keymaps
  if km then
    vim.keymap.set("n", km.toggle,      M.toggle,          { desc = "SqlLens: toggle" })
    vim.keymap.set("n", km.explain,     M.explain_current, { desc = "SqlLens: explain" })
    vim.keymap.set("n", km.show_detail, M.show_detail,     { desc = "SqlLens: detail" })
    vim.keymap.set("n", km.connect,     M.connect,         { desc = "SqlLens: connect" })
    if km.run then
      vim.keymap.set("n", km.run, M.run_current, { desc = "SqlLens: run query" })
      vim.keymap.set("v", km.run, M.run_selection, { desc = "SqlLens: run selection" })
    end
    if km.run_all then
      vim.keymap.set("n", km.run_all, M.run_all, { desc = "SqlLens: run all queries" })
    end
    if km.report then
      vim.keymap.set("n", km.report, M.report, { desc = "SqlLens: HTML report" })
    end
    if km.pick_db then
      vim.keymap.set("n", km.pick_db, M.pick_database, { desc = "SqlLens: pick database" })
    end
    if km.explore then
      vim.keymap.set("n", km.explore, M.explore_tables, { desc = "SqlLens: explore tables" })
    end
    if km.history then
      vim.keymap.set("n", km.history, M.show_history, { desc = "SqlLens: query history" })
    end
    if km.format then
      vim.keymap.set({"n", "v"}, km.format, function() require("sql-lens.formatter").format_buffer() end, { desc = "SqlLens: format SQL" })
    end
    if km.schema_diff then
      vim.keymap.set("n", km.schema_diff, function() require("sql-lens.schema_diff").pick_and_compare() end, { desc = "SqlLens: schema diff" })
    end
    if km.cost_trend then
      vim.keymap.set("n", km.cost_trend, M.show_cost_trend, { desc = "SqlLens: cost trend" })
    end
    if km.er_diagram then
      vim.keymap.set("n", km.er_diagram, function() require("sql-lens.er_diagram").generate() end, { desc = "SqlLens: ER diagram" })
    end
    if km.columns then
      vim.keymap.set("n", km.columns, function() require("sql-lens.column_picker").pick() end, { desc = "SqlLens: column picker" })
    end
    if km.snippets then
      vim.keymap.set("n", km.snippets, function() require("sql-lens.snippets").pick() end, { desc = "SqlLens: snippets" })
    end
    if km.result_diff then
      vim.keymap.set("n", km.result_diff, M.result_diff_current, { desc = "SqlLens: result diff" })
    end
    if km.chart then
      vim.keymap.set("n", km.chart, function() require("sql-lens.chart").show() end, { desc = "SqlLens: chart view" })
    end
    if km.dashboard then
      vim.keymap.set("n", km.dashboard, function() require("sql-lens.dashboard").show() end, { desc = "SqlLens: table sizes" })
    end
    if km.dep_graph then
      vim.keymap.set("n", km.dep_graph, function() require("sql-lens.dep_graph").generate() end, { desc = "SqlLens: dependency graph" })
    end
  end

  -- Apply history config
  local hist_cfg = M._config.history or {}
  local history = require("sql-lens.history")
  if hist_cfg.max_entries then history._max = hist_cfg.max_entries end
  if hist_cfg.max_days then history._max_days = hist_cfg.max_days end

  -- Register nvim-cmp source if available
  require("sql-lens.completion").setup()
end

function M.attach_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg   = M._config.trigger
  local lint_cfg = M._config.lint or {}
  local lint_enabled = lint_cfg.enable_offline and true or false

  -- Auto-restore saved file → connection binding
  if not conn_mgr.get_active(bufnr) then
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath and filepath ~= "" then
      local binding = require("sql-lens.bookmarks").get_binding(filepath)
      if binding then
        -- Find matching connection and set active
        for _, conn in ipairs(conn_mgr._connections) do
          if conn.config.name == binding.connection then
            conn_mgr._active[bufnr] = conn
            conn_mgr._disconnected[bufnr] = nil
            if binding.database and binding.database ~= "" then
              conn.config.dbname = binding.database
            end
            break
          end
        end
      end
    end
  end

  local lint_debounced
  if lint_enabled then
    lint_debounced = debounce.debounce(
      function() M._run_lint(bufnr) end,
      150
    )
  end

  -- Server explain: runs slower with longer debounce
  local analyze_debounced = debounce.debounce(
    function() M._run_all_analysis(bufnr) end,
    cfg.debounce_ms
  )

  local aug = vim.api.nvim_create_augroup("SqlLens_buf_" .. bufnr, { clear = true })

  if cfg.on_change then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer   = bufnr,
      group    = aug,
      callback = function()
        if lint_enabled and lint_debounced then
          lint_debounced()
        end
        analyze_debounced()   -- slow server explain
      end,
    })
  end

  if cfg.on_write then
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer   = bufnr,
      group    = aug,
      callback = function()
        if lint_enabled then
          M._run_lint(bufnr)
        end
        M._run_all_analysis(bufnr)
      end,
    })
  end

  -- Run on first attach
  if lint_enabled then
    M._run_lint(bufnr)
  end
  M._run_all_analysis(bufnr)
end

---Collect offline lint errors for all statements
---@return table[] lint_errors, table[] statements
function M._collect_lint(bufnr)
  local statements = extractor.get_all_statements(bufnr)
  if not statements or #statements == 0 then return {}, {} end

  local all_errors = {}
  -- Track which statements have errors (by start_line)
  local errored_stmts = {}
  for _, stmt in ipairs(statements) do
    local errs = lint_mod.lint(stmt.sql, stmt.start_line)
    if #errs > 0 then
      vim.list_extend(all_errors, errs)
      for _, e in ipairs(errs) do
        if e.level == "error" then
          errored_stmts[stmt.start_line] = true
        end
      end
    end
  end

  return all_errors, statements, errored_stmts
end

---FAST offline lint only (on TextChanged, before server respond)
function M._run_lint(bufnr)
  if not M._enabled then return end

  local all_errors, statements = M._collect_lint(bufnr)

  vt.clear(bufnr)
  if #all_errors > 0 then
    vt.render_lint_errors(bufnr, all_errors)
  end
end

---Analyze ALL SQL statements: offline lint + server EXPLAIN
function M._run_all_analysis(bufnr)
  if not M._enabled then return end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vt.clear(bufnr)
    vt.render_summary(bufnr, 0, "No connection — use :SqlLensConnect", "warn")
    return
  end

  local lint_cfg = M._config.lint or {}
  local lint_enabled = lint_cfg.enable_offline and true or false

  local all_errors, statements, errored_stmts
  if lint_enabled then
    all_errors, statements, errored_stmts = M._collect_lint(bufnr)
  else
    statements = extractor.get_all_statements(bufnr) or {}
    all_errors = {}
    errored_stmts = {}
  end
  if #statements == 0 then return end

  vt.clear(bufnr)

  -- Render offline lint errors first (visible immediately)
  if lint_enabled and #all_errors > 0 then
    vt.render_lint_errors(bufnr, all_errors)
  end

  -- Run server explain for each statement (async)
  for _, stmt in ipairs(statements) do
    if #stmt.sql >= (M._config.trigger.min_length or 10) then
      -- Only skip THIS statement if IT has a hard lint error
      if not errored_stmts[stmt.start_line] then
        M._analyze_one(bufnr, conn, stmt.sql, stmt.start_line)
      end
    end
  end
end

---Analyze a single SQL statement via server and render inline
function M._analyze_one(bufnr, conn, sql, start_line)
  conn:explain(sql, function(err, raw_data)
    if err then
      local err_str = tostring(err or "")
      local first_line = err_str:match("([^\r\n]+)") or err_str
      local msg = first_line
      if #msg > 80 then
        msg = msg:sub(1, 77) .. "..."
      end
      vt.render_summary(bufnr, start_line, "Error: " .. msg, "error")
      return
    end

    local plan  = parser.parse(raw_data, conn.type)
    local hints = hints_mod.analyze(plan)

    float.store(plan, hints)

    -- Record cost trend
    local cost_trend = require("sql-lens.cost_trend")
    cost_trend.record(sql, plan.total_cost, plan.execution_time, conn.config.name)

    local level = #vim.tbl_filter(function(h) return h.level == "error" end, hints) > 0 and "error"
               or #vim.tbl_filter(function(h) return h.level == "warn"  end, hints) > 0 and "warn"
               or "ok"

    local summary = hints_mod.summary_line(plan, hints)

    -- Append trend indicator
    local trend = cost_trend.get_trend(sql)
    local trend_text = cost_trend.trend_text(trend)
    if trend_text then
      summary = summary .. "  " .. trend_text
    end

    vt.render_summary(bufnr, start_line, summary, level)
    if #hints > 0 then
      vt.render_hints(bufnr, start_line, hints)
    end
  end)
end

---Analyze only the statement at cursor
function M._run_analysis(bufnr)
  if not M._enabled then return end

  local sql, start_line = extractor.get_statement_at_cursor(bufnr)
  if not sql or #sql < (M._config.trigger.min_length or 10) then return end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vt.render_summary(bufnr, start_line or 0, "No connection — use :SqlLensConnect", "warn")
    return
  end

  vt.clear(bufnr)
  M._analyze_one(bufnr, conn, sql, start_line or 0)
end

function M.toggle()
  M._enabled = not M._enabled
  if not M._enabled then
    vt.clear(vim.api.nvim_get_current_buf())
  else
    M._run_all_analysis(vim.api.nvim_get_current_buf())
  end
  vim.notify("SqlLens: " .. (M._enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

function M.explain_current()
  M._run_all_analysis(vim.api.nvim_get_current_buf())
end

function M.show_detail()
  float.show_last()
end

function M.connect()
  conn_mgr.pick_and_connect()
end

function M.disconnect()
  local bufnr = vim.api.nvim_get_current_buf()
  conn_mgr.set_active(bufnr, nil)
  vt.clear(bufnr)
  vim.notify("SqlLens: Disconnected", vim.log.levels.INFO)
end

function M.use_connection(name)
  conn_mgr.set_active_by_name(vim.api.nvim_get_current_buf(), name)
end

function M.pick_database()
  conn_mgr.pick_database()
end

---Execute the SQL statement at cursor and show results
function M.run_current()
  local result_ui = require("sql-lens.ui.result")
  local bufnr = vim.api.nvim_get_current_buf()

  local sql, start_line = extractor.get_statement_at_cursor(bufnr)
  if not sql or #sql < 3 then
    vim.notify("SqlLens: No SQL statement at cursor", vim.log.levels.WARN)
    return
  end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No connection — use :SqlLensConnect", vim.log.levels.WARN)
    return
  end

  local lint_cfg = M._config.lint or {}
  if lint_cfg.enable_offline then
    local lint_errors = lint_mod.lint(sql, start_line)
    local hard_errors = vim.tbl_filter(function(e) return e.level == "error" end, lint_errors)
    if #hard_errors > 0 then
      vt.clear(bufnr)
      vt.render_lint_errors(bufnr, lint_errors)
      result_ui.show_error(
        table.concat(vim.tbl_map(function(e) return e.message end, hard_errors), "\n"),
        sql
      )
      return
    end
  end

  vim.notify("SqlLens: Running query...", vim.log.levels.INFO)

  local history = require("sql-lens.history")
  history.add(sql, conn)

  conn:execute(sql, function(err, stdout)
    if err then
      result_ui.show_error(err, sql)
    else
      result_ui.show(stdout, sql)
    end
  end)
end

---Run a list of SQL statements one by one and show labeled results
local function run_statements(statements, conn)
  local result_ui = require("sql-lens.ui.result")
  local total = #statements
  local results = {}
  local done = 0

  vim.notify(string.format("SqlLens: Running %d queries...", total), vim.log.levels.INFO)

  local history = require("sql-lens.history")
  for _, stmt in ipairs(statements) do
    history.add(stmt, conn)
  end

  for i, stmt in ipairs(statements) do
    conn:execute(stmt, function(err, stdout)
      results[i] = { sql = stmt, output = stdout or "", err = err }
      done = done + 1
      if done == total then
        result_ui.show_multi(results)
      end
    end)
  end
end

---Split raw SQL text into individual statements
local function split_sql(text)
  local stmts = {}
  local current = {}
  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^%-%-") then
      table.insert(current, line)
      if line:match(";%s*$") then
        local sql = table.concat(current, "\n"):gsub("%s+$", "")
        if #sql >= 3 then
          table.insert(stmts, sql)
        end
        current = {}
      end
    elseif #current == 0 then
      -- skip blank/comment between statements
    end
  end
  -- Remaining without trailing semicolon
  if #current > 0 then
    local sql = table.concat(current, "\n"):gsub("%s+$", "")
    if #sql >= 3 then
      table.insert(stmts, sql)
    end
  end
  return stmts
end

---Execute visually selected SQL
function M.run_selection()
  local result_ui = require("sql-lens.ui.result")
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  local start_line = vim.fn.line("'<") - 1
  local end_line   = vim.fn.line("'>")
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
  local sql = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

  if #sql < 3 then
    vim.notify("SqlLens: No SQL in selection", vim.log.levels.WARN)
    return
  end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No connection — use :SqlLensConnect", vim.log.levels.WARN)
    return
  end

  local stmts = split_sql(sql)
  if #stmts <= 1 then
    -- Single statement: use normal show
    vim.notify("SqlLens: Running query...", vim.log.levels.INFO)
    conn:execute(sql, function(err, stdout)
      if err then
        result_ui.show_error(err, sql)
      else
        result_ui.show(stdout, sql)
      end
    end)
  else
    run_statements(stmts, conn)
  end
end

---Generate HTML report for all queries across all connections
function M.report()
  require("sql-lens.report").run(vim.api.nvim_get_current_buf())
end

---Execute ALL SQL statements in buffer sequentially
function M.run_all()
  local bufnr = vim.api.nvim_get_current_buf()

  local statements = extractor.get_all_statements(bufnr)
  if not statements or #statements == 0 then
    vim.notify("SqlLens: No SQL statements found", vim.log.levels.WARN)
    return
  end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No connection — use :SqlLensConnect", vim.log.levels.WARN)
    return
  end

  local stmts = {}
  for _, stmt in ipairs(statements) do
    table.insert(stmts, stmt.sql)
  end

  run_statements(stmts, conn)
end

function M.explore_tables()
  conn_mgr.explore_tables()
end

function M.result_diff_current()
  local result_ui = require("sql-lens.ui.result")
  local rdiff = require("sql-lens.result_diff")
  local bufnr = vim.api.nvim_get_current_buf()

  local sql = extractor.get_statement_at_cursor(bufnr)
  if not sql or #sql < 3 then
    vim.notify("SqlLens: No SQL statement at cursor", vim.log.levels.WARN)
    return
  end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No connection", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Running query for diff...", vim.log.levels.INFO)
  conn:execute(sql, function(err, stdout)
    if err then
      vim.notify("SqlLens: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    rdiff.diff(stdout, sql)
  end)
end

function M.show_cost_trend()
  local bufnr = vim.api.nvim_get_current_buf()
  local sql = extractor.get_statement_at_cursor(bufnr)
  if not sql or #sql < 3 then
    vim.notify("SqlLens: No SQL statement at cursor", vim.log.levels.WARN)
    return
  end
  require("sql-lens.cost_trend").show_trend(sql)
end

-- Filter modes: 1 = conn+db, 2 = conn (all dbs), 3 = all connections
function M.show_history(mode)
  mode = mode or 1
  local history = require("sql-lens.history")
  local picker = require("sql-lens.ui.picker")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)

  local conn_name = conn and conn.config.name or nil
  local dbname = conn and conn.config.dbname or nil

  -- If no connection, force mode 3
  if not conn_name then mode = 3 end

  local entries, title
  if mode == 1 then
    entries = history.get_by_connection(conn_name, dbname)
    local suffix = conn_name
    if dbname and dbname ~= "" then suffix = suffix .. "/" .. dbname end
    title = suffix .. " — <Tab> ▸ all dbs"
    -- Fallback to mode 2 if empty
    if #entries == 0 then
      mode = 2
      entries = history.get_by_connection(conn_name, nil)
      title = conn_name .. " (all dbs) — <Tab> ▸ all conns"
    end
    -- Fallback to mode 3 if still empty
    if #entries == 0 then
      mode = 3
      entries = history.get_all()
      title = "All connections"
    end
  elseif mode == 2 then
    entries = history.get_by_connection(conn_name, nil)
    title = conn_name .. " (all dbs) — <Tab> ▸ all conns"
    if #entries == 0 then
      mode = 3
      entries = history.get_all()
      title = "All connections"
    end
  else
    entries = history.get_all()
    title = "All connections — <Tab> ▸ current"
  end

  if #entries == 0 then
    vim.notify("SqlLens: No query history", vim.log.levels.INFO)
    return
  end

  local labels, details = history.build_display(entries)

  picker.open(labels, {
    prompt = title,
    details = details,
    on_tab = function()
      -- Cycle: 1 → 2 → 3 → 1
      local next_mode = (mode % 3) + 1
      M.show_history(next_mode)
    end,
    on_select = function(label)
      for i, l in ipairs(labels) do
        if l == label then
          local entry = entries[i]
          if not conn then
            vim.notify("SqlLens: No connection — use :SqlLensConnect", vim.log.levels.WARN)
            return
          end
          local result_ui = require("sql-lens.ui.result")
          vim.notify("SqlLens: Re-running query...", vim.log.levels.INFO)
          history.add(entry.sql, conn)
          conn:execute(entry.sql, function(err, stdout)
            if err then
              result_ui.show_error(err, entry.sql)
            else
              result_ui.show(stdout, entry.sql)
            end
          end)
          return
        end
      end
    end,
  })
end

return M
