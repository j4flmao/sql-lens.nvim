local M = {}

local secrets = require("sql-lens.utils.secrets")

local adapters = {
  postgres  = require("sql-lens.connections.postgres"),
  mysql     = require("sql-lens.connections.mysql"),
  sqlserver = require("sql-lens.connections.sqlserver"),
  sqlite    = require("sql-lens.connections.sqlite"),
}

M._connections = {}
M._active = {}  -- bufnr → connection instance

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
  return M._active[bufnr] or M._default
end

function M.set_active(bufnr, conn)
  M._active[bufnr] = conn
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
      return c.config.name .. " (" .. c.type .. ")"
    end,
  }, function(choice)
    if choice then
      local bufnr = vim.api.nvim_get_current_buf()
      M._active[bufnr] = choice
      vim.notify("SqlLens: Connected to '" .. choice.config.name .. "'", vim.log.levels.INFO)
    end
  end)
end

return M
