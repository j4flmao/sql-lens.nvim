local M = {}

local function has_exe(bin)
  return vim.fn.executable(bin) == 1
end

local function get_ok_fn()
  if vim.health and vim.health.ok then
    return vim.health.ok
  end
  return function(msg)
    vim.fn["health#report_ok"](msg)
  end
end

local function get_warn_fn()
  if vim.health and vim.health.warn then
    return vim.health.warn
  end
  return function(msg)
    vim.fn["health#report_warn"](msg)
  end
end

local function get_error_fn()
  if vim.health and vim.health.error then
    return vim.health.error
  end
  return function(msg)
    vim.fn["health#report_error"](msg)
  end
end

local function start_section(name)
  if vim.health and vim.health.start then
    vim.health.start(name)
  else
    vim.fn["health#report_start"](name)
  end
end

local function collect_bins(connections)
  local bins = {}
  for _, c in ipairs(connections or {}) do
    local t = c.type
    if t == "postgres" then
      bins[c.cmd or "psql"] = true
    elseif t == "mysql" then
      bins[c.cmd or "mysql"] = true
    elseif t == "sqlserver" then
      bins.sqlcmd = true
    elseif t == "sqlite" then
      bins.sqlite3 = true
    elseif t == "mongodb" then
      bins[c.cmd or "mongosh"] = true
    end
  end
  return bins
end

function M.check()
  local ok = get_ok_fn()
  local warn = get_warn_fn()
  local err = get_error_fn()

  start_section("sql-lens.nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    ok("Neovim >= 0.9")
  else
    err("Neovim >= 0.9 is required")
  end

  local cfg = {}
  local loaded, mod = pcall(require, "sql-lens")
  if loaded and mod and type(mod._config) == "table" then
    cfg = mod._config
  end

  start_section("Dependencies")

  local bins = collect_bins((cfg.connections or {}))
  if vim.tbl_count(bins) == 0 then
    warn("No configured connections; cannot check DB CLIs")
  else
    for bin in pairs(bins) do
      if has_exe(bin) then
        ok("Found executable: " .. bin)
      else
        warn("Missing executable: " .. bin)
      end
    end
  end

  if vim.treesitter then
    ok("Treesitter runtime available")
  else
    warn("Treesitter runtime not found (nvim-treesitter recommended)")
  end

  if cfg.secrets and cfg.secrets.use_dotenv then
    local dotenv = require("sql-lens.utils.secrets").find_dotenv()
    if dotenv then
      ok("Found .env: " .. dotenv)
    else
      warn("secrets.use_dotenv=true but no .env found in cwd")
    end
  end
end

return M
