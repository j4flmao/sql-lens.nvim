# sql-lens.nvim

Real-time SQL query plan analyzer — see EXPLAIN output inline + execute queries directly in Neovim.

![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.9-green?logo=neovim)
![License](https://img.shields.io/badge/License-MIT-blue)

## ✨ Features

- ⚡ Real-time EXPLAIN as you type (debounced)
- 🔌 PostgreSQL, MySQL, SQL Server (including LocalDB), SQLite, MongoDB
- 💡 Smart hints: missing indexes, high cost, row estimate drift
- 🎨 Inline virtual text + floating detail window
- 🏃 Execute queries & view results in a formatted table inside Neovim
- 📊 Performance stats: execution time, CPU, logical reads, IO per table
- 🔐 Credentials via `.env` files or environment variables
- 🔑 SQL Server Windows Auth (trusted connection) support
- 📋 Table Explorer: browse tables/collections and generate preview queries
- 🕐 Query History: re-run previous queries from a searchable picker
- 🔤 Auto-completion: table & column names via nvim-cmp integration
- 📤 Export Results: save query results to CSV, JSON, or Markdown
- 📄 Result Pagination: large results split into pages with `[`/`]` navigation
- 🔖 Saved Connections: bookmark connections to JSON file (persist across sessions)
- 📊 Statusline: lualine component showing current connection + database
- ✍️ SQL Formatter: beautify SQL with proper keywords & indentation
- 🔍 Schema Diff: compare schemas between two databases
- 💡 Index Suggestions: auto-suggest `CREATE INDEX` from EXPLAIN plans
- 📈 Cost Trend: track query cost over time with sparkline charts
- 📊 Chart View: ASCII bar charts from query results
- 📏 Table Size Dashboard: row counts + disk size for all tables
- 🕸️ Dependency Graph: view/proc → table relationships in browser

## 📦 Installation

### lazy.nvim

```lua
{
  "j4flmao/sql-lens.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = { "sql", "plpgsql", "mysql" },
  keys = {
    { "<leader>sq", desc = "SqlLens Toggle" },
    { "<leader>sc", desc = "SqlLens Connect" },
    { "<leader>se", desc = "SqlLens Explain" },
    { "<leader>sd", desc = "SqlLens Detail" },
    { "<leader>sr", desc = "SqlLens Run query" },
    { "<leader>sR", desc = "SqlLens Run all" },
  },
  opts = {
    connections = {
      -- Add your connections here (see below)
    },
  },
}
```

## 🔌 Connection Setup

### SQL Server (LocalDB — Windows Auth)

```lua
require("sql-lens").setup({
  connections = {
    {
      name   = "local-sqlserver",
      type   = "sqlserver",
      host   = [[(localdb)\MSSQLLocalDB]],  -- or "localhost" / "server\instance"
      dbname = "MyDatabase",  -- optional: omit to pick database later via :SqlLensDB
      -- No user/password needed → uses Windows Authentication
    },
  },
})
```

### SQL Server (SQL Auth — user/password)

```lua
require("sql-lens").setup({
  connections = {
    {
      name     = "dev-server",
      type     = "sqlserver",
      host     = "192.168.1.100",
      port     = 1433,          -- default 1433
      dbname   = "MyApp",       -- optional: omit to pick database later via :SqlLensDB
      user     = "sa",
      password = "${MSSQL_PASS}",  -- read from env var
      -- On Linux/macOS if you need to trust the server certificate:
      -- sqlcmd_args = { "-C" },
    },
  },
})
```

### PostgreSQL

```lua
require("sql-lens").setup({
  connections = {
    {
      name     = "local-pg",
      type     = "postgres",
      host     = "localhost",
      port     = 5432,
      user     = "postgres",
      password = "${PG_PASS}",
      dbname   = "mydb",         -- optional: omit to pick database later via :SqlLensDB
      -- sslmode = "require",
    },
  },
})
```

### MySQL / MariaDB

```lua
require("sql-lens").setup({
  connections = {
    {
      name     = "dev-mysql",
      type     = "mysql",
      host     = "127.0.0.1",
      port     = 3306,
      user     = "root",
      password = "${MYSQL_PASS}",
      dbname   = "app",          -- optional: omit to pick database later via :SqlLensDB
    },
  },
})
```

**Laragon / XAMPP (no password):**

```lua
{
  name     = "laragon-mysql",
  type     = "mysql",
  host     = "127.0.0.1",
  port     = 3306,
  user     = "root",
  password = "",              -- empty password is supported
  dbname   = "my_database",  -- optional: omit to pick database later via :SqlLensDB
}
```

> **Windows note:** Make sure `mysql` is in your system PATH.
> For Laragon, add `C:\laragon\bin\mysql\mysql-x.x.x-winx64\bin` to your PATH environment variable.

### MongoDB

```lua
require("sql-lens").setup({
  connections = {
    {
      name = "local-mongo",
      type = "mongodb",
      host = "127.0.0.1",
      port = 27017,
      dbname = "mydb",          -- optional: omit to pick database later via :SqlLensDB
      -- user = "admin",        -- optional: omit for no-auth (default Docker)
      -- password = "${MONGO_PASS}",
      -- authSource = "admin",  -- optional: auth database
    },
  },
})
```

> **Note:** Requires `mongosh` in your PATH. Queries are JavaScript (mongosh syntax),
> e.g. `db.users.find({age: {$gt: 25}})`.

### SQLite

```lua
require("sql-lens").setup({
  connections = {
    {
      name = "local-db",
      type = "sqlite",
      path = vim.fn.expand("~/projects/app/data.db"),
    },
  },
})
```

### Multiple connections

```lua
require("sql-lens").setup({
  connections = {
    { name = "dev-pg",     type = "postgres",  host = "localhost", dbname = "dev",  user = "postgres", password = "secret" },
    { name = "staging-pg", type = "postgres",  host = "staging.company.com", dbname = "app", user = "readonly", password = "${STAGING_PG_PASS}" },
    { name = "local-sql",  type = "sqlserver", host = [[(localdb)\MSSQLLocalDB]], dbname = "MyDB" },
    { name = "mongo",      type = "mongodb",   host = "127.0.0.1", port = 27017 },
    { name = "sqlite",     type = "sqlite",    path = "~/app.db" },
  },
})
-- Use <leader>sc or :SqlLensConnect to pick a connection
-- Or :SqlLensUse dev-pg to switch directly by name
```

### Credentials from .env

Create a `.env` file at the project root:

```bash
PG_PASS=mysecretpassword
MYSQL_PASS=rootpass
MSSQL_PASS=sa_password
```

The plugin will automatically read `.env` and replace `${VAR_NAME}` in the config. Remember to add `.env` to `.gitignore`!

### Project-local config (`.sql-lens.lua`)

Create a `.sql-lens.lua` file at the project root to override config per project:

```lua
-- .sql-lens.lua
return {
  default_connection = "dev-pg",
  connections = {
    { name = "dev-pg", type = "postgres",
      host = "localhost", dbname = "myproject_dev",
      user = "postgres", password = "secret" },
  },
}
```

## ⚙️ Full Configuration

```lua
require("sql-lens").setup({
  -- When to trigger analysis
  trigger = {
    on_write    = true,     -- analyze on save (BufWritePost)
    on_change   = true,     -- analyze while typing (with debounce)
    debounce_ms = 500,      -- wait 500ms after last change
    min_length  = 10,       -- ignore very short queries
  },

  -- Display
  display = {
    mode           = "virtual",  -- "virtual" | "float" | "sidebar"
    virtual_prefix = "󰋼 ",
    show_cost      = true,
    show_rows      = true,
    show_warnings  = true,
    max_virtual_width = 80,
    float = {
      border = "rounded",
      width  = 70,
      height = 20,
    },
  },

  -- Thresholds
  thresholds = {
    cost_warn     = 1000,    -- highlight in yellow when cost > 1000
    cost_error    = 10000,   -- highlight in red when cost > 10000
    rows_warn     = 100000,
    seq_scan_warn = true,    -- always warn on full table scan
  },

  -- Query history
  history = {
    max_entries = 200,   -- max entries to keep
    max_days    = 7,     -- auto-delete entries older than N days
  },

  -- Connections (see Connection Setup section)
  connections = {},

  -- Secrets
  secrets = {
    use_env    = true,  -- read ${VAR} from environment
    use_dotenv = true,  -- search for .env in project root
  },

  -- Keymaps (set any to false to disable)
  keymaps = {
    toggle      = "<leader>sq",   -- enable/disable inline analysis
    explain     = "<leader>se",   -- explain all queries
    show_detail = "<leader>sd",   -- floating detail window
    connect     = "<leader>sc",   -- connection picker
    pick_db     = "<leader>sD",   -- pick database from server
    run         = "<leader>sr",   -- run query at cursor (visual: run selection)
    run_all     = "<leader>sR",   -- run all queries in buffer
    explore     = "<leader>st",   -- explore tables
    columns     = "<leader>sC",   -- column picker (multi-select)
    er_diagram  = "<leader>sE",   -- ER diagram in browser
    schema_diff = "<leader>sS",   -- compare schemas
    history     = "<leader>sh",   -- query history
    snippets    = "<leader>si",   -- SQL snippet templates
    format      = "<leader>sf",   -- format/beautify SQL
    cost_trend  = "<leader>sT",   -- cost trend chart
    result_diff = "<leader>sX",   -- result diff (run & compare)
    report      = "<leader>sH",   -- HTML performance report
  },
})
```

### Warnings & hints (optional)

By default sql-lens.nvim will show performance hints inline, for example:

- Sequential scans on large tables (`Seq Scan → consider adding an index`)
- High cost / high row count plans

You can tune or disable these warnings:

```lua
require("sql-lens").setup({
  -- hide inline warning lines (keep them in detail/report)
  display = {
    show_warnings = false,
  },

  -- disable specific rules
  thresholds = {
    seq_scan_warn = false,  -- do not warn on full table scans
  },
})
```

## 🎮 Commands

### Connection & Database

| Command | Description |
|---------|-------------|
| `:SqlLensConnect` | Open connection picker (auto-saves file binding) |
| `:SqlLensDisconnect` | Disconnect current buffer |
| `:SqlLensDB` | Pick database from server (dynamic list) |
| `:SqlLensSaveConn` | Save current connection as bookmark (persists to JSON) |
| `:SqlLensUse {name}` | Switch connection directly by name |

### Query Execution

| Command | Description |
|---------|-------------|
| `:SqlLensRun` | Execute query at cursor, show results |
| `:SqlLensRunAll` | Execute all queries in the buffer |
| `:SqlLensRunSelection` | Execute visually selected SQL (supports multi-statement) |
| `:SqlLensResultDiff` | Run query and compare with previous result (diff view) |

### Analysis & Explain

| Command | Description |
|---------|-------------|
| `:SqlLensToggle` | Enable/disable inline EXPLAIN analysis |
| `:SqlLensExplain` | Manually trigger EXPLAIN on all queries |
| `:SqlLensFloatDetail` | Show detailed plan tree in floating window |
| `:SqlLensCostTrend` | Show cost trend chart with history for query at cursor |
| `:SqlLensReport` | Generate HTML performance report |

### Schema & Exploration

| Command | Description |
|---------|-------------|
| `:SqlLensTables` | Browse tables/collections, select to generate `SELECT * LIMIT 50` |
| `:SqlLensColumns` | Multi-select columns with checkboxes, generate custom SELECT |
| `:SqlLensER` | Generate ER diagram (opens in browser with Mermaid.js) |
| `:SqlLensSchemaDiff` | Compare schemas between 2 connections (shows migration SQL) |
| `:SqlLensDepGraph` | Dependency graph: views/procs → tables (opens in browser) |

### Visualization

| Command | Description |
|---------|-------------|
| `:SqlLensChart` | Bar chart from last query result (auto-detects numeric columns) |
| `:SqlLensDashboard` | Table size dashboard: row counts + disk size, sorted by size |

### Editing & Productivity

| Command | Description |
|---------|-------------|
| `:SqlLensFormat` | Format/beautify SQL (uppercase keywords, proper indentation) |
| `:SqlLensSnippets` | Insert SQL template (CRUD, JOIN, CTE, window functions, etc.) |
| `:SqlLensHistory` | Browse query history with preview (`<Tab>` to cycle filter) |
| `:SqlLensExport {fmt}` | Export last result to file (`csv`, `json`, or `md`) |

## ⌨️ Default Keymaps

### Normal Mode — Global

| Key | Mode | Action |
|-----|------|--------|
| `<leader>sc` | n | Connection picker |
| `<leader>sD` | n | Pick database from server |
| `<leader>sq` | n | Toggle inline analysis on/off |
| `<leader>se` | n | Explain all queries |
| `<leader>sd` | n | Show detail in floating window |
| `<leader>sr` | n | Run query at cursor |
| `<leader>sr` | v | Run selected SQL |
| `<leader>sR` | n | Run all queries in buffer |
| `<leader>st` | n | Explore tables (generates SELECT) |
| `<leader>sC` | n | Column picker (multi-select → SELECT) |
| `<leader>sE` | n | ER diagram (opens in browser) |
| `<leader>sS` | n | Schema diff between 2 connections |
| `<leader>sh` | n | Query history (`<Tab>` cycles filter) |
| `<leader>si` | n | SQL snippet templates |
| `<leader>sf` | n/v | Format SQL |
| `<leader>sT` | n | Cost trend chart |
| `<leader>sX` | n | Result diff (run & compare) |
| `<leader>sG` | n | Chart view (bar chart from result) |
| `<leader>sZ` | n | Table size dashboard |
| `<leader>sP` | n | Dependency graph (opens in browser) |
| `<leader>sH` | n | HTML performance report |

### Result Buffer — Inside Result Split

| Key | Action |
|-----|--------|
| `q` | Close result panel |
| `E` | Export format picker |
| `ec` | Export to CSV |
| `ej` | Export to JSON |
| `em` | Export to Markdown |
| `]` | Next page (large results, 50 rows/page) |
| `[` | Previous page |
| `H` / `L` | Scroll left / right |
| `←` / `→` | Scroll horizontally |

### Picker — Inside Any Picker Window

| Key | Action |
|-----|--------|
| `j` / `k` / `↑` / `↓` | Navigate items |
| `Enter` | Confirm selection |
| `Esc` / `q` | Cancel |
| Type any letter | Filter/search items |
| `Backspace` | Delete search character |
| `Ctrl+w` | Clear search |
| `Ctrl+d` / `Ctrl+u` | Page down / up |
| `Tab` | Toggle filter mode (history only) |
| `Space` | Toggle checkbox (column picker only) |
| `a` | Select/deselect all (column picker only) |

## 🔧 Requirements

| Database   | Required CLI | Install |
|-----------|--------------|---------|
| PostgreSQL | `psql` | `brew install postgresql` / `apt install postgresql-client` |
| MySQL | `mysql` | `brew install mysql-client` / `apt install mysql-client` / Laragon (add to PATH) |
| SQL Server | `sqlcmd` | [Microsoft ODBC Driver](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility) |
| MongoDB | `mongosh` | [MongoDB Shell](https://www.mongodb.com/try/download/shell) / `brew install mongosh` |
| SQLite | `sqlite3` | usually available / `brew install sqlite` |

- **Neovim >= 0.9**
- **nvim-treesitter** with SQL parser (optional, improves detection)

## 📖 Workflow Demo

1. Open a `.sql` file → plugin analyzes all queries and shows inline cost
2. `<leader>sc` — Connect to a database server
3. `<leader>sD` — Pick a database (or auto-prompted if no `dbname`)
4. `<leader>st` — Browse tables, select one → generates `SELECT * FROM ... LIMIT 50`
5. `<leader>sr` — Run the query at cursor, show table result + stats
6. `<leader>sh` — Browse query history, select to re-run
7. `<leader>se` — Refresh explain plan (after creating indexes)
8. `<leader>sd` — View detailed plan tree + IO stats
9. Start typing SQL → nvim-cmp suggests table and column names
10. `E` — Export results to CSV/JSON/Markdown
11. `]`/`[` — Navigate pages if result has 50+ rows

## 📊 Statusline (lualine)

Add the sql-lens component to your lualine config:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      require("sql-lens.statusline").lualine,
    },
  },
})
```

Shows ` connection/database` in the statusline when editing SQL files.

## 🔖 Saved Connections (Bookmarks)

Save frequently used connections so you don't have to configure them every time:

```vim
:SqlLensSaveConn     " Save current active connection as a bookmark
```

Bookmarks are stored in `~/.local/share/nvim/sql-lens-bookmarks.json` and
automatically loaded alongside your config connections on startup.

## License

MIT
