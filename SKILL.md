# sql-lens.nvim — SKILL.md
## Bộ Kit Xây Dựng Plugin Neovim: Real-time SQL Query Plan Analyzer

> Plugin hiển thị EXPLAIN ANALYZE inline trong buffer khi bạn gõ SQL,
> hỗ trợ PostgreSQL, MySQL, SQLServer, SQLite, và nhiều hơn nữa.

---

## 📁 Cấu Trúc Thư Mục Chuẩn

```
sql-lens.nvim/
├── plugin/
│   └── sql-lens.vim              ← Auto-load entry, khai báo commands
├── lua/
│   └── sql-lens/
│       ├── init.lua              ← setup(), public API
│       ├── config.lua            ← Default config + validation
│       ├── connections/
│       │   ├── init.lua          ← Connection manager
│       │   ├── postgres.lua      ← PostgreSQL adapter
│       │   ├── mysql.lua         ← MySQL adapter
│       │   ├── sqlserver.lua     ← SQL Server adapter
│       │   ├── sqlite.lua        ← SQLite adapter
│       │   └── base.lua          ← Base adapter interface
│       ├── analyzer/
│       │   ├── init.lua          ← Query analysis orchestrator
│       │   ├── extractor.lua     ← Extract SQL từ buffer (Treesitter)
│       │   ├── parser.lua        ← Parse EXPLAIN output → structured data
│       │   └── hints.lua         ← Sinh performance hints từ plan
│       ├── ui/
│       │   ├── init.lua          ← UI manager
│       │   ├── virtual_text.lua  ← Inline virtual text (extmarks)
│       │   ├── float.lua         ← Floating window chi tiết
│       │   ├── sidebar.lua       ← Split panel view
│       │   └── highlights.lua    ← Highlight groups
│       └── utils/
│           ├── debounce.lua      ← Debounce cho real-time trigger
│           ├── async.lua         ← Async job helpers (vim.loop)
│           └── secrets.lua       ← Đọc .env / vault credentials
├── queries/
│   └── sql/                      ← Treesitter queries cho SQL
│       ├── statements.scm        ← Match SELECT/INSERT/UPDATE
│       └── highlights.scm
├── doc/
│   └── sql-lens.txt              ← :help documentation
├── tests/
│   ├── spec/
│   │   ├── connection_spec.lua
│   │   ├── parser_spec.lua
│   │   └── extractor_spec.lua
│   └── helpers/
│       └── mock_db.lua
├── .github/
│   └── workflows/
│       └── ci.yml
├── README.md
├── CHANGELOG.md
└── LICENSE
```

---

## 🧠 Architecture Flow

```
User gõ SQL trong buffer
        │
        ▼
[TextChangedI / BufWritePost]  ← autocmd trigger
        │
        ▼
[debounce 500ms]               ← tránh spam queries
        │
        ▼
[extractor.lua]
  Dùng Treesitter parse buffer
  Tìm SQL statement dưới cursor
        │
        ▼
[connections/init.lua]
  Lấy active connection cho buffer
  (theo filetype hoặc manual set)
        │
        ▼
[adapter.explain(sql)]         ← async job, không block UI
  PostgreSQL → EXPLAIN (ANALYZE, FORMAT JSON)
  MySQL      → EXPLAIN FORMAT=JSON
  SQLServer  → SET STATISTICS ON + execution plan
        │
        ▼
[parser.lua]
  Parse JSON/text output → normalized PlanNode tree
        │
        ▼
[hints.lua]
  Phân tích PlanNode:
  - Seq Scan? → gợi ý index
  - High cost? → cảnh báo
  - Nested loop? → suggest hash join
        │
        ▼
[ui/virtual_text.lua]
  Render inline bên cạnh câu lệnh
  Dùng nvim_buf_set_extmark()
```

---

## ⚡ Core Files — Code Mẫu

