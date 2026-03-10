local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local MySQL = setmetatable({}, { __index = Base })
MySQL.__index = MySQL

function MySQL.new(config)
  local self = Base.new(config)
  self.type = "mysql"
  return setmetatable(self, MySQL)
end

function MySQL:_args()
  local c = self.config
  return {
    "mysql",
    "-h", c.host or "127.0.0.1",
    "-P", tostring(c.port or 3306),
    "-u", c.user,
    string.format("-p%s", c.password),
    c.dbname,
    "--silent", "--raw",
  }
end

function MySQL:wrap_explain(sql)
  return "EXPLAIN FORMAT=JSON " .. sql
end

function MySQL:explain(sql, cb)
  local args = self:_args()
  vim.list_extend(args, { "-e", self:wrap_explain(sql) })

  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr, nil) end
    local ok, data = pcall(vim.json.decode, stdout)
    if not ok then return cb("JSON parse error", nil) end
    cb(nil, data)
  end)
end

return MySQL
