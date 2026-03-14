local M = {}

-- All SQL keywords to uppercase (sorted longest first)
local KEYWORDS = {}
local kw_list = {
  "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "OUTER JOIN", "FULL JOIN",
  "CROSS JOIN", "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN",
  "ORDER BY", "GROUP BY", "UNION ALL", "INSERT INTO", "NOT NULL", "IS NOT",
  "NOT IN", "NOT EXISTS", "NOT BETWEEN", "NOT LIKE",
  "CURRENT_TIMESTAMP", "INFORMATION_SCHEMA",
  "SELECT", "FROM", "WHERE", "JOIN", "ON", "AND", "OR", "NOT", "IN",
  "EXISTS", "BETWEEN", "LIKE", "IS", "NULL", "AS", "SET", "INTO", "VALUES",
  "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
  "HAVING", "UNION", "DISTINCT", "TOP", "LIMIT", "OFFSET",
  "GO", "BEGIN", "END", "DECLARE", "EXEC", "EXECUTE",
  "CASE", "WHEN", "THEN", "ELSE",
  "WITH", "TABLE", "INDEX", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
  "CONSTRAINT", "DEFAULT", "CHECK", "UNIQUE", "CASCADE", "ASC", "DESC",
  "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST", "CONVERT", "COALESCE",
  "ISNULL", "NULLIF", "DATEADD", "DATEDIFF", "GETDATE", "NOW",
  "INT", "VARCHAR", "NVARCHAR", "TEXT", "BOOLEAN", "DATE", "DATETIME",
  "DATETIME2", "FLOAT", "DECIMAL", "BIGINT", "SMALLINT", "BIT", "CHAR",
  "IF", "RETURNS", "RETURN", "PROCEDURE", "FUNCTION", "TRIGGER",
  "VIEW", "DATABASE", "SCHEMA", "USE", "GRANT", "REVOKE",
  "OVER", "PARTITION BY", "ROW_NUMBER", "RANK", "DENSE_RANK",
  "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
  "IDENTITY", "AUTOINCREMENT", "AUTO_INCREMENT", "SERIAL",
  "TRUNCATE", "MERGE", "USING", "MATCHED",
  "EXCEPT", "INTERSECT", "ALL", "ANY", "SOME",
  "ROLLBACK", "COMMIT", "TRANSACTION", "SAVEPOINT",
  "CURSOR", "FETCH", "NEXT", "PRIOR", "OPEN", "CLOSE", "DEALLOCATE",
  "WHILE", "BREAK", "CONTINUE", "TRY", "CATCH", "THROW",
  "NONCLUSTERED", "CLUSTERED", "INCLUDE",
  "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER",
}
for _, kw in ipairs(kw_list) do
  KEYWORDS[#KEYWORDS + 1] = kw
end
table.sort(KEYWORDS, function(a, b) return #a > #b end)

-- Major clause keywords that get their own line (indent level 0 relative to statement)
local CLAUSE_KEYWORDS = {
  SELECT = true, FROM = true, WHERE = true,
  ["INNER JOIN"] = true, ["LEFT JOIN"] = true, ["RIGHT JOIN"] = true,
  ["OUTER JOIN"] = true, ["FULL JOIN"] = true, ["CROSS JOIN"] = true,
  ["LEFT OUTER JOIN"] = true, ["RIGHT OUTER JOIN"] = true, ["FULL OUTER JOIN"] = true,
  JOIN = true, ["ORDER BY"] = true, ["GROUP BY"] = true,
  HAVING = true, UNION = true, ["UNION ALL"] = true,
  SET = true, VALUES = true, ["INSERT INTO"] = true,
  USING = true, MERGE = true,
  EXCEPT = true, INTERSECT = true,
}

-- Sub-clause keywords that indent one level
local SUB_CLAUSE = {
  AND = true, OR = true, ON = true,
  WHEN = true, ELSE = true,
}

---Protect strings, quoted identifiers, and bracketed identifiers
local function protect(sql)
  local map = {}
  local idx = 0
  local function sub(s)
    idx = idx + 1
    local key = "\1P" .. idx .. "\1"
    map[key] = s
    return key
  end
  -- Order matters: block comments, line comments, strings, double-quoted, bracketed
  sql = sql:gsub("/%*.-%*/", sub)       -- block comments
  sql = sql:gsub("%-%-[^\n]*", sub)     -- line comments
  sql = sql:gsub("(N?'.-')", sub)       -- strings (including N'...')
  sql = sql:gsub('(".-")', sub)         -- double-quoted identifiers
  sql = sql:gsub('(%[.-%])', sub)       -- bracketed identifiers
  return sql, map
end

local function unprotect(sql, map)
  -- May need multiple passes for nested replacements
  for _ = 1, 3 do
    for key, val in pairs(map) do
      sql = sql:gsub(vim.pesc(key), val:gsub("%%", "%%%%"))
    end
  end
  return sql
end

---Uppercase keywords (only outside protected regions)
local function upper_keywords(sql)
  for _, kw in ipairs(KEYWORDS) do
    local parts = {}
    for _, word in ipairs(vim.split(kw, " ")) do
      table.insert(parts, "%f[%w_]" .. word:lower() .. "%f[^%w_]")
    end
    local pat = table.concat(parts, "%s+")
    sql = sql:gsub(pat, kw)
  end
  return sql
end

---Count unprotected opening parens minus closing parens
local function paren_depth_change(line)
  local d = 0
  for c in line:gmatch(".") do
    if c == "(" then d = d + 1
    elseif c == ")" then d = d - 1 end
  end
  return d
end

---Check if a token is a function name (followed by `(`)
local function is_function_call(sql, pos)
  local after = sql:sub(pos):match("^%w+%s*%(")
  return after ~= nil
end

function M.format(sql)
  local protected_map
  sql, protected_map = protect(sql)

  -- Normalize whitespace (but keep newlines for comment detection)
  sql = sql:gsub("\r\n", "\n"):gsub("\r", "\n")
  sql = sql:gsub("[ \t]+", " ")
  sql = sql:gsub("\n[ \t]*\n", "\n")

  -- Uppercase keywords
  sql = upper_keywords(sql)

  -- Collapse to single line for restructuring (but preserve protected newlines in comments)
  sql = sql:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  -- Insert newlines before major clauses
  for kw in pairs(CLAUSE_KEYWORDS) do
    local escaped = kw:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    sql = sql:gsub("%s+" .. escaped .. "%s", "\n" .. kw .. " ")
    sql = sql:gsub("^" .. escaped .. "%s", kw .. " ")
  end

  -- Insert newlines before sub-clauses
  for kw in pairs(SUB_CLAUSE) do
    local escaped = kw:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    sql = sql:gsub("%s+" .. escaped .. "%s", "\n  " .. kw .. " ")
  end

  -- CASE/END handling
  sql = sql:gsub("%s+CASE%s", "\n    CASE ")
  sql = sql:gsub("%s+END%f[^%w_]", "\n    END")

  -- Commas: put each column on its own line after SELECT (before FROM)
  -- Find SELECT...FROM blocks and split by comma
  sql = sql:gsub("(SELECT%s+)(.-)\n(FROM)", function(sel, cols, fr)
    -- Don't split if it's inside a function or subquery
    local depth = 0
    local parts = {}
    local current = ""
    for i = 1, #cols do
      local ch = cols:sub(i, i)
      if ch == "(" then depth = depth + 1
      elseif ch == ")" then depth = depth - 1
      elseif ch == "," and depth == 0 then
        table.insert(parts, current:match("^%s*(.-)%s*$"))
        current = ""
        goto continue
      end
      current = current .. ch
      ::continue::
    end
    if current:match("%S") then
      table.insert(parts, current:match("^%s*(.-)%s*$"))
    end
    if #parts > 1 then
      return sel .. "\n  " .. table.concat(parts, ",\n  ") .. "\n" .. fr
    end
    return sel .. cols .. "\n" .. fr
  end)

  -- GO on its own line
  sql = sql:gsub("%s+GO%f[^%w_]", "\nGO")

  -- Indent based on parenthesis depth
  local raw_lines = vim.split(sql, "\n")
  local result = {}
  local depth = 0

  for _, line in ipairs(raw_lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "" then goto next_line end

    -- Calculate leading depth change (closing parens at start)
    local leading_close = trimmed:match("^%)*")
    if leading_close and #leading_close > 0 then
      depth = math.max(0, depth - #leading_close)
    end

    local indent = string.rep("  ", depth)
    -- Sub-clauses get extra indent
    local first = trimmed:match("^(%S+)")
    if SUB_CLAUSE[first] then
      indent = indent .. "  "
    end

    table.insert(result, indent .. trimmed)

    depth = math.max(0, depth + paren_depth_change(trimmed))

    ::next_line::
  end

  sql = table.concat(result, "\n")

  -- Restore protected content
  sql = unprotect(sql, protected_map)

  -- Clean up: remove excessive blank lines
  sql = sql:gsub("\n\n\n+", "\n\n")
  -- Ensure semicolons are at end of line
  sql = sql:gsub(";%s*\n", ";\n")

  return sql
end

---Format SQL in the current buffer (whole buffer or visual selection)
function M.format_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, end_line

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
  vim.notify(string.format("SqlLens: Formatted %d → %d lines", #lines, #new_lines), vim.log.levels.INFO)
end

return M
