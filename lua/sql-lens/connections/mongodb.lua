local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local MongoDB = setmetatable({}, { __index = Base })
MongoDB.__index = MongoDB

function MongoDB.new(config)
  local self = Base.new(config)
  self.type = "mongodb"
  return setmetatable(self, MongoDB)
end

function MongoDB:_bin()
  return self.config.cmd or "mongosh"
end

function MongoDB:_connstr()
  local c = self.config
  local userinfo = ""
  if c.user and c.user ~= "" then
    userinfo = string.format("%s:%s@", c.user, c.password or "")
  end
  local uri = string.format("mongodb://%s%s:%s",
    userinfo,
    c.host or "127.0.0.1",
    c.port or 27017
  )
  if c.dbname then -- optional: omit to pick database later via :SqlLensDB
    uri = uri .. "/" .. c.dbname
  end
  if c.authSource then
    local sep = uri:find("?") and "&" or "?"
    uri = uri .. sep .. "authSource=" .. c.authSource
  end
  return uri
end

function MongoDB:_args()
  return { self:_bin(), self:_connstr(), "--quiet" }
end

function MongoDB:execute(js, cb)
  local args = self:_args()
  vim.list_extend(args, { "--eval", js })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "mongosh error", nil) end
    cb(nil, stdout)
  end)
end

function MongoDB:ping(cb)
  local args = self:_args()
  vim.list_extend(args, { "--eval", "db.runCommand({ping:1}).ok" })
  async.job(args, function(code) cb(code == 0) end)
end

function MongoDB:wrap_explain(js)
  return js
end

function MongoDB:explain(js, cb)
  local args = self:_args()
  -- Try to append .explain("executionStats") for find/aggregate queries
  local explain_js = js:gsub("%.find%(", ".find("):gsub("%)%s*;?%s*$", ".explain('executionStats'))")
  -- If the query already has .explain, use as-is
  if js:find("%.explain%(") then
    explain_js = js
  end
  vim.list_extend(args, { "--eval", "JSON.stringify(" .. explain_js .. ")" })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "mongosh error", nil) end
    local ok, data = pcall(vim.json.decode, stdout)
    if not ok then return cb("JSON parse error: " .. stdout, nil) end
    cb(nil, data)
  end)
end

function MongoDB:preview_query(collection)
  return "db." .. collection .. ".find().limit(50)"
end

function MongoDB:list_tables(cb)
  local args = self:_args()
  vim.list_extend(args, { "--eval", "db.getCollectionNames().forEach(c => print(c))" })
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

function MongoDB:list_columns(collection, cb)
  local args = self:_args()
  local js = string.format(
    "var doc = db.%s.findOne(); if(doc){Object.keys(doc).forEach(k => print(k + ' ' + typeof doc[k]))}",
    collection
  )
  vim.list_extend(args, { "--eval", js })
  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr or "error", {}) end
    local cols = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local name = line:match("^%s*(.-)%s*$")
      if name ~= "" then table.insert(cols, name) end
    end
    cb(nil, cols)
  end)
end

function MongoDB:list_databases(cb)
  local args = self:_args()
  vim.list_extend(args, {
    "--eval",
    "db.adminCommand('listDatabases').databases.forEach(d => print(d.name))",
  })
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

return MongoDB