### `plugin/sql-lens.vim`
```vim
if exists('g:loaded_sql_lens') | finish | endif
let g:loaded_sql_lens = 1

command! SqlLensConnect      lua require('sql-lens').connect()
command! SqlLensDisconnect   lua require('sql-lens').disconnect()
command! SqlLensToggle       lua require('sql-lens').toggle()
command! SqlLensExplain      lua require('sql-lens').explain_current()
command! SqlLensFloatDetail  lua require('sql-lens').show_detail()
command! -nargs=1 SqlLensUse lua require('sql-lens').use_connection(<q-args>)

augroup SqlLens
  autocmd!
  autocmd FileType sql,plpgsql lua require('sql-lens').attach_buffer()
augroup END
```

---

### `lua/sql-lens/config.lua`
```lua
local M = {}

M.defaults = {
  -- Khi nào trigger analyze
  trigger = {
    on_write    = true,    -- BufWritePost
    on_change   = true,    -- TextChanged (với debounce)
    debounce_ms = 500,     -- milliseconds
    min_length  = 10,      -- bỏ qua query quá ngắn
  },

  -- Hiển thị
  display = {
    mode          = "virtual",  -- "virtual" | "float" | "sidebar"
    virtual_prefix = "󰋼 ",
    show_cost     = true,
    show_rows     = true,
    show_warnings = true,
    max_virtual_width = 80,
    float = {
      border  = "rounded",
      width   = 70,
      height  = 20,
    },
  },

  -- Ngưỡng cảnh báo
  thresholds = {
    cost_warn     = 1000,
    cost_error    = 10000,
    rows_warn     = 100000,
    seq_scan_warn = true,   -- luôn cảnh báo Seq Scan trên table lớn
  },

  -- Connections
  connections = {},  -- xem CONNECTION_GUIDE.md

  -- Bảo mật
  secrets = {
    use_env    = true,   -- đọc từ .env tự động
    use_dotenv = true,   -- tìm .env trong project root
  },

  -- Keymaps
  keymaps = {
    toggle        = "<leader>sq",
    explain       = "<leader>se",
    show_detail   = "<leader>sd",
    connect       = "<leader>sc",
  },
}

function M.validate(opts)
  vim.validate({
    trigger          = { opts.trigger, "table" },
    display          = { opts.display, "table" },
    ["display.mode"] = { opts.display.mode, function(v)
      return vim.tbl_contains({"virtual","float","sidebar"}, v)
    end, "virtual | float | sidebar" },
  })
end

return M
```

---

### `lua/sql-lens/connections/base.lua`
```lua
-- Interface mà mọi adapter phải implement
local Base = {}
Base.__index = Base

function Base.new(config)
  return setmetatable({ config = config, connected = false }, Base)
end

-- Mỗi adapter override các hàm này:
function Base:connect()    error("Not implemented") end
function Base:disconnect() error("Not implemented") end
function Base:ping()       error("Not implemented") end

---@param sql string  Câu SQL cần explain
---@param cb  function  callback(err, plan_json_string)
function Base:explain(sql, cb)
  error("Not implemented")
end

function Base:wrap_explain(sql)
  error("Not implemented: must return EXPLAIN query string")
end

return Base
```

---

