local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local MySQL = setmetatable({}, { __index = Base })
MySQL.__index = MySQL

function MySQL.new(config)
  local self = Base.new(config)
  self.type = "mysql"
  return setmetatable(self, MySQL)
end

function MySQL:_bin()
  return self.config.cmd or "mysql"
end

function MySQL:_args()
  local c = self.config
  local args = {
    self:_bin(),
    "-h", c.host or "127.0.0.1",
    "-P", tostring(c.port or 3306),
    "-u", c.user,
  }
  if c.password and c.password ~= "" then
    table.insert(args, string.format("-p%s", c.password))
  end
  if c.dbname then -- optional: omit to pick database later via :SqlLensDB
    table.insert(args, c.dbname)
  end
  return args
end

function MySQL:wrap_explain(sql)
  return "EXPLAIN FORMAT=JSON " .. sql
end

function MySQL:explain(sql, cb)
  local args = self:_args()
  vim.list_extend(args, { "--silent", "--raw", "-e", self:wrap_explain(sql) })

  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr, nil) end
    local ok, data = pcall(vim.json.decode, stdout)
    if not ok then return cb("JSON parse error", nil) end
    cb(nil, data)
  end)
end

function MySQL:execute(sql, cb)
  local args = self:_args()
  vim.list_extend(args, { "-t", "-e", sql })

  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "mysql error", nil) end
    cb(nil, stdout)
  end)
end

function MySQL:ping(cb)
  local args = self:_args()
  vim.list_extend(args, { "-e", "SELECT 1" })
  async.job(args, function(code) cb(code == 0) end)
end

function MySQL:list_tables(cb)
  local args = self:_args()
  vim.list_extend(args, { "--silent", "--raw", "-e", "SHOW TABLES" })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local tables = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" then table.insert(tables, name) end
    end
    cb(nil, tables)
  end)
end

function MySQL:list_columns(tbl, cb)
  local args = self:_args()
  vim.list_extend(args, { "--silent", "--raw", "-e", "SHOW COLUMNS FROM " .. tbl })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local cols = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local parts = vim.split(line, "\t")
      if parts[1] and parts[1] ~= "" then
        table.insert(cols, parts[1] .. " " .. (parts[2] or ""))
      end
    end
    cb(nil, cols)
  end)
end

function MySQL:list_table_sizes(cb)
  local args = self:_args()
  vim.list_extend(args, { "--silent", "--raw", "-e",
    "SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH + INDEX_LENGTH FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY DATA_LENGTH + INDEX_LENGTH DESC" })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local sizes = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local parts = vim.split(line, "\t")
      if #parts >= 3 and parts[1] ~= "" then
        table.insert(sizes, {
          name = parts[1],
          row_count = tonumber(parts[2]) or 0,
          bytes = tonumber(parts[3]) or 0,
        })
      end
    end
    cb(nil, sizes)
  end)
end

function MySQL:list_foreign_keys(cb)
  local args = self:_args()
  local sql = "SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_NAME IS NOT NULL AND TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME"
  vim.list_extend(args, { "--silent", "--raw", "-e", sql })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local fks = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local parts = vim.split(line, "\t")
      if #parts >= 4 then
        table.insert(fks, {
          from_table = parts[1], from_column = parts[2],
          to_table = parts[3], to_column = parts[4],
        })
      end
    end
    cb(nil, fks)
  end)
end

function MySQL:list_databases(cb)
  local args = self:_args()
  vim.list_extend(args, { "--silent", "--raw", "-e", "SHOW DATABASES" })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local dbs = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" then
        table.insert(dbs, name)
      end
    end
    cb(nil, dbs)
  end)
end

return MySQL
