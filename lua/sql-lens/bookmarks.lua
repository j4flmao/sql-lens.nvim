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
  -- Update existing or add new
  local found = false
  for i, bm in ipairs(bookmarks) do
    if bm.name == cfg.name then
      bookmarks[i] = cfg
      found = true
      break
    end
  end
  if not found then
    table.insert(bookmarks, cfg)
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

  -- Save current connection config (without sensitive resolve)
  local cfg = vim.deepcopy(conn.config)
  M.save(cfg)
end

return M