### `lua/sql-lens/connections/postgres.lua`
```lua
local Base   = require("sql-lens.connections.base")
local async  = require("sql-lens.utils.async")

local PG = setmetatable({}, { __index = Base })
PG.__index = PG

function PG.new(config)
  local self = Base.new(config)
  -- config = { host, port, user, password, dbname, sslmode }
  self.type = "postgres"
  return setmetatable(self, PG)
end

-- Tạo connection string psql
function PG:_connstr()
  local c = self.config
  return string.format(
    "postgresql://%s:%s@%s:%s/%s",
    c.user, c.password, c.host or "localhost",
    c.port or 5432, c.dbname
  )
end

-- Wrap SQL thành EXPLAIN ANALYZE JSON
function PG:wrap_explain(sql)
  -- Chỉ explain SELECT/UPDATE/DELETE/INSERT, không explain DDL
  local upper = sql:upper():match("^%s*(%w+)")
  if not vim.tbl_contains({"SELECT","UPDATE","DELETE","INSERT","WITH"}, upper) then
    return nil, "Cannot EXPLAIN " .. (upper or "unknown") .. " statement"
  end
  return string.format(
    "EXPLAIN (ANALYZE true, COSTS true, FORMAT JSON, BUFFERS true) %s",
    sql
  )
end

---@param sql string
---@param cb function(err, result_table)
function PG:explain(sql, cb)
  local explain_sql, err = self:wrap_explain(sql)
  if err then return cb(err, nil) end

  local cmd = {
    "psql", self:_connstr(),
    "--no-psqlrc", "-t", "-A",
    "-c", explain_sql
  }

  async.job(cmd, function(exit_code, stdout, stderr)
    if exit_code ~= 0 then
      return cb(stderr, nil)
    end
    -- psql trả về JSON array trong stdout
    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok then
      return cb("Failed to parse JSON: " .. stdout, nil)
    end
    cb(nil, decoded)
  end)
end

function PG:ping(cb)
  async.job(
    { "psql", self:_connstr(), "-c", "SELECT 1" },
    function(code) cb(code == 0) end
  )
end

return PG
```

---

### `lua/sql-lens/connections/mysql.lua`
```lua
local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local MySQL = setmetatable({}, { __index = Base })
MySQL.__index = MySQL

function MySQL.new(config)
  local self = Base.new(config)
  self.type = "mysql"
  return setmetatable(self, MySQL)
end

function MySQL:_args()
  local c = self.config
  return {
    "mysql",
    "-h", c.host or "127.0.0.1",
    "-P", tostring(c.port or 3306),
    "-u", c.user,
    string.format("-p%s", c.password),
    c.dbname,
    "--silent", "--raw",
  }
end

function MySQL:wrap_explain(sql)
  return "EXPLAIN FORMAT=JSON " .. sql
end

function MySQL:explain(sql, cb)
  local args = self:_args()
  vim.list_extend(args, { "-e", self:wrap_explain(sql) })

  async.job(args, function(code, stdout, stderr)
    if code ~= 0 then return cb(stderr, nil) end
    local ok, data = pcall(vim.json.decode, stdout)
    if not ok then return cb("JSON parse error", nil) end
    cb(nil, data)
  end)
end

return MySQL
```

---

### `lua/sql-lens/connections/sqlserver.lua`
```lua
local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

-- Dùng sqlcmd (Microsoft SQL Server CLI)
local MSSQL = setmetatable({}, { __index = Base })
MSSQL.__index = MSSQL

function MSSQL.new(config)
  local self = Base.new(config)
  self.type = "sqlserver"
  return setmetatable(self, MSSQL)
end

function MSSQL:_args()
  local c = self.config
  return {
    "sqlcmd",
    "-S", string.format("%s,%s", c.host, c.port or 1433),
    "-U", c.user,
    "-P", c.password,
    "-d", c.dbname,
    "-h", "-1",   -- no header
  }
end

-- SQL Server dùng SET STATISTICS + XML plan
function MSSQL:wrap_explain(sql)
  return table.concat({
    "SET STATISTICS TIME ON;",
    "SET STATISTICS IO ON;",
    "SET SHOWPLAN_XML ON;",
    "GO",
    sql,
    "GO",
    "SET SHOWPLAN_XML OFF;",
  }, "\n")
end

function MSSQL:explain(sql, cb)
  local args = self:_args()
  -- Viết query ra temp file (sqlcmd không nhận -Q với multi-line tốt)
  local tmpfile = vim.fn.tempname() .. ".sql"
  vim.fn.writefile(vim.split(self:wrap_explain(sql), "\n"), tmpfile)
  vim.list_extend(args, { "-i", tmpfile })

  async.job(args, function(code, stdout, stderr)
    vim.fn.delete(tmpfile)
    if code ~= 0 then return cb(stderr, nil) end
    -- Parse XML plan → table (simplified)
    cb(nil, { raw = stdout, type = "xml" })
  end)
end

return MSSQL
```

