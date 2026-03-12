local M = {}

local secrets = require("sql-lens.utils.secrets")

local adapters = {
  postgres  = require("sql-lens.connections.postgres"),
  mysql     = require("sql-lens.connections.mysql"),
  sqlserver = require("sql-lens.connections.sqlserver"),
  sqlite    = require("sql-lens.connections.sqlite"),
}

M._connections = {}
M._active = {}      -- bufnr → connection instance
M._disconnected = {} -- bufnr → true if explicitly disconnected

function M.setup(conn_configs)
  M._connections = {}
  for _, cfg in ipairs(conn_configs or {}) do
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
        vim.notify("SqlLens: Switched to database '" .. choice .. "'", vim.log.levels.INFO)
      end,
    })
  end)
end

return M
