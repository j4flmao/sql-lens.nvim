local M = {}

local KEYWORDS = {
  "SELECT", "FROM", "WHERE", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN",
  "OUTER JOIN", "FULL JOIN", "CROSS JOIN", "ON", "AND", "OR", "NOT", "IN",
  "EXISTS", "BETWEEN", "LIKE", "IS", "NULL", "AS", "SET", "INTO", "VALUES",
  "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "ORDER BY",
  "GROUP BY", "HAVING", "UNION", "UNION ALL", "DISTINCT", "TOP", "LIMIT",
  "OFFSET", "GO", "BEGIN", "END", "DECLARE", "EXEC", "CASE", "WHEN", "THEN",
  "ELSE", "WITH", "TABLE", "INDEX", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
  "CONSTRAINT", "DEFAULT", "CHECK", "UNIQUE", "CASCADE", "ASC", "DESC",
  "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST", "CONVERT", "COALESCE",
  "ISNULL", "DATEADD", "DATEDIFF", "GETDATE", "NOW", "CURRENT_TIMESTAMP",
  "INT", "VARCHAR", "NVARCHAR", "TEXT", "BOOLEAN", "DATE", "DATETIME",
  "DATETIME2", "FLOAT", "DECIMAL", "BIGINT", "SMALLINT", "BIT",
  "NOT NULL", "IF", "RETURNS", "RETURN", "PROCEDURE", "FUNCTION", "TRIGGER",
  "VIEW", "DATABASE", "SCHEMA", "USE", "GRANT", "REVOKE",
}

-- Sort by length descending so multi-word keywords match first
table.sort(KEYWORDS, function(a, b) return #a > #b end)

-- Keywords that start a new line (major clauses)
local NEWLINE_BEFORE = {
  SELECT = true, FROM = true, WHERE = true,
  ["INNER JOIN"] = true, ["LEFT JOIN"] = true, ["RIGHT JOIN"] = true,
  ["OUTER JOIN"] = true, ["FULL JOIN"] = true, ["CROSS JOIN"] = true,
  JOIN = true, ["ORDER BY"] = true, ["GROUP BY"] = true,
  HAVING = true, UNION = true, ["UNION ALL"] = true,
  SET = true, VALUES = true, INTO = true,
  ON = true, AND = true, OR = true,
}

-- Keywords that increase indent
local INDENT_AFTER = {
  SELECT = true, SET = true,
}

---Extract string literals and replace with placeholders to protect them
local function protect_strings(sql)
  local protected = {}
  local idx = 0
  -- Replace quoted strings with placeholders
  local result = sql:gsub("('.-')", function(s)
    idx = idx + 1
    local key = "\0STR" .. idx .. "\0"
    protected[key] = s
    return key
  end)
  -- Replace double-quoted identifiers
  result = result:gsub('(".-")', function(s)
    idx = idx + 1
    local key = "\0STR" .. idx .. "\0"
    protected[key] = s
    return key
  end)
  -- Replace [bracket] identifiers
  result = result:gsub('(%[.-%])', function(s)
    idx = idx + 1
    local key = "\0STR" .. idx .. "\0"
    protected[key] = s
    return key
  end)
  return result, protected
end

---Restore protected strings
local function restore_strings(sql, protected)
  for key, val in pairs(protected) do
    sql = sql:gsub(key, val)
  end
  return sql
end

---Uppercase keywords in SQL
local function uppercase_keywords(sql)
  for _, kw in ipairs(KEYWORDS) do
    -- Build pattern: word boundary + case-insensitive keyword
    local pattern = "%f[%w]" .. kw:lower():gsub(" ", "%%s+") .. "%f[^%w]"
    sql = sql:gsub(pattern, kw)
    -- Also try original case
    pattern = "%f[%w]" .. kw:gsub(" ", "%%s+") .. "%f[^%w]"
    sql = sql:gsub(pattern, kw)
  end
  return sql
end

function M.format(sql)
  -- Separate comments
  local comments = {}
  local cleaned = sql:gsub("%-%-[^\n]*", function(c)
    table.insert(comments, c)
    return "\0COM" .. #comments .. "\0"
  end)

  local protected
  cleaned, protected = protect_strings(cleaned)

  -- Normalize whitespace
  cleaned = cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  -- Uppercase keywords
  cleaned = uppercase_keywords(cleaned)

  -- Add newlines before major clauses
  for kw in pairs(NEWLINE_BEFORE) do
    local pattern = "%s+" .. kw:gsub(" ", "%%s+") .. "%s"
    cleaned = cleaned:gsub(pattern, "\n" .. kw .. " ")
  end

  -- Indent lines
  local lines = {}
  local indent = 0
  for line in cleaned:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    local first_word = trimmed:match("^(%S+)")

    -- Decrease indent for certain keywords
    if first_word == "FROM" or first_word == "WHERE" or first_word == "SET"
       or first_word == "VALUES" or trimmed:match("^ORDER BY")
       or trimmed:match("^GROUP BY") or first_word == "HAVING"
       or first_word == "UNION" then
      indent = 0
    end

    local prefix = string.rep("  ", indent)
    table.insert(lines, prefix .. trimmed)

    -- Increase indent after SELECT, etc.
    if INDENT_AFTER[first_word] then
      indent = indent + 1
    end
  end

  local result = table.concat(lines, "\n")

  -- Restore protected content
  result = restore_strings(result, protected)
  for i, c in ipairs(comments) do
    result = result:gsub("\0COM" .. i .. "\0", c)
  end

  return result
end

---Format SQL in the current buffer (whole buffer or visual selection)
function M.format_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, end_line

  -- Check for visual selection
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    start_line = vim.fn.line("'<") - 1
    end_line = vim.fn.line("'>")
  else
    start_line = 0
    end_line = vim.api.nvim_buf_line_count(bufnr)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
  local sql = table.concat(lines, "\n")
  local formatted = M.format(sql)
  local new_lines = vim.split(formatted, "\n")

  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, new_lines)
  vim.notify("SqlLens: Formatted " .. #new_lines .. " lines", vim.log.levels.INFO)
end

return M
