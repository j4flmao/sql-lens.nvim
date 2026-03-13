local M = {}

local icon = " "  -- database icon

function M.get()
  local ok, conn_mgr = pcall(require, "sql-lens.connections")
  if not ok then return "" end

  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)
  if not conn then return "" end

  local name = conn.config.name or conn.type
  local db = conn.config.dbname
  if db and db ~= "" then
    return icon .. name .. "/" .. db
  else
    return icon .. name .. " (no db)"
  end
end

-- Lualine component
M.lualine = {
  function() return M.get() end,
  cond = function()
    local ft = vim.bo.filetype
    return ft == "sql" or ft == "plpgsql" or ft == "mysql" or ft == "mongodb"
  end,
  color = { fg = "#60a5fa" },
}

return M
