local M = {}

-- ══════════════════════════════════════════════════════
-- FULL SQL Server keyword/function list for fuzzy match
-- ══════════════════════════════════════════════════════

local SQL_KEYWORDS = {
  -- DML
  "select", "from", "where", "group", "by", "order", "having",
  "insert", "into", "values", "update", "set", "delete", "merge",
  "truncate", "output",
  -- Joins
  "join", "inner", "left", "right", "full", "cross", "outer", "on",
  "apply", "pivot", "unpivot",
  -- Set operators
  "union", "all", "except", "intersect",
  -- DDL
  "create", "alter", "drop", "table", "index", "view",
  "procedure", "function", "trigger", "schema", "database",
  "column", "constraint", "primary", "key", "foreign", "references",
  "unique", "check", "default", "identity", "clustered", "nonclustered",
  -- Conditions
  "and", "or", "not", "in", "between", "like", "is", "null",
  "exists", "any", "some",
  -- CASE
  "case", "when", "then", "else", "end",
  -- Aliases & misc
  "as", "on", "asc", "desc", "top", "distinct", "with",
  "over", "partition", "rows", "range", "preceding", "following",
  "unbounded", "current", "row",
  -- Control flow
  "if", "begin", "while", "return", "break", "continue",
  "goto", "throw", "try", "catch",
  -- Transaction
  "commit", "rollback", "transaction", "savepoint",
  -- Variables
  "declare", "exec", "execute", "print",
  -- Types
  "int", "bigint", "smallint", "tinyint", "bit",
  "decimal", "numeric", "float", "real", "money", "smallmoney",
  "char", "varchar", "nchar", "nvarchar", "text", "ntext",
  "date", "time", "datetime", "datetime2", "smalldatetime",
  "datetimeoffset", "timestamp",
  "binary", "varbinary", "image", "xml", "uniqueidentifier",
  -- Other
  "go", "use", "grant", "revoke", "deny",
  "cursor", "open", "fetch", "close", "deallocate",
  "include", "nocount", "statistics",
  "showplan_all", "noexec", "quoted_identifier",
}

local SQL_FUNCTIONS = {
  -- Aggregate
  "count", "sum", "avg", "min", "max",
  "stdev", "stdevp", "var", "varp",
  "count_big", "checksum_agg", "grouping", "grouping_id",
  "string_agg", "approx_count_distinct",
  -- Window
  "row_number", "rank", "dense_rank", "ntile",
  "lag", "lead", "first_value", "last_value",
  "percent_rank", "cume_dist", "percentile_cont", "percentile_disc",
  -- String
  "len", "datalength", "upper", "lower", "ltrim", "rtrim", "trim",
  "left", "right", "substring", "charindex", "patindex",
  "replace", "stuff", "reverse", "replicate", "space",
  "concat", "concat_ws", "format", "quotename",
  "string_split", "string_escape", "translate", "unicode", "ascii",
  "char", "nchar",
  -- Date/Time
  "getdate", "getutcdate", "sysdatetime", "sysutcdatetime",
  "current_timestamp", "sysdatetimeoffset",
  "dateadd", "datediff", "datediff_big", "datename", "datepart",
  "year", "month", "day",
  "eomonth", "datefromparts", "datetime2fromparts",
  "datetimefromparts", "timefromparts",
  "datetimeoffsetfromparts", "smalldatetimefromparts",
  "switchoffset", "todatetimeoffset", "isdate",
  -- Conversion
  "cast", "convert", "try_cast", "try_convert", "parse", "try_parse",
  -- Null handling
  "isnull", "nullif", "coalesce",
  -- Logic
  "iif", "choose",
  -- Math
  "abs", "ceiling", "floor", "round", "sign", "power",
  "sqrt", "square", "log", "log10", "exp",
  "sin", "cos", "tan", "asin", "acos", "atan", "atn2",
  "pi", "rand", "degrees", "radians",
  -- System
  "newid", "newsequentialid",
  "object_id", "object_name", "db_id", "db_name",
  "scope_identity", "ident_current",
  "error_message", "error_number", "error_severity", "error_state",
  "host_name", "app_name", "suser_name", "user_name",
  "schema_name", "type_name",
  -- JSON
  "json_value", "json_query", "json_modify",
  "isjson", "json_path_exists",
  -- XML
  "xml_value", "xml_query", "xml_exist",
  -- Type check
  "isnumeric", "isdate",
}