---

### `lua/sql-lens/connections/sqlite.lua`
```lua
local Base  = require("sql-lens.connections.base")
local async = require("sql-lens.utils.async")

local SQLite = setmetatable({}, { __index = Base })
SQLite.__index = SQLite

function SQLite.new(config)
  -- config = { path = "/path/to/db.sqlite" }
  local self = Base.new(config)
  self.type = "sqlite"
  return setmetatable(self, SQLite)
end

function SQLite:wrap_explain(sql)
  return "EXPLAIN QUERY PLAN " .. sql
end

function SQLite:explain(sql, cb)
  async.job(
    { "sqlite3", self.config.path, self:wrap_explain(sql) },
    function(code, stdout, stderr)
      if code ~= 0 then return cb(stderr, nil) end
      -- SQLite output là plain text, parse thủ công
      local rows = {}
      for line in stdout:gmatch("[^\n]+") do
        local id, parent, notused, detail = line:match("(%d+)|(%d+)|(%d+)|(.*)")
        if detail then
          table.insert(rows, { id=tonumber(id), parent=tonumber(parent), detail=detail })
        end
      end
      cb(nil, { type = "sqlite_qp", rows = rows })
    end
  )
end

return SQLite
```

---

### `lua/sql-lens/utils/async.lua`
```lua
-- Chạy external command async, không block Neovim UI
local M = {}

---@param cmd table   argv array, e.g. {"psql", "...", "-c", "..."}
---@param cb  function(exit_code, stdout, stderr)
function M.job(cmd, cb)
  local stdout_data = {}
  local stderr_data = {}

  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,

    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_data, data)
      end
    end,

    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr_data, data)
      end
    end,

    on_exit = function(_, code)
      local out = table.concat(stdout_data, "\n"):gsub("^\n+", ""):gsub("\n+$", "")
      local err = table.concat(stderr_data, "\n"):gsub("^\n+", ""):gsub("\n+$", "")
      vim.schedule(function()
        cb(code, out, err)
      end)
    end,
  })

  if job <= 0 then
    cb(1, "", "Failed to start job: " .. table.concat(cmd, " "))
  end
end

return M
```

---

### `lua/sql-lens/utils/debounce.lua`
```lua
local M = {}

---Tạo debounced function
---@param fn    function  Hàm cần debounce
---@param delay number    Milliseconds
---@return function
function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(delay, 0, vim.schedule_wrap(function()
      timer:close()
      timer = nil
      fn(unpack(args))
    end))
  end
end

return M
```

---

### `lua/sql-lens/analyzer/extractor.lua`
```lua
-- Dùng Treesitter để extract SQL statement dưới cursor
local M = {}

-- Treesitter query để tìm statement nodes
local QUERY_SRC = [[
  (statement) @stmt
  (select_statement) @stmt
  (insert_statement) @stmt
  (update_statement) @stmt
  (delete_statement) @stmt
]]

---Lấy SQL statement mà cursor đang đứng trong
---@param bufnr number
---@return string|nil  SQL text
---@return number|nil  start_line (0-indexed)
function M.get_statement_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "sql")
  if not ok or not parser then
    -- Fallback: lấy toàn bộ buffer nếu không có SQL parser
    return M.fallback_get_statement(bufnr)
  end

  local tree = parser:parse()[1]
  if not tree then return nil end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row    = cursor[1] - 1  -- 0-indexed
  local col    = cursor[2]

  local ok2, query = pcall(vim.treesitter.query.parse, "sql", QUERY_SRC)
  if not ok2 then return M.fallback_get_statement(bufnr) end

  local root = tree:root()
  local best_node = nil
  local best_size = math.huge

  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    local sr, sc, er, ec = node:range()
    -- Cursor nằm trong node này?
    local in_range = (row > sr or (row == sr and col >= sc))
                  and (row < er or (row == er and col <= ec))
    if in_range then
      local size = (er - sr) * 10000 + (ec - sc)
      if size < best_size then
        best_size = size
        best_node = node
      end
    end
  end

  if not best_node then return nil end

  local sr = best_node:range()
  local text = vim.treesitter.get_node_text(best_node, bufnr)
  return text, sr
end

-- Fallback: lấy block SQL bằng cách tìm statement boundary thủ công
function M.fallback_get_statement(bufnr)
  local lines   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor  = vim.api.nvim_win_get_cursor(0)
  local cur_row = cursor[1] - 1

  -- Tìm ra đằng trước đến khi gặp dòng trống hoặc semicolon
  local start_row = cur_row
  while start_row > 0 do
    local line = lines[start_row]
    if line and (line:match("^%s*$") or lines[start_row-1] and lines[start_row-1]:match(";%s*$")) then
      break
    end
    start_row = start_row - 1
  end

  local sql_lines = {}
  for i = start_row + 1, #lines do
    local line = lines[i]
    table.insert(sql_lines, line)
    if line and line:match(";%s*$") then break end
  end

  local sql = table.concat(sql_lines, "\n"):gsub(";%s*$", "")
  if #sql < 5 then return nil end
  return sql, start_row
end

return M
```

