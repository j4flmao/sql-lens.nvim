local M = {}

M._entries = {}
M._max = 200
M._max_days = 7
M._file = vim.fn.stdpath("data") .. "/sql-lens-history.json"

---Load history from disk
function M._load()
  local f = io.open(M._file, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    M._entries = data
  end
end

---Save history to disk
function M._save()
  local ok, json = pcall(vim.json.encode, M._entries)
  if not ok then return end
  local f = io.open(M._file, "w")
  if not f then return end
  f:write(json)
  f:close()
end

---Remove entries older than max_days
function M._prune()
  local cutoff = os.time() - (M._max_days * 86400)
  local pruned = {}
  for _, e in ipairs(M._entries) do
    if (e.epoch or 0) >= cutoff then
      table.insert(pruned, e)
    end
  end
  M._entries = pruned
end

function M.add(sql, conn)
  -- Load on first use
  if #M._entries == 0 then
    M._load()
  end

  local entry = {
    sql = sql,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    epoch = os.time(),
    connection = conn and conn.config.name or "unknown",
    database = conn and conn.config.dbname or "",
    db_type = conn and conn.type or "",
  }

  -- Avoid consecutive duplicates
  if M._entries[1] and M._entries[1].sql == sql
    and M._entries[1].connection == entry.connection
    and M._entries[1].database == entry.database then
    M._entries[1] = entry
    M._save()
    return
  end

  table.insert(M._entries, 1, entry)

  -- Trim to max
  while #M._entries > M._max do
    table.remove(M._entries)
  end

  M._prune()
  M._save()
end

function M.get_all()
  if #M._entries == 0 then
    M._load()
    M._prune()
  end
  return M._entries
end

---Get entries filtered by connection name and database
function M.get_by_connection(conn_name, dbname)
  local all = M.get_all()
  local result = {}
  for _, e in ipairs(all) do
    if e.connection == conn_name and (not dbname or dbname == "" or e.database == dbname) then
      table.insert(result, e)
    end
  end
  return result
end

function M.clear()
  M._entries = {}
  M._save()
end

---Build label + detail arrays from entries
---@param entries table[]
---@return string[] labels, string[] details
function M.build_display(entries)
  local labels = {}
  local details = {}
  for _, e in ipairs(entries) do
    local short = e.sql:gsub("%s+", " "):sub(1, 50)
    if #e.sql > 50 then short = short .. "…" end
    local db_info = e.connection
    if e.database and e.database ~= "" then
      db_info = db_info .. "/" .. e.database
    end
    local label = string.format("[%s] %s — %s", e.timestamp, db_info, short)
    table.insert(labels, label)
    table.insert(details, e.sql)
  end
  return labels, details
end

return M
