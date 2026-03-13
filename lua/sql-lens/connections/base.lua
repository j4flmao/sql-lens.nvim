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

---@param cb fun(err?: string, tables?: string[])
function Base:list_tables(cb)
  cb("Not implemented", {})
end

---@param tbl string
---@param cb fun(err?: string, columns?: string[])
function Base:list_columns(tbl, cb)
  cb("Not implemented", {})
end

---Return a preview query for the given table
---@param tbl string
---@return string
function Base:preview_query(tbl)
  return "SELECT * FROM " .. tbl .. " LIMIT 50;"
end

return Base
