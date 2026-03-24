local M = {}

M._file = vim.fn.stdpath("data") .. "/sql-lens-bookmarks.json"

function M._read()
  local f = io.open(M._file, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then return data end
  return {}
end

function M._write(bookmarks)
  local ok, json = pcall(vim.json.encode, bookmarks)
  if not ok then return end
  local f = io.open(M._file, "w")
  if not f then return end
  f:write(json)
  f:close()
end

function M.save(cfg)
  local bookmarks = M._read()
  local safe = vim.deepcopy(cfg)
  safe.password = nil
  safe.connection_string = nil
  -- Update existing or add new
  local found = false
  for i, bm in ipairs(bookmarks) do
    if bm.name == cfg.name then
      bookmarks[i] = safe
      found = true
      break
    end
  end
  if not found then
    table.insert(bookmarks, safe)
  end
  M._write(bookmarks)
  vim.notify("SqlLens: Bookmark saved '" .. cfg.name .. "'", vim.log.levels.INFO)
end

function M.load_all()
  return M._read()
end

function M.remove(name)
  local bookmarks = M._read()
  local new = {}
  for _, bm in ipairs(bookmarks) do
    if bm.name ~= name then
      table.insert(new, bm)
    end
  end
  M._write(new)
  vim.notify("SqlLens: Bookmark removed '" .. name .. "'", vim.log.levels.INFO)
end

function M.pick_and_save()
  local conn_mgr = require("sql-lens.connections")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No active connection to save", vim.log.levels.WARN)
    return
  end

  local cfg = vim.deepcopy(conn.config)
  M.save(cfg)

  -- Also save file → connection mapping
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath and filepath ~= "" then
    M.bind_file(filepath, cfg.name, cfg.dbname)
  end
end

-- File → connection mapping
M._bindings_file = vim.fn.stdpath("data") .. "/sql-lens-file-bindings.json"

function M._read_bindings()
  local f = io.open(M._bindings_file, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then return data end
  return {}
end

function M._write_bindings(bindings)
  local ok, json = pcall(vim.json.encode, bindings)
  if not ok then return end
  local f = io.open(M._bindings_file, "w")
  if not f then return end
  f:write(json)
  f:close()
end

function M.bind_file(filepath, conn_name, dbname)
  local bindings = M._read_bindings()
  bindings[filepath] = { connection = conn_name, database = dbname or "" }
  M._write_bindings(bindings)
end

function M.get_binding(filepath)
  local bindings = M._read_bindings()
  return bindings[filepath]
end

return M
