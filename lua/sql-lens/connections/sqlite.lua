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

function SQLite:list_tables(cb)
  async.job(
    { "sqlite3", self.config.path, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" },
    function(code, stdout, stderr)
      if code ~= 0 then return cb(stderr or "error", {}) end
      local tables = {}
      for line in stdout:gmatch("[^\r\n]+") do
        local name = line:match("^%s*(.-)%s*$")
        if name ~= "" then table.insert(tables, name) end
      end
      cb(nil, tables)
    end
  )
end

function SQLite:list_columns(tbl, cb)
  async.job(
    { "sqlite3", self.config.path, "PRAGMA table_info(" .. tbl .. ");" },
    function(code, stdout, stderr)
      if code ~= 0 then return cb(stderr or "error", {}) end
      local cols = {}
      for line in stdout:gmatch("[^\r\n]+") do
        local parts = vim.split(line, "|")
        if parts[2] and parts[2] ~= "" then
          table.insert(cols, parts[2] .. " " .. (parts[3] or ""))
        end
      end
      cb(nil, cols)
    end
  )
end

function SQLite:list_foreign_keys(cb)
  -- First get all tables, then PRAGMA foreign_key_list for each
  self:list_tables(function(err, tables)
    if err then return cb(err, {}) end
    local fks = {}
    local done = 0
    if #tables == 0 then return cb(nil, {}) end
    for _, tbl in ipairs(tables) do
      async.job(
        { "sqlite3", self.config.path, "PRAGMA foreign_key_list(" .. tbl .. ");" },
        function(code, stdout)
          if code == 0 then
            for line in stdout:gmatch("[^\r\n]+") do
              local parts = vim.split(line, "|")
              if #parts >= 5 then
                table.insert(fks, {
                  from_table = tbl, from_column = parts[4],
                  to_table = parts[3], to_column = parts[5],
                })
              end
            end
          end
          done = done + 1
          if done == #tables then cb(nil, fks) end
        end
      )
    end
  end)
end

return SQLite
