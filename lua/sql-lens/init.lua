local M = {}

local config_mod  = require("sql-lens.config")
local conn_mgr    = require("sql-lens.connections")
local extractor   = require("sql-lens.analyzer.extractor")
local parser      = require("sql-lens.analyzer.parser")
local hints_mod   = require("sql-lens.analyzer.hints")
local vt          = require("sql-lens.ui.virtual_text")
local float       = require("sql-lens.ui.float")
local highlights  = require("sql-lens.ui.highlights")
local debounce    = require("sql-lens.utils.debounce")

M._config  = {}
M._enabled = true

function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", config_mod.defaults, opts or {})
  config_mod.validate(M._config)

  highlights.setup()
  hints_mod.setup(M._config.thresholds)
  conn_mgr.setup(M._config.connections)

  local km = M._config.keymaps
  if km then
    vim.keymap.set("n", km.toggle,      M.toggle,          { desc = "SqlLens: toggle" })
    vim.keymap.set("n", km.explain,     M.explain_current, { desc = "SqlLens: explain" })
    vim.keymap.set("n", km.show_detail, M.show_detail,     { desc = "SqlLens: detail" })
    vim.keymap.set("n", km.connect,     M.connect,         { desc = "SqlLens: connect" })
    if km.run then
      vim.keymap.set("n", km.run, M.run_current, { desc = "SqlLens: run query" })
    end
    if km.run_all then
      vim.keymap.set("n", km.run_all, M.run_all, { desc = "SqlLens: run all queries" })
    end
    if km.report then
      vim.keymap.set("n", km.report, M.report, { desc = "SqlLens: HTML report" })
    end
  end
end

function M.attach_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg   = M._config.trigger
  local analyze_debounced = debounce.debounce(
    function() M._run_all_analysis(bufnr) end,
    cfg.debounce_ms
  )

  local aug = vim.api.nvim_create_augroup("SqlLens_buf_" .. bufnr, { clear = true })

  if cfg.on_change then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer   = bufnr,
      group    = aug,
      callback = analyze_debounced,
    })
  end

  if cfg.on_write then
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer   = bufnr,
      group    = aug,
      callback = function() M._run_all_analysis(bufnr) end,
    })
  end

  M._run_all_analysis(bufnr)
end

---Analyze ALL SQL statements in the buffer
function M._run_all_analysis(bufnr)
  if not M._enabled then return end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vt.clear(bufnr)
    vt.render_summary(bufnr, 0, "No connection — use :SqlLensConnect", "warn")
    return
  end

  local statements = extractor.get_all_statements(bufnr)
  if not statements or #statements == 0 then return end

  -- Clear all previous marks once before rendering new results
  vt.clear(bufnr)

  for _, stmt in ipairs(statements) do
    if #stmt.sql >= (M._config.trigger.min_length or 10) then
      M._analyze_one(bufnr, conn, stmt.sql, stmt.start_line)
    end
  end
end

---Analyze a single SQL statement and render inline
function M._analyze_one(bufnr, conn, sql, start_line)
  conn:explain(sql, function(err, raw_data)
    if err then
      vt.render_summary(bufnr, start_line, "Error: " .. tostring(err):sub(1, 60), "error")
      return
    end

    local plan  = parser.parse(raw_data, conn.type)
    local hints = hints_mod.analyze(plan)

    float.store(plan, hints)

    local level = #vim.tbl_filter(function(h) return h.level == "error" end, hints) > 0 and "error"
               or #vim.tbl_filter(function(h) return h.level == "warn"  end, hints) > 0 and "warn"
               or "ok"

    local summary = hints_mod.summary_line(plan, hints)

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

---Execute the SQL statement at cursor and show results
function M.run_current()
  local result_ui = require("sql-lens.ui.result")
  local bufnr = vim.api.nvim_get_current_buf()

  local sql, _ = extractor.get_statement_at_cursor(bufnr)
  if not sql or #sql < 3 then
    vim.notify("SqlLens: No SQL statement at cursor", vim.log.levels.WARN)
    return
  end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No connection — use :SqlLensConnect", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Running query...", vim.log.levels.INFO)

  conn:execute(sql, function(err, stdout)
    if err then
      result_ui.show_error(err, sql)
    else
      result_ui.show(stdout, sql)
    end
  end)
end

---Generate HTML report for all queries across all connections
function M.report()
  require("sql-lens.report").run(vim.api.nvim_get_current_buf())
end

---Execute ALL SQL statements in buffer sequentially
function M.run_all()
  local result_ui = require("sql-lens.ui.result")
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

  -- Concat all queries into one batch
  local all_sql = {}
  for _, stmt in ipairs(statements) do
    table.insert(all_sql, stmt.sql .. ";")
  end
  local batch = table.concat(all_sql, "\n")

  vim.notify(string.format("SqlLens: Running %d queries...", #statements), vim.log.levels.INFO)

  conn:execute(batch, function(err, stdout)
    if err then
      result_ui.show_error(err, batch)
    else
      result_ui.show(stdout, string.format("(%d queries)", #statements))
    end
  end)
end

return M
