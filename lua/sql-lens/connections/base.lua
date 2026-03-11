local Base = {}
Base.__index = Base

function Base.new(config)
  return setmetatable({ config = config, connected = false }, Base)
end

function Base:connect()    error("Not implemented") end
function Base:disconnect() error("Not implemented") end
function Base:ping()       error("Not implemented") end

function Base:explain(sql, cb)
  error("Not implemented")
end

function Base:wrap_explain(sql)
  error("Not implemented: must return EXPLAIN query string")
end

---@param sql string
---@param cb function(err, stdout)
function Base:execute(sql, cb)
  error("Not implemented")
end

---Lint SQL server-side (validate without executing)
---@param sql string
---@param cb fun(err?: string)
function Base:lint(sql, cb)
  -- Default: no server-side lint
  cb(nil)
end

return Base