---

### `lua/sql-lens/analyzer/parser.lua`
```lua
-- Parse EXPLAIN output từ các DB khác nhau → chuẩn hóa
local M = {}

---@class PlanNode
---@field node_type     string   "Seq Scan" | "Index Scan" | "Hash Join" | ...
---@field relation_name string|nil
---@field total_cost    number
---@field rows          number
---@field actual_rows   number|nil
---@field actual_time   number|nil
---@field plans         PlanNode[]
---@field warnings      string[]

---Parse PostgreSQL EXPLAIN JSON output
---@param json_data table  Decoded JSON từ psql
---@return PlanNode
function M.parse_postgres(json_data)
  -- PostgreSQL trả về array, lấy phần tử đầu
  local plan_wrapper = json_data[1] or json_data
  local plan = plan_wrapper["Plan"] or plan_wrapper

  local function parse_node(node)
    local result = {
      node_type     = node["Node Type"] or "Unknown",
      relation_name = node["Relation Name"],
      total_cost    = node["Total Cost"] or 0,
      startup_cost  = node["Startup Cost"] or 0,
      rows          = node["Plan Rows"] or 0,
      actual_rows   = node["Actual Rows"],
      actual_time   = node["Actual Total Time"],
      loops         = node["Actual Loops"] or 1,
      buffers_hit   = node["Shared Hit Blocks"],
      buffers_read  = node["Shared Read Blocks"],
      plans         = {},
      warnings      = {},
    }

    -- Recursive parse sub-plans
    if node["Plans"] then
      for _, subplan in ipairs(node["Plans"]) do
        table.insert(result.plans, parse_node(subplan))
      end
    end

    return result
  end

  local root = parse_node(plan)
  root.planning_time  = plan_wrapper["Planning Time"]
  root.execution_time = plan_wrapper["Execution Time"]
  return root
end

---Parse MySQL EXPLAIN JSON
function M.parse_mysql(json_data)
  local qb = json_data["query_block"] or {}
  local function parse_node(n)
    return {
      node_type     = n["select_type"] or n["table"] or "Step",
      relation_name = n["table_name"],
      total_cost    = tonumber(n["cost_info"] and n["cost_info"]["query_cost"]) or 0,
      rows          = tonumber(n["rows_examined_per_scan"]) or 0,
      access_type   = n["access_type"],
      key           = n["key"],
      plans         = {},
      warnings      = {},
    }
  end
  return parse_node(qb)
end

---Parse SQLite EXPLAIN QUERY PLAN text rows
function M.parse_sqlite(data)
  local root = { node_type = "Query Plan", plans = {}, warnings = {}, total_cost = 0, rows = 0 }
  for _, row in ipairs(data.rows or {}) do
    table.insert(root.plans, {
      node_type     = row.detail,
      relation_name = row.detail:match("TABLE (%w+)"),
      total_cost    = 0,
      rows          = 0,
      plans         = {},
      warnings      = {},
    })
  end
  return root
end

---Entry point: detect DB type và parse
---@param raw_data table
---@param db_type  string  "postgres" | "mysql" | "sqlite" | "sqlserver"
---@return PlanNode
function M.parse(raw_data, db_type)
  if db_type == "postgres" then
    return M.parse_postgres(raw_data)
  elseif db_type == "mysql" then
    return M.parse_mysql(raw_data)
  elseif db_type == "sqlite" then
    return M.parse_sqlite(raw_data)
  else
    return { node_type = "Unknown", plans = {}, warnings = {}, total_cost = 0, rows = 0 }
  end
end

return M
```

