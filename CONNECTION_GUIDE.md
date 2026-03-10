# CONNECTION_GUIDE.md — sql-lens.nvim

## Quản Lý Connections

### 1. Cấu hình trực tiếp trong setup()

```lua
require("sql-lens").setup({
  connections = {
    { name = "dev-pg",    type = "postgres",  ... },
    { name = "dev-mysql", type = "mysql",     ... },
    { name = "local-db",  type = "sqlite", path = "~/app.db" },
  }
})
```

### 2. Đọc từ .env tự động

Nếu `secrets.use_env = true`, plugin sẽ tìm các biến môi trường:

```bash
# .env trong project root
SQL_LENS_PG_HOST=localhost
SQL_LENS_PG_PORT=5432
SQL_LENS_PG_USER=postgres
SQL_LENS_PG_PASS=mysecret
SQL_LENS_PG_DB=mydb

SQL_LENS_MYSQL_HOST=127.0.0.1
SQL_LENS_MYSQL_USER=root
SQL_LENS_MYSQL_PASS=rootpass
SQL_LENS_MYSQL_DB=app
```

Plugin tự sinh connection objects từ các biến này.

### 3. Profile theo project (`.sql-lens.lua`)

Tạo file `.sql-lens.lua` ở root project:

```lua
-- .sql-lens.lua
return {
  default_connection = "dev-pg",
  connections = {
    { name = "dev-pg", type = "postgres",
      host = "localhost", dbname = "myproject_dev",
      user = "postgres", password = "dev123" },
  }
}
```

Plugin tự detect và load khi mở file SQL trong project đó.

### 4. Chọn connection runtime

```vim
:SqlLensConnect          " Mở picker (telescope/fzf/vim.ui.select)
:SqlLensUse dev-pg       " Set trực tiếp bằng tên
```

Hoặc keymap `<leader>sc` để mở picker.

---

## Supported Database Clients (cần cài)

| DB          | Client cần có | Cài đặt                         |
|-------------|---------------|---------------------------------|
| PostgreSQL  | `psql`        | `brew install postgresql`       |
| MySQL       | `mysql`       | `brew install mysql-client`     |
| SQL Server  | `sqlcmd`      | Microsoft ODBC Driver           |
| SQLite      | `sqlite3`     | `brew install sqlite` (built-in)|
| MariaDB     | `mysql`       | Dùng MySQL adapter              |
| CockroachDB | `cockroach`   | CockroachDB CLI                 |

---

## Security Best Practices

1. **Không hardcode password** trong config — dùng env vars
2. **Dùng .gitignore** để exclude `.sql-lens.lua` nếu chứa credentials
3. **Dùng readonly user** cho explain — không cần write permission
4. **SSH tunnel** cho production DB:

```lua
{ name = "prod-via-tunnel",
  type = "postgres",
  host = "localhost",  -- tunnel local
  port = 15432,        -- forwarded port
  user = "readonly",
  password = "${PROD_RO_PASS}",
  dbname = "production" }
```
