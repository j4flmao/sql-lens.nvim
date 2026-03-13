local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local MSSQL = setmetatable({}, { __index = Base })
MSSQL.__index = MSSQL

function MSSQL.new(config)
  local self = Base.new(config)
  self.type = "sqlserver"
  return setmetatable(self, MSSQL)
end

function MSSQL:_args()
  local c = self.config
  local args = { "sqlcmd" }

  if c.host then
    if c.port and not c.host:match("\\") then
      vim.list_extend(args, { "-S", string.format("%s,%s", c.host, c.port) })
    else
      vim.list_extend(args, { "-S", c.host })
    end
  end

  if c.user and c.user ~= "" then
    vim.list_extend(args, { "-U", c.user, "-P", c.password or "" })
  else
    table.insert(args, "-E")
  end

  if c.dbname then -- optional: omit to pick database later via :SqlLensDB
    vim.list_extend(args, { "-d", c.dbname })
  end

  if type(c.sqlcmd_args) == "table" then
    vim.list_extend(args, c.sqlcmd_args)
  elseif type(c.sqlcmd_args) == "string" and c.sqlcmd_args ~= "" then
    table.insert(args, c.sqlcmd_args)
  end

  return args
end

---Lint SQL using NOEXEC so it is parsed/compiled but not executed
---@param sql string
---@param cb fun(err?: string)
function MSSQL:lint(sql, cb)
  local args = self:_args()
  vim.list_extend(args, { "-W", "-s", "\t" })

  local tmpfile = vim.fn.tempname() .. ".sql"
  local batch = table.concat({
    "SET NOEXEC ON;",
    "GO",
    sql,
    "GO",
    "SET NOEXEC OFF;",
  }, "\n")
  vim.fn.writefile(vim.split(batch, "\n"), tmpfile)
  vim.list_extend(args, { "-i", tmpfile })

  async.job(args, function(code, stdout, stderr)
    vim.fn.delete(tmpfile)
    if code ~= 0 then
      cb(stderr or stdout or "sqlcmd lint error")
    else
      cb(nil)
    end
  end)
end

function MSSQL:wrap_explain(sql)
  -- Each SET SHOWPLAN must be alone in its batch (separated by GO)
  -- Part 1: SHOWPLAN_ALL for estimated plan
  -- Part 2: STATISTICS TIME/IO for actual execution
  return table.concat({
    "SET SHOWPLAN_ALL ON;",
    "GO",
    sql,
    "GO",
    "SET SHOWPLAN_ALL OFF;",
    "GO",
    "SET NOCOUNT ON;",
    "SET STATISTICS TIME ON;",
    "SET STATISTICS IO ON;",
    "GO",
    sql,
    "GO",
    "SET STATISTICS TIME OFF;",
    "SET STATISTICS IO OFF;",
  }, "\n")
end

function MSSQL:explain(sql, cb)
  local args = self:_args()
  -- Use pipe separator and compact output for easier parsing
  vim.list_extend(args, { "-h", "-1", "-W", "-s", "\t" })

  local tmpfile = vim.fn.tempname() .. ".sql"
  vim.fn.writefile(vim.split(self:wrap_explain(sql), "\n"), tmpfile)
  vim.list_extend(args, { "-i", tmpfile })

  async.job(args, function(code, stdout, stderr)
    vim.fn.delete(tmpfile)
    if code ~= 0 then return cb(stderr, nil) end
    cb(nil, { raw = stdout, type = "showplan_stats" })
  end)
end

---Execute SQL and return raw result
function MSSQL:execute(sql, cb)
  local args = self:_args()
  -- -W trims trailing spaces, -s tab separator for clean columns
  vim.list_extend(args, { "-W", "-s", "\t" })

  local tmpfile = vim.fn.tempname() .. ".sql"
  local wrapped = table.concat({
    "SET STATISTICS TIME ON;",
    "SET STATISTICS IO ON;",
    "GO",
    sql,
    "GO",
    "SET STATISTICS TIME OFF;",
    "SET STATISTICS IO OFF;",
  }, "\n")
  vim.fn.writefile(vim.split(wrapped, "\n"), tmpfile)
  vim.list_extend(args, { "-i", tmpfile })

  async.job(args, function(code, stdout, stderr)
    vim.fn.delete(tmpfile)
    if code ~= 0 then return cb(stderr or "sqlcmd error", nil) end
    cb(nil, stdout)
  end)
end

function MSSQL:ping(cb)
  local args = self:_args()
  vim.list_extend(args, { "-Q", "SELECT 1" })
  async.job(args, function(code) cb(code == 0) end)
end

function MSSQL:preview_query(tbl)
  return "SELECT TOP 50 * FROM [" .. tbl .. "];"
end

function MSSQL:list_tables(cb)
  local args = self:_args()
  vim.list_extend(args, {
    "-h", "-1", "-W", "-Q",
    "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME",
  })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local tables = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" and not name:match("^%-%-") then table.insert(tables, name) end
    end
    cb(nil, tables)
  end)
end

function MSSQL:list_columns(tbl, cb)
  local args = self:_args()
  local sql = string.format(
    "SELECT COLUMN_NAME + ' ' + DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '%s' ORDER BY ORDINAL_POSITION",
    tbl
  )
  vim.list_extend(args, { "-h", "-1", "-W", "-Q", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local cols = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" and not name:match("^%-%-") then table.insert(cols, name) end
    end
    cb(nil, cols)
  end)
end

function MSSQL:list_databases(cb)
  local args = self:_args()
  vim.list_extend(args, { "-h", "-1", "-W", "-Q", "SELECT name FROM sys.databases ORDER BY name" })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local dbs = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" and not name:match("^%-%-") then
        table.insert(dbs, name)
      end
    end
    cb(nil, dbs)
  end)
end

return MSSQL