---

### `lua/sql-lens/analyzer/hints.lua`
```lua
-- Sinh performance hints từ PlanNode tree
local M = {}

local cfg_thresholds -- set từ setup()

function M.setup(thresholds)
  cfg_thresholds = thresholds
end

---@param node PlanNode
---@param hints table  accumulator
local function walk(node, hints, depth)
  depth = depth or 0
  local t = cfg_thresholds or {}

  -- 1. Seq Scan cảnh báo
  if node.node_type == "Seq Scan" and node.relation_name then
    if t.seq_scan_warn then
      table.insert(hints, {
        level   = "warn",
        icon    = "󰋽",
        message = string.format("Seq Scan on '%s' — consider adding an index", node.relation_name),
        node    = node,
      })
    end
  end

  -- 2. Chi phí cao
  if node.total_cost >= (t.cost_error or 10000) then
    table.insert(hints, {
      level   = "error",
      icon    = "󰀪",
      message = string.format("Very high cost: %.0f (threshold: %d)", node.total_cost, t.cost_error),
      node    = node,
    })
  elseif node.total_cost >= (t.cost_warn or 1000) then
    table.insert(hints, {
      level   = "warn",
      icon    = "󰀦",
      message = string.format("High cost: %.0f", node.total_cost),
      node    = node,
    })
  end

  -- 3. Rows estimate vs actual mismatch (chỉ PostgreSQL có actual_rows)
  if node.rows and node.actual_rows then
    local ratio = node.actual_rows / math.max(node.rows, 1)
    if ratio > 10 or ratio < 0.1 then
      table.insert(hints, {
        level   = "warn",
        icon    = "󰈇",
        message = string.format(
          "Row estimate off: expected %d, got %d (%.0fx)",
          node.rows, node.actual_rows, ratio
        ),
        node    = node,
      })
    end
  end

  -- 4. Hash Join vs Nested Loop
  if node.node_type == "Nested Loop" and node.total_cost > 500 then
    table.insert(hints, {
      level   = "info",
      icon    = "󰌹",
      message = "Nested Loop with high cost — Hash Join may be more efficient",
      node    = node,
    })
  end

  -- 5. Missing index (Index Scan Not Used)
  if node.node_type == "Index Scan" and not node.key then
    table.insert(hints, {
      level   = "warn",
      icon    = "󰋽",
      message = "Index Scan but no key used — check index condition",
      node    = node,
    })
  end

  -- Đệ quy sub-plans
  for _, child in ipairs(node.plans or {}) do
    walk(child, hints, depth + 1)
  end
end

---@param plan_node PlanNode
---@return table[]  list of hint objects
function M.analyze(plan_node)
  local hints = {}
  walk(plan_node, hints, 0)
  return hints
end

---Tóm tắt 1 dòng để hiện virtual text
---@param plan  PlanNode
---@param hints table[]
---@return string
function M.summary_line(plan, hints)
  local parts = {}

  -- Thời gian thực thi (nếu có)
  if plan.execution_time then
    table.insert(parts, string.format("%.1fms", plan.execution_time))
  end

  -- Cost
  table.insert(parts, string.format("cost=%.0f", plan.total_cost))

  -- Số warnings
  local warns = vim.tbl_filter(function(h) return h.level == "warn" or h.level == "error" end, hints)
  if #warns > 0 then
    table.insert(parts, string.format("⚠ %d issue%s", #warns, #warns > 1 and "s" or ""))
  else
    table.insert(parts, "✓ ok")
  end

  return table.concat(parts, "  ")
end

return M
```

