# sql-lens.nvim

Real-time SQL query plan analyzer — see EXPLAIN output inline + execute queries directly in Neovim.

![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.9-green?logo=neovim)
![License](https://img.shields.io/badge/License-MIT-blue)

## ✨ Features

- ⚡ Real-time EXPLAIN as you type (debounced)
- 🔌 PostgreSQL, MySQL, SQL Server (including LocalDB), SQLite
- 💡 Smart hints: missing indexes, high cost, row estimate drift
- 🎨 Inline virtual text + floating detail window
- 🏃 Execute queries & view results in a formatted table inside Neovim
- 📊 Performance stats: execution time, CPU, logical reads, IO per table
- 🔐 Credentials via `.env` files or environment variables
- 🔑 SQL Server Windows Auth (trusted connection) support

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
      -- Thêm connections của bạn ở đây (xem bên dưới)
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
      host   = [[(localdb)\MSSQLLocalDB]],  -- hoặc "localhost" / "server\instance"
      dbname = "MyDatabase",
      -- Không cần user/password → tự dùng Windows Authentication
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
      port     = 1433,          -- mặc định 1433
      dbname   = "MyApp",
      user     = "sa",
      password = "${MSSQL_PASS}",  -- đọc từ env var
      -- Trên Linux/macOS nếu cần trust server certificate:
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
      dbname   = "mydb",
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
      dbname   = "app",
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
  password = "",       -- empty password is supported
  dbname   = "my_database",
}
```

> **Windows note:** Make sure `mysql` is in your system PATH.
> For Laragon, add `C:\laragon\bin\mysql\mysql-x.x.x-winx64\bin` to your PATH environment variable.

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

  -- Connections (see Connection Setup section)
  connections = {},

  -- Secrets
  secrets = {
    use_env    = true,  -- read ${VAR} from environment
    use_dotenv = true,  -- search for .env in project root
  },

  -- Keymaps (set to false to disable)
  keymaps = {
    toggle      = "<leader>sq",   -- enable/disable plugin
    explain     = "<leader>se",   -- show explain plan
    show_detail = "<leader>sd",   -- floating detail window
    connect     = "<leader>sc",   -- choose connection
    run         = "<leader>sr",   -- run query at cursor
    run_all     = "<leader>sR",   -- run all queries
  },
})
```

## 🎮 Commands

| Command | Description |
|---------|-------------|
| `:SqlLensConnect` | Open connection picker |
| `:SqlLensDisconnect` | Disconnect current buffer |
| `:SqlLensToggle` | Enable/disable inline analysis |
| `:SqlLensExplain` | Analyze all queries in the file |
| `:SqlLensFloatDetail` | Show detailed plan in floating window |
| `:SqlLensRun` | Run query at cursor and show result |
| `:SqlLensRunAll` | Run all queries in the file |
| `:SqlLensUse {name}` | Switch connection by name |

## ⌨️ Default Keymaps

| Key | Action |
|-----|--------|
| `<leader>sq` | Toggle on/off |
| `<leader>se` | Explain all queries |
| `<leader>sd` | Float detail window |
| `<leader>sc` | Connection picker |
| `<leader>sr` | Run query at cursor |
| `<leader>sR` | Run all queries |
| `q` | Close result/float panel |

## 🔧 Requirements

| Database   | Required CLI | Install |
|-----------|--------------|---------|
| PostgreSQL | `psql` | `brew install postgresql` / `apt install postgresql-client` |
| MySQL | `mysql` | `brew install mysql-client` / `apt install mysql-client` / Laragon (add to PATH) |
| SQL Server | `sqlcmd` | [Microsoft ODBC Driver](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility) |
| SQLite | `sqlite3` | usually available / `brew install sqlite` |

- **Neovim >= 0.9**
- **nvim-treesitter** with SQL parser (optional, improves detection)

## 📖 Workflow Demo

1. Open a `.sql` file → plugin analyzes all queries and shows inline cost
2. `<leader>sr` — Run the query at cursor, show table result + stats
3. `<leader>se` — Refresh explain plan (after creating indexes)
4. `<leader>sd` — View detailed plan tree + IO stats
5. `<leader>sc` — Switch to another connection

## License

MIT
