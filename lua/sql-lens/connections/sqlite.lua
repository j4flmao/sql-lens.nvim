local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local SQLite = setmetatable({}, { __index = Base })
SQLite.__index = SQLite

function SQLite.new(config)
  local self = Base.new(config)
  self.type = "sqlite"
  return setmetatable(self, SQLite)
end

function SQLite:wrap_explain(sql)
  return "EXPLAIN QUERY PLAN " .. sql
end

function SQLite:explain(sql, cb)
  async.job(
    { "sqlite3", self.config.path, self:wrap_explain(sql) },
    function(code, stdout, stderr)
      if code ~= 0 then return cb(stderr, nil) end
      local rows = {}
      for line in stdout:gmatch("[^\n]+") do
        local id, parent, notused, detail = line:match("(%d+)|(%d+)|(%d+)|(.*)")
        if detail then
          table.insert(rows, { id=tonumber(id), parent=tonumber(parent), detail=detail })
        end
      end
      cb(nil, { type = "sqlite_qp", rows = rows })
    end
  )
end

return SQLite