---

### `lua/sql-lens/ui/virtual_text.lua`
```lua
local M = {}

local NS = vim.api.nvim_create_namespace("sql_lens")

-- Highlight groups (xem highlights.lua)
local HL = {
  info  = "SqlLensInfo",
  warn  = "SqlLensWarn",
  error = "SqlLensError",
  ok    = "SqlLensOk",
  dim   = "SqlLensDim",
}

---Xóa toàn bộ virtual text trong buffer
---@param bufnr number
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

---Render summary line dưới câu SQL
---@param bufnr     number
---@param line      number   0-indexed line
---@param summary   string   text hiển thị
---@param level     string   "ok" | "warn" | "error"
function M.render_summary(bufnr, line, summary, level)
  M.clear(bufnr)

  local hl = HL[level] or HL.info
  local prefix = level == "error" and "󰀪 "
              or level == "warn"  and "󰀦 "
              or "󰋼 "

  vim.api.nvim_buf_set_extmark(bufnr, NS, line, 0, {
    virt_text = {
      { "  " .. prefix .. summary, hl },
    },
    virt_text_pos = "eol",
    priority      = 100,
  })
end

---Render danh sách hints dưới dạng virtual lines
---@param bufnr   number
---@param line    number  0-indexed, ngay sau câu SQL
---@param hints   table[]
function M.render_hints(bufnr, line, hints)
  -- Chỉ show tối đa 3 hints inline để không spam
  local show = vim.list_slice(hints, 1, 3)

  local virt_lines = {}
  for _, hint in ipairs(show) do
    local hl = HL[hint.level] or HL.info
    table.insert(virt_lines, {
      { "    " .. hint.icon .. " " .. hint.message, hl }
    })
  end

  if #hints > 3 then
    table.insert(virt_lines, {
      { string.format("    ... và %d issue khác (dùng :SqlLensFloatDetail)", #hints - 3), HL.dim }
    })
  end

  vim.api.nvim_buf_set_extmark(bufnr, NS, line, 0, {
    virt_lines    = virt_lines,
    virt_lines_above = false,
  })
end

return M
```

---

### `lua/sql-lens/ui/highlights.lua`
```lua
local M = {}

function M.setup()
  local groups = {
    SqlLensOk    = { fg = "#4ade80", bold = false },  -- green
    SqlLensInfo  = { fg = "#60a5fa", bold = false },  -- blue
    SqlLensWarn  = { fg = "#facc15", bold = true  },  -- yellow
    SqlLensError = { fg = "#f87171", bold = true  },  -- red
    SqlLensDim   = { fg = "#6b7280", bold = false },  -- gray
    SqlLensBg    = { bg = "#1e2030"               },  -- float bg
  }

  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
```

---

