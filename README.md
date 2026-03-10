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

### Nhiều connections cùng lúc

```lua
require("sql-lens").setup({
  connections = {
    { name = "dev-pg",     type = "postgres",  host = "localhost", dbname = "dev",  user = "postgres", password = "secret" },
    { name = "staging-pg", type = "postgres",  host = "staging.company.com", dbname = "app", user = "readonly", password = "${STAGING_PG_PASS}" },
    { name = "local-sql",  type = "sqlserver", host = [[(localdb)\MSSQLLocalDB]], dbname = "MyDB" },
    { name = "sqlite",     type = "sqlite",    path = "~/app.db" },
  },
})
-- Dùng <leader>sc hoặc :SqlLensConnect để chọn connection
-- Hoặc :SqlLensUse dev-pg để chọn trực tiếp
```

### Credentials từ .env

Tạo file `.env` ở project root:

```bash
PG_PASS=mysecretpassword
MYSQL_PASS=rootpass
MSSQL_PASS=sa_password
```

Plugin tự đọc `.env` và thay thế `${VAR_NAME}` trong config. Nhớ thêm `.env` vào `.gitignore`!

### Project-local config (`.sql-lens.lua`)

Tạo file `.sql-lens.lua` ở root project để override config per-project:

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
  -- Khi nào trigger analyze
  trigger = {
    on_write    = true,     -- analyze khi save file
    on_change   = true,     -- analyze khi gõ (có debounce)
    debounce_ms = 500,      -- chờ 500ms sau khi ngưng gõ
    min_length  = 10,       -- bỏ qua query quá ngắn
  },

  -- Hiển thị
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

  -- Ngưỡng cảnh báo
  thresholds = {
    cost_warn     = 1000,    -- highlight vàng khi cost > 1000
    cost_error    = 10000,   -- highlight đỏ khi cost > 10000
    rows_warn     = 100000,
    seq_scan_warn = true,    -- luôn cảnh báo full table scan
  },

  -- Connections (xem phần Connection Setup)
  connections = {},

  -- Bảo mật
  secrets = {
    use_env    = true,  -- đọc ${VAR} từ env
    use_dotenv = true,  -- tìm .env trong project root
  },

  -- Keymaps (set = false để tắt)
  keymaps = {
    toggle      = "<leader>sq",   -- bật/tắt plugin
    explain     = "<leader>se",   -- show explain plan
    show_detail = "<leader>sd",   -- floating window chi tiết
    connect     = "<leader>sc",   -- chọn connection
    run         = "<leader>sr",   -- chạy query tại cursor
    run_all     = "<leader>sR",   -- chạy tất cả queries
  },
})
```

## 🎮 Commands

| Command | Description |
|---------|-------------|
| `:SqlLensConnect` | Mở picker chọn connection |
| `:SqlLensDisconnect` | Ngắt connection buffer hiện tại |
| `:SqlLensToggle` | Bật/tắt inline analysis |
| `:SqlLensExplain` | Analyze tất cả queries trong file |
| `:SqlLensFloatDetail` | Xem plan chi tiết trong floating window |
| `:SqlLensRun` | Chạy query tại cursor, hiện kết quả |
| `:SqlLensRunAll` | Chạy tất cả queries trong file |
| `:SqlLensUse {name}` | Đổi connection theo tên |

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

| Database | CLI cần có | Cài đặt |
|----------|-----------|---------|
| PostgreSQL | `psql` | `brew install postgresql` / `apt install postgresql-client` |
| MySQL | `mysql` | `brew install mysql-client` / `apt install mysql-client` |
| SQL Server | `sqlcmd` | [Microsoft ODBC Driver](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility) |
| SQLite | `sqlite3` | Thường có sẵn / `brew install sqlite` |

- **Neovim >= 0.9**
- **nvim-treesitter** với SQL parser (optional, cải thiện detection)

## 📖 Workflow Demo

1. Mở file `.sql` → plugin tự analyze tất cả queries, hiện cost inline
2. `<leader>sr` — Chạy query tại cursor, xem kết quả dạng bảng + stats
3. `<leader>se` — Refresh explain plan (sau khi tạo index)
4. `<leader>sd` — Xem chi tiết plan tree + IO stats
5. `<leader>sc` — Đổi sang connection khác

## License

MIT