-- Build lookup sets
local KEYWORD_SET = {}
for _, k in ipairs(SQL_KEYWORDS) do KEYWORD_SET[k] = true end
local FUNCTION_SET = {}
for _, f in ipairs(SQL_FUNCTIONS) do FUNCTION_SET[f] = true end
-- Combined set for "is this a known SQL word?"
local ALL_KNOWN = {}
for _, k in ipairs(SQL_KEYWORDS) do ALL_KNOWN[k] = true end
for _, f in ipairs(SQL_FUNCTIONS) do ALL_KNOWN[f] = true end

-- ══════════════════════════════════════════════════════
-- Levenshtein distance for fuzzy matching
-- ══════════════════════════════════════════════════════

local function levenshtein(a, b)
  local la, lb = #a, #b
  if la == 0 then return lb end
  if lb == 0 then return la end
  local prev = {}
  local curr = {}
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    curr[0] = i
    local ca = a:sub(i, i)
    for j = 1, lb do
      local cb = b:sub(j, j)
      local cost = (ca == cb) and 0 or 1
      curr[j] = math.min(curr[j-1]+1, prev[j]+1, prev[j-1]+cost)
    end
    prev, curr = curr, prev
  end
  return prev[lb]
end

---Find the best matching SQL keyword/function for a token
---@param token string lowercase token
---@return string|nil suggestion, number|nil distance
local function find_best_match(token)
  if #token < 3 then return nil end

  -- Thresholds balanced between catching typos and avoiding false positives
  local max_dist
  if #token <= 3 then
    max_dist = 1       -- 3 chars: only 1 edit (ord→or)
  elseif #token <= 5 then
    max_dist = 2       -- 4-5 chars: 2 edits (form→from, wehre→where)
  else
    max_dist = 2       -- 6+ chars: 2 edits
  end

  local best_word, best_dist = nil, max_dist + 1

  -- Search keywords first (higher priority)
  for _, kw in ipairs(SQL_KEYWORDS) do
    -- Quick length filter: skip if lengths differ too much
    if math.abs(#kw - #token) <= max_dist then
      local d = levenshtein(token, kw)
      if d > 0 and d < best_dist then
        best_dist = d
        best_word = kw
      end
    end
  end

  -- Then search functions
  for _, fn in ipairs(SQL_FUNCTIONS) do
    if math.abs(#fn - #token) <= max_dist then
      local d = levenshtein(token, fn)
      if d > 0 and d < best_dist then
        best_dist = d
        best_word = fn
      end
    end
  end

  if best_word and best_dist <= max_dist then
    return best_word, best_dist
  end
  return nil
end

-- ══════════════════════════════════════════════════════
-- Context: track table/column names seen in buffer
-- so we don't flag them as typos
-- ══════════════════════════════════════════════════════

---Extract identifiers that appear after FROM/JOIN/TABLE/INTO (table names)
---and after SELECT/ON/WHERE/SET/BY = column context
---@param sql string
---@return table set of known identifiers (lowercase)
local function extract_identifiers(sql)
  local ids = {}
  -- Table names: after FROM, JOIN, INTO, UPDATE, TABLE
  for tbl in sql:gmatch("[Ff][Rr][Oo][Mm]%s+([%w_]+)") do ids[tbl:lower()] = true end
  for tbl in sql:gmatch("[Jj][Oo][Ii][Nn]%s+([%w_]+)") do ids[tbl:lower()] = true end
  for tbl in sql:gmatch("[Ii][Nn][Tt][Oo]%s+([%w_]+)") do ids[tbl:lower()] = true end
  for tbl in sql:gmatch("[Uu][Pp][Dd][Aa][Tt][Ee]%s+([%w_]+)") do ids[tbl:lower()] = true end
  for tbl in sql:gmatch("[Tt][Aa][Bb][Ll][Ee]%s+([%w_]+)") do ids[tbl:lower()] = true end
  -- Aliases: after AS
  for alias in sql:gmatch("[Aa][Ss]%s+([%w_]+)") do ids[alias:lower()] = true end
  -- Dot-prefix identifiers: u.username → u, username are identifiers
  for prefix, col in sql:gmatch("([%w_]+)%.([%w_]+)") do
    ids[prefix:lower()] = true
    ids[col:lower()] = true
  end
  -- Parameters @param
  for param in sql:gmatch("@([%w_]+)") do ids[param:lower()] = true end
  -- CTE names (WITH name AS)
  for cte in sql:gmatch("[Ww][Ii][Tt][Hh]%s+([%w_]+)%s+[Aa][Ss]") do ids[cte:lower()] = true end
  -- CREATE TABLE/INDEX identifiers
  for name in sql:gmatch("[Cc][Rr][Ee][Aa][Tt][Ee]%s+%w+%s+([%w_]+)") do ids[name:lower()] = true end
  -- Column definitions in CREATE TABLE (...) or after SET
  for col in sql:gmatch("[Ss][Ee][Tt]%s+([%w_]+)%s*=") do ids[col:lower()] = true end
  -- Column definitions of the form "col TYPE ..." (CREATE/ALTER/DECLARE)
  local upper = sql:upper()
  for col in upper:gmatch("([%w_]+)%s+(INT|BIGINT|SMALLINT|TINYINT|BIT|DECIMAL|NUMERIC|FLOAT|REAL|MONEY|SMALLMONEY|CHAR|NCHAR|VARCHAR|NVARCHAR|TEXT|NTEXT|DATE|TIME|DATETIME2?|SMALLDATETIME|DATETIMEOFFSET|TIMESTAMP|BINARY|VARBINARY|IMAGE|XML|UNIQUEIDENTIFIER)") do
    ids[col:lower()] = true
  end
  -- Identifiers in parentheses after table name: INSERT INTO t(col1, col2)
  for cols_str in sql:gmatch("[Ii][Nn][Tt][Oo]%s+%w+%s*%(([^%)]+)%)") do
    for col in cols_str:gmatch("([%w_]+)") do ids[col:lower()] = true end
  end
  -- REFERENCES table_name (...)
  for tbl in sql:gmatch("[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee][Ss]%s+([%w_]+)") do
    ids[tbl:lower()] = true
  end
  -- Anything that contains _ is likely a user identifier (user_id, created_at, etc.)
  for id in sql:gmatch("([%a_][%w]*_[%w_]+)") do ids[id:lower()] = true end
  -- Any word directly inside function parens: FUNC(word, ...) → word is likely column
  for inner in sql:gmatch("[%w_]+%(([^%)]+)%)") do
    for w in inner:gmatch("([%a_][%w_]*)") do
      if not ALL_KNOWN[w:lower()] then ids[w:lower()] = true end
    end
  end
  -- Words right after ON keyword (index ON table(cols))
  for tbl in sql:gmatch("[Oo][Nn]%s+([%w_]+)") do ids[tbl:lower()] = true end
  -- Anything after GROUP BY, ORDER BY, PARTITION BY
  for col in sql:gmatch("[Bb][Yy]%s+([%w_%.]+)") do
    ids[col:lower():gsub("%..*", "")] = true
    ids[col:lower():gsub(".*%.", "")] = true
  end
  return ids
end

-- ══════════════════════════════════════════════════════
-- Main lint function
-- ══════════════════════════════════════════════════════

---@class LintError
---@field line number 0-indexed
---@field col number|nil 0-indexed
---@field message string
---@field level string "error" | "warn"
---@field token string|nil

---Lint a single SQL statement
---@param sql string
---@param start_line number 0-indexed
---@return LintError[]
function M.lint(sql, start_line)
  local errors = {}
  start_line = start_line or 0
  if not sql or #sql < 3 then return errors end

  local lines = vim.split(sql, "\n", { plain = true })
  local identifiers = extract_identifiers(sql)

  -- ── 1. Balanced parentheses ──
  local open_parens = 0
  local last_open_line = nil
  for i, line in ipairs(lines) do
    local in_str = false
    for j = 1, #line do
      local c = line:sub(j, j)
      if c == "'" then
        if line:sub(j+1, j+1) == "'" then
          -- escaped, skip
        else
          in_str = not in_str
        end
      elseif not in_str then
        if c == "(" then
          open_parens = open_parens + 1
          if last_open_line == nil then last_open_line = i end
        elseif c == ")" then
          open_parens = open_parens - 1
          if open_parens < 0 then
            table.insert(errors, {
              line = start_line + (i - 1),
              col = j - 1,
              message = "Unmatched closing parenthesis ')'",
              level = "error",
              token = ")",
            })
            open_parens = 0
          end
        end
      end
    end
  end
  if open_parens > 0 then
    table.insert(errors, {
      line = start_line + (last_open_line or 1) - 1,
      message = string.format("Unclosed parenthesis: %d '(' without matching ')'", open_parens),
      level = "error",
      token = "(",
    })
  end

  -- ── 2. Balanced quotes ──
  local in_single = false
  local single_start_line = nil
  for i, line in ipairs(lines) do
    local j = 1
    while j <= #line do
      local ch = line:sub(j, j)
      if ch == "'" then
        if line:sub(j+1, j+1) == "'" then
          j = j + 1
        else
          if in_single then in_single = false
          else in_single = true; single_start_line = i end
        end
      end
      j = j + 1
    end
  end
  if in_single then
    table.insert(errors, {
      line = start_line + (single_start_line or 1) - 1,
      message = "Unclosed string literal (missing closing quote ')",
      level = "error",
      token = "'",
    })
  end

  -- ── 3. Fuzzy keyword/function matching ──
  -- Check every token: if it's NOT a known keyword AND NOT an identifier,
  -- see if it's close to a known keyword (typo)
  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    -- Skip comment lines
    if not trimmed:match("^%-%-") then
      -- Remove string literals to avoid false positives
      local clean = trimmed:gsub("'[^']*'", "")
      -- Remove numbers
      clean = clean:gsub("%d+%.?%d*", "")

      for token in clean:gmatch("[%a_][%w_]*") do
        local lower = token:lower()

        -- Skip if: known keyword, known function, or identifier (table/column/alias)
        if not ALL_KNOWN[lower] and not identifiers[lower] then
          -- Skip rất nhiều trường hợp có khả năng là tên cột/bảng:
          -- 1) Rất ngắn (u, o, p, id, yr, mo, ...)
          if #token < 3 then
            goto continue_token
          end

          -- Fuzzy-match cho các token còn lại (khả năng cao là keyword/hàm viết sai)
          local suggestion, dist = find_best_match(lower)
          if suggestion and dist then
            local col = line:lower():find(lower, 1, true)
            table.insert(errors, {
              line = start_line + (i - 1),
              col = col and (col - 1) or nil,
              message = string.format(
                "'%s' → Did you mean '%s'?",
                token, suggestion:upper()
              ),
              level = "error",
              token = token,
            })
          end
        end
        ::continue_token::
      end
    end
  end

  -- ── 4. Structure checks ──
  local upper_sql = sql:upper():gsub("%-%-[^\n]*", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")

  if upper_sql:match("^FROM%s") then
    table.insert(errors, {
      line = start_line,
      message = "Statement starts with FROM — missing SELECT/DELETE/UPDATE?",
      level = "error",
    })
  end

  return errors
end

return M
