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
  return string.format(
    "postgresql://%s:%s@%s:%s/%s",
    c.user, c.password, c.host or "localhost",
    c.port or 5432, c.dbname
  )
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

function PG:ping(cb)
  async.job(
    { "psql", self:_connstr(), "-c", "SELECT 1" },
    function(code) cb(code == 0) end
  )
end

return PG
