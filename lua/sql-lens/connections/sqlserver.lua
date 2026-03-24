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

---Filter sqlcmd noise lines
local function is_noise(line)
  return line:match("^%-%-")
      or line:match("rows? affected")
      or line:match("^Changed database")
      or line:match("^%(%d+ rows?")
      or line:match("^$")
end

function MSSQL:list_tables(cb)
  local args = self:_args()
  vim.list_extend(args, {
    "-h", "-1", "-W", "-Q",
    "SET NOCOUNT ON; SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME",
  })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local tables = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" and not is_noise(name) then table.insert(tables, name) end
    end
    cb(nil, tables)
  end)
end

function MSSQL:list_columns(tbl, cb)
  local args = self:_args()
  local sql = string.format(
    "SET NOCOUNT ON; SELECT COLUMN_NAME + ' ' + DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '%s' ORDER BY ORDINAL_POSITION",
    tbl
  )
  vim.list_extend(args, { "-h", "-1", "-W", "-Q", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local cols = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" and not is_noise(name) then table.insert(cols, name) end
    end
    cb(nil, cols)
  end)
end

function MSSQL:list_table_sizes(cb)
  local args = self:_args()
  local sql = "SET NOCOUNT ON; SELECT t.name, SUM(p.rows), SUM(a.total_pages) * 8192 FROM sys.tables t JOIN sys.indexes i ON t.object_id = i.object_id JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id JOIN sys.allocation_units a ON p.partition_id = a.container_id WHERE i.index_id IN (0, 1) GROUP BY t.name ORDER BY SUM(a.total_pages) DESC"
  vim.list_extend(args, { "-h", "-1", "-W", "-s", "\t", "-Q", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local sizes = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local trimmed = line:match("^%s*(.-)%s*$")
      if not (is_noise(trimmed) or trimmed == "") then
        local parts = vim.split(trimmed, "\t")
        if #parts >= 3 then
          table.insert(sizes, {
            name = parts[1]:match("^%s*(.-)%s*$"),
            row_count = tonumber(parts[2]) or 0,
            bytes = tonumber(parts[3]) or 0,
          })
        end
      end
    end
    cb(nil, sizes)
  end)
end

function MSSQL:list_foreign_keys(cb)
  local args = self:_args()
  local sql = "SET NOCOUNT ON; SELECT tp.name, cp.name, tr.name, cr.name FROM sys.foreign_key_columns fkc JOIN sys.tables tp ON fkc.parent_object_id = tp.object_id JOIN sys.columns cp ON fkc.parent_object_id = cp.object_id AND fkc.parent_column_id = cp.column_id JOIN sys.tables tr ON fkc.referenced_object_id = tr.object_id JOIN sys.columns cr ON fkc.referenced_object_id = cr.object_id AND fkc.referenced_column_id = cr.column_id ORDER BY tp.name"
  vim.list_extend(args, { "-h", "-1", "-W", "-s", "\t", "-Q", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local fks = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local parts = vim.split(line, "\t")
      if #parts >= 4 and not parts[1]:match("^%-") then
        table.insert(fks, {
          from_table = parts[1]:match("^%s*(.-)%s*$"),
          from_column = parts[2]:match("^%s*(.-)%s*$"),
          to_table = parts[3]:match("^%s*(.-)%s*$"),
          to_column = parts[4]:match("^%s*(.-)%s*$"),
        })
      end
    end
    cb(nil, fks)
  end)
end

---Return uniqueness info (unique indexes and primary keys)
function MSSQL:list_unique_info(cb)
  local args = self:_args()
  local sql = [[
    SET NOCOUNT ON;
    SELECT t.name, i.name, c.name, ic.key_ordinal
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.tables t ON t.object_id = i.object_id
    JOIN sys.columns c ON c.object_id = i.object_id AND c.column_id = ic.column_id
    WHERE i.is_unique = 1 OR i.is_primary_key = 1
    ORDER BY t.name, i.name, ic.key_ordinal
  ]]
  vim.list_extend(args, { "-h", "-1", "-W", "-s", "\t", "-Q", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local groups = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local parts = vim.split(line, "\t")
      local tbl, idx, col = parts[1], parts[2], parts[3]
      if tbl and idx and col and tbl ~= "" and idx ~= "" and col ~= "" then
        groups[tbl] = groups[tbl] or {}
        groups[tbl][idx] = groups[tbl][idx] or {}
        table.insert(groups[tbl][idx], col)
      end
    end
    local info = { unique_single = {}, unique_composites = {} }
    for tbl, idx_map in pairs(groups) do
      info.unique_single[tbl] = {}
      info.unique_composites[tbl] = {}
      for _, cols in pairs(idx_map) do
        if #cols == 1 then
          info.unique_single[tbl][cols[1]] = true
        elseif #cols > 1 then
          table.sort(cols)
          table.insert(info.unique_composites[tbl], cols)
        end
      end
    end
    cb(nil, info)
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

function MSSQL:list_schemas(cb)
  local args = self:_args()
  vim.list_extend(args, { "-h", "-1", "-W", "-Q", "SELECT name FROM sys.schemas ORDER BY name" })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local schemas = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" and not name:match("^%-%-") then
        table.insert(schemas, name)
      end
    end
    cb(nil, schemas)
  end)
end

function MSSQL:list_nullability(cb)
  local args = self:_args()
  local sql = [[
    SET NOCOUNT ON;
    SELECT t.name, c.name, c.is_nullable
    FROM sys.columns c
    JOIN sys.tables t ON t.object_id = c.object_id
    ORDER BY t.name, c.column_id
  ]]
  vim.list_extend(args, { "-h", "-1", "-W", "-s", "\t", "-Q", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local map = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local parts = vim.split(line, "\t")
      local tbl, col, nul = parts[1], parts[2], parts[3]
      if tbl and col and nul then
        map[tbl] = map[tbl] or {}
        map[tbl][col] = (nul == "1")
      end
    end
    cb(nil, map)
  end)
end

return MSSQL
