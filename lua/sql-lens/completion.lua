local M = {}

local source = {}
source.__index = source

source._cache = {}  -- conn_name → { tables = {}, columns = { tbl → {} } }

function source.new()
  return setmetatable({}, source)
end

function source:is_available()
  local conn_mgr = require("sql-lens.connections")
  local bufnr = vim.api.nvim_get_current_buf()
  return conn_mgr.get_active(bufnr) ~= nil
end

function source:get_debug_name()
  return "sql-lens"
end

function source:get_trigger_characters()
  return { ".", " " }
end

local function get_cache(conn)
  local key = (conn.config.name or "") .. ":" .. (conn.config.dbname or "")
  if not source._cache[key] then
    source._cache[key] = { tables = nil, columns = {} }
  end
  return source._cache[key], key
end

function source:complete(params, callback)
  local conn_mgr = require("sql-lens.connections")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)
  if not conn then return callback({ items = {}, isIncomplete = false }) end

  local cache = get_cache(conn)

  -- Get the current line text before cursor to detect context
  local line = params.context.cursor_before_line or ""
  local word = line:match("(%w+)$") or ""

  -- Check if we're after FROM/JOIN/INTO/UPDATE/TABLE → suggest tables
  -- Or after a table alias dot → suggest columns
  local items = {}

  local function build_items()
    -- Table completions
    if cache.tables then
      for _, tbl in ipairs(cache.tables) do
        table.insert(items, {
          label = tbl,
          kind = 22, -- Struct
          detail = "table",
          sortText = "0_" .. tbl,
        })
      end
    end
    -- Column completions from all cached tables
    for tbl, cols in pairs(cache.columns) do
      for _, col_info in ipairs(cols) do
        local col_name = col_info:match("^(%S+)")
        local col_type = col_info:match("%s+(.+)$") or ""
        if col_name then
          table.insert(items, {
            label = col_name,
            kind = 5, -- Field
            detail = tbl .. " (" .. col_type .. ")",
            sortText = "1_" .. col_name,
          })
        end
      end
    end
    callback({ items = items, isIncomplete = false })
  end

  -- Fetch tables if not cached
  if not cache.tables then
    conn:list_tables(function(err, tables)
      if err or not tables then
        cache.tables = {}
      else
        cache.tables = tables
        -- Fetch columns for each table (up to 20 tables)
        local count = math.min(#tables, 20)
        local done = 0
        if count == 0 then
          build_items()
          return
        end
        for i = 1, count do
          conn:list_columns(tables[i], function(cerr, cols)
            cache.columns[tables[i]] = cols or {}
            done = done + 1
            if done == count then
              build_items()
            end
          end)
        end
      end
    end)
  else
    build_items()
  end
end

function M.setup()
  local ok, cmp = pcall(require, "cmp")
  if not ok then return end
  cmp.register_source("sql_lens", source.new())
end

--- Invalidate cache (call when switching database)
function M.invalidate()
  source._cache = {}
end

return M
