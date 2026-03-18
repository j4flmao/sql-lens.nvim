local Base   = require("sql-lens.connections.base")
local async  = require("sql-lens.utils.async")

local PG = setmetatable({}, { __index = Base })
PG.__index = PG

function PG.new(config)
  local self = Base.new(config)
  self.type = "postgres"
  return setmetatable(self, PG)
end

function PG:_connstr()
  local c = self.config
  local uri = string.format(
    "postgresql://%s:%s@%s:%s/%s",
    c.user, c.password, c.host or "localhost",
    c.port or 5432, c.dbname or "postgres" -- dbname optional: defaults to "postgres", pick later via :SqlLensDB
  )
  if c.sslmode then
    uri = uri .. "?sslmode=" .. c.sslmode
  end
  return uri
end

function PG:wrap_explain(sql)
  local upper = sql:upper():match("^%s*(%w+)")
  if not vim.tbl_contains({"SELECT","UPDATE","DELETE","INSERT","WITH"}, upper) then
    return nil, "Cannot EXPLAIN " .. (upper or "unknown") .. " statement"
  end
  return string.format(
    "EXPLAIN (ANALYZE true, COSTS true, FORMAT JSON, BUFFERS true) %s",
    sql
  )
end

function PG:explain(sql, cb)
  local explain_sql, err = self:wrap_explain(sql)
  if err then return cb(err, nil) end

  local cmd = {
    "psql", self:_connstr(),
    "--no-psqlrc", "-t", "-A",
    "-c", explain_sql
  }

  async.job(cmd, function(exit_code, stdout, stderr)
    if exit_code ~= 0 then
      return cb(stderr, nil)
    end
    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok then
      return cb("Failed to parse JSON: " .. stdout, nil)
    end
    cb(nil, decoded)
  end)
end

function PG:execute(sql, cb)
  local cmd = {
    "psql", self:_connstr(),
    "--no-psqlrc", "--pset=pager=off",
    "-A", "-F", "\t",
    "-c", sql
  }
  async.job(cmd, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "psql error", nil) end
    cb(nil, stdout)
  end)
end

function PG:ping(cb)
  async.job(
    { "psql", self:_connstr(), "-c", "SELECT 1" },
    function(code) cb(code == 0) end
  )
end

function PG:list_tables(cb)
  local cmd = {
    "psql", self:_connstr(),
    "--no-psqlrc", "-t", "-A",
    "-c", "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename",
  }
  async.job(cmd, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local tables = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" then table.insert(tables, name) end
    end
    cb(nil, tables)
  end)
end

function PG:list_columns(tbl, cb)
  local sql = string.format(
    "SELECT column_name || ' ' || data_type FROM information_schema.columns WHERE table_name = '%s' ORDER BY ordinal_position",
    tbl
  )
  local cmd = { "psql", self:_connstr(), "--no-psqlrc", "-t", "-A", "-c", sql }
  async.job(cmd, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local cols = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" then table.insert(cols, name) end
    end
    cb(nil, cols)
  end)
end

function PG:list_table_sizes(cb)
  local sql = "SELECT tablename, n_live_tup, pg_total_relation_size(schemaname||'.'||tablename) FROM pg_stat_user_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC"
  local cmd = { "psql", self:_connstr(), "--no-psqlrc", "-t", "-A", "-F", "\t", "-c", sql }
  async.job(cmd, function(code, stdout, stderr)
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

function PG:list_foreign_keys(cb)
  local sql = [[
    SELECT
      tc.table_name AS from_table,
      kcu.column_name AS from_column,
      ccu.table_name AS to_table,
      ccu.column_name AS to_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
    ORDER BY tc.table_name
  ]]
  local cmd = { "psql", self:_connstr(), "--no-psqlrc", "-t", "-A", "-F", "\t", "-c", sql }
  async.job(cmd, function(code, stdout, stderr)
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

function PG:list_databases(cb)
  local cmd = {
    "psql", self:_connstr(),
    "--no-psqlrc", "-t", "-A",
    "-c", "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
  }
  async.job(cmd, function(code, stdout, stderr)
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

return PG
