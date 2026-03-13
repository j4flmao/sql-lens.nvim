local M = {}

local secrets = require("sql-lens.utils.secrets")

local adapters = {
  postgres  = require("sql-lens.connections.postgres"),
  mysql     = require("sql-lens.connections.mysql"),
  sqlserver = require("sql-lens.connections.sqlserver"),
  sqlite    = require("sql-lens.connections.sqlite"),
  mongodb   = require("sql-lens.connections.mongodb"),
}

M._connections = {}
M._active = {}      -- bufnr → connection instance
M._disconnected = {} -- bufnr → true if explicitly disconnected

function M.setup(conn_configs)
  M._connections = {}

  -- Merge config connections + saved bookmarks
  local all_configs = {}
  for _, cfg in ipairs(conn_configs or {}) do
    table.insert(all_configs, cfg)
  end
  local bookmarks = require("sql-lens.bookmarks").load_all()
  for _, bm in ipairs(bookmarks) do
    -- Skip if a config connection with same name already exists
    local exists = false
    for _, cfg in ipairs(all_configs) do
      if cfg.name == bm.name then exists = true; break end
    end
    if not exists then
      table.insert(all_configs, bm)
    end
  end

  for _, cfg in ipairs(all_configs) do
    local resolved = secrets.resolve_connection(cfg)
    local adapter = adapters[resolved.type]
    if adapter then
      table.insert(M._connections, adapter.new(resolved))
    else
      vim.notify("SqlLens: Unknown DB type: " .. tostring(cfg.type), vim.log.levels.WARN)
    end
  end

  if #M._connections == 1 then
    M._default = M._connections[1]
  end
end

function M.get_active(bufnr)
  if M._disconnected[bufnr] then return nil end
  return M._active[bufnr] or M._default
end

function M.set_active(bufnr, conn)
  M._active[bufnr] = conn
  if conn == nil then
    M._disconnected[bufnr] = true
  else
    M._disconnected[bufnr] = nil
  end
end

function M.set_active_by_name(bufnr, name)
  for _, conn in ipairs(M._connections) do
    if conn.config.name == name then
      M._active[bufnr] = conn
      vim.notify("SqlLens: Using connection '" .. name .. "'", vim.log.levels.INFO)
      return
    end
  end
  vim.notify("SqlLens: Connection '" .. name .. "' not found", vim.log.levels.ERROR)
end

function M.pick_and_connect()
  if #M._connections == 0 then
    vim.notify("SqlLens: No connections configured. See :help sql-lens-connections", vim.log.levels.WARN)
    return
  end

  vim.ui.select(M._connections, {
    prompt = "SqlLens — Choose connection:",
    format_item = function(c)
      local db = c.config.dbname or "(no database)"
      return c.config.name .. " (" .. c.type .. " → " .. db .. ")"
    end,
  }, function(choice)
    if choice then
      local bufnr = vim.api.nvim_get_current_buf()
      M._active[bufnr] = choice
      M._disconnected[bufnr] = nil
      if not choice.config.dbname or choice.config.dbname == "" then
        vim.notify("SqlLens: Connected to '" .. choice.config.name .. "' (no database selected)", vim.log.levels.INFO)
        vim.defer_fn(function() M.pick_database() end, 100)
      else
        vim.notify("SqlLens: Connected to '" .. choice.config.name .. "' → " .. choice.config.dbname, vim.log.levels.INFO)
      end
    end
  end)
end

function M.pick_database()
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = M.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No active connection — use :SqlLensConnect first", vim.log.levels.WARN)
    return
  end

  if not conn.list_databases then
    vim.notify("SqlLens: This adapter does not support listing databases", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Fetching databases...", vim.log.levels.INFO)

  conn:list_databases(function(err, dbs)
    if err then
      vim.notify("SqlLens: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    if #dbs == 0 then
      vim.notify("SqlLens: No databases found", vim.log.levels.WARN)
      return
    end

    local picker = require("sql-lens.ui.picker")
    picker.open(dbs, {
      prompt = "Database (" .. conn.config.name .. ")",
      on_select = function(choice)
        conn.config.dbname = choice
        require("sql-lens.completion").invalidate()
        vim.notify("SqlLens: Switched to database '" .. choice .. "'", vim.log.levels.INFO)
      end,
    })
  end)
end

function M.explore_tables()
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = M.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No active connection — use :SqlLensConnect first", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Fetching tables...", vim.log.levels.INFO)

  conn:list_tables(function(err, tables)
    if err then
      vim.notify("SqlLens: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    if #tables == 0 then
      vim.notify("SqlLens: No tables found", vim.log.levels.WARN)
      return
    end

    local picker = require("sql-lens.ui.picker")
    local label = conn.type == "mongodb" and "Collections" or "Tables"
    picker.open(tables, {
      prompt = label .. " (" .. (conn.config.dbname or conn.config.name) .. ")",
      on_select = function(tbl)
        local query = conn:preview_query(tbl)
        -- Insert at cursor position
        local row = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(bufnr, row, row, false, { query })
        vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
        vim.notify("SqlLens: Inserted query for '" .. tbl .. "'", vim.log.levels.INFO)
      end,
    })
  end)
end

return M