### `lua/sql-lens/init.lua` (Public API)
```lua
local M = {}

local config_mod  = require("sql-lens.config")
local conn_mgr    = require("sql-lens.connections")
local extractor   = require("sql-lens.analyzer.extractor")
local parser      = require("sql-lens.analyzer.parser")
local hints_mod   = require("sql-lens.analyzer.hints")
local vt          = require("sql-lens.ui.virtual_text")
local highlights  = require("sql-lens.ui.highlights")
local debounce    = require("sql-lens.utils.debounce")

M._config  = {}
M._enabled = true

---@param opts table  User config (partial)
function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", config_mod.defaults, opts or {})
  config_mod.validate(M._config)

  highlights.setup()
  hints_mod.setup(M._config.thresholds)
  conn_mgr.setup(M._config.connections)

  -- Keymaps
  local km = M._config.keymaps
  if km then
    vim.keymap.set("n", km.toggle,      M.toggle,       { desc = "SqlLens: toggle" })
    vim.keymap.set("n", km.explain,     M.explain_current, { desc = "SqlLens: explain" })
    vim.keymap.set("n", km.show_detail, M.show_detail,  { desc = "SqlLens: detail" })
    vim.keymap.set("n", km.connect,     M.connect,      { desc = "SqlLens: connect" })
  end
end

-- Attach autocmds cho buffer SQL
function M.attach_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg   = M._config.trigger
  local analyze_debounced = debounce.debounce(
    function() M._run_analysis(bufnr) end,
    cfg.debounce_ms
  )

  local aug = vim.api.nvim_create_augroup("SqlLens_buf_" .. bufnr, { clear = true })

  if cfg.on_change then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer  = bufnr,
      group   = aug,
      callback = analyze_debounced,
    })
  end

  if cfg.on_write then
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer  = bufnr,
      group   = aug,
      callback = function() M._run_analysis(bufnr) end,
    })
  end

  -- Chạy lần đầu ngay khi attach
  M._run_analysis(bufnr)
end

-- Core analysis pipeline
function M._run_analysis(bufnr)
  if not M._enabled then return end

  local sql, start_line = extractor.get_statement_at_cursor(bufnr)
  if not sql or #sql < (M._config.trigger.min_length or 10) then return end

  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vt.render_summary(bufnr, start_line or 0, "No connection — use :SqlLensConnect", "warn")
    return
  end

  conn:explain(sql, function(err, raw_data)
    if err then
      vt.render_summary(bufnr, start_line or 0, "Error: " .. tostring(err):sub(1, 60), "error")
      return
    end

    local plan  = parser.parse(raw_data, conn.type)
    local hints = hints_mod.analyze(plan)
    local level = #vim.tbl_filter(function(h) return h.level == "error" end, hints) > 0 and "error"
               or #vim.tbl_filter(function(h) return h.level == "warn"  end, hints) > 0 and "warn"
               or "ok"

    local summary = hints_mod.summary_line(plan, hints)

    vt.clear(bufnr)
    vt.render_summary(bufnr, start_line or 0, summary, level)
    if #hints > 0 then
      vt.render_hints(bufnr, (start_line or 0) + 1, hints)
    end
  end)
end

function M.toggle()
  M._enabled = not M._enabled
  if not M._enabled then
    vt.clear(vim.api.nvim_get_current_buf())
  else
    M._run_analysis(vim.api.nvim_get_current_buf())
  end
  vim.notify("SqlLens: " .. (M._enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

function M.explain_current()
  M._run_analysis(vim.api.nvim_get_current_buf())
end

function M.show_detail()
  require("sql-lens.ui.float").show_last()
end

function M.connect()
  require("sql-lens.connections").pick_and_connect()
end

function M.use_connection(name)
  conn_mgr.set_active_by_name(vim.api.nvim_get_current_buf(), name)
end

return M
```

---

## 🔌 Hướng Dẫn Cấu Hình User (`CONNECTION_GUIDE.md` → xem file riêng)

```lua
-- Trong init.lua của user:
require("sql-lens").setup({
  connections = {
    -- PostgreSQL
    { name = "local-pg",  type = "postgres",
      host = "localhost", port = 5432,
      user = "postgres",  password = "secret",
      dbname = "mydb" },

    -- MySQL
    { name = "staging-mysql", type = "mysql",
      host = "staging.example.com",
      user = "root", password = "${MYSQL_PASS}",  -- đọc từ env
      dbname = "app" },

    -- SQL Server
    { name = "prod-mssql", type = "sqlserver",
      host = "sqlserver.company.com",
      user = "sa", password = "${MSSQL_PASS}",
      dbname = "Production" },

    -- SQLite
    { name = "local-sqlite", type = "sqlite",
      path = vim.fn.expand("~/projects/app/db.sqlite3") },
  },

  display = {
    mode = "virtual",   -- hoặc "float" | "sidebar"
  },

  thresholds = {
    cost_warn  = 500,
    cost_error = 5000,
  },
})
```
