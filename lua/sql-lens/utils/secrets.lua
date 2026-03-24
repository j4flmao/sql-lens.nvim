local M = {}

function M.resolve_env_vars(str)
  if type(str) ~= "string" then return str end
  return str:gsub("%${([%w_]+)}", function(var)
    local v = vim.env[var]
    if v == nil or v == "" then
      v = os.getenv(var)
    end
    return v or "${" .. var .. "}"
  end)
end

function M.load_dotenv(path)
  path = path or M.find_dotenv()
  if not path then return {} end

  local vars = {}
  local f = io.open(path, "r")
  if not f then return vars end

  for line in f:lines() do
    local key, val = line:match("^([%w_]+)%s*=%s*(.+)$")
    if key and val then
      val = val:gsub("^[\"']", ""):gsub("[\"']$", "")
      vars[key] = val
      vim.env[key] = vim.env[key] or val
    end
  end
  f:close()
  return vars
end

function M.find_dotenv()
  local cwd = vim.fn.getcwd()
  local dotenv = cwd .. "/.env"
  if vim.fn.filereadable(dotenv) == 1 then
    return dotenv
  end
  return nil
end

function M.resolve_connection(conn, opts)
  local resolved = vim.deepcopy(conn)
  if opts and opts.use_env == false then
    return resolved
  end
  for k, v in pairs(resolved) do
    if type(v) == "string" then
      resolved[k] = M.resolve_env_vars(v)
    end
  end
  return resolved
end

return M
