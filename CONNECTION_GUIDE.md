# CONNECTION_GUIDE.md — sql-lens.nvim

## Managing Connections

### 1. Configure directly in setup()

```lua
require("sql-lens").setup({
  connections = {
    { name = "dev-pg",    type = "postgres",  ... },
    { name = "dev-mysql", type = "mysql",     ... },
    { name = "local-db",  type = "sqlite", path = "~/app.db" },
  }
})
```

### 2. Auto load from .env

If `secrets.use_env = true`, the plugin will look for environment variables:

```bash
# .env at project root
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

The plugin will automatically build connection objects from these variables.

### 3. Per-project profile (`.sql-lens.lua`)

Create a `.sql-lens.lua` file at the project root:

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

The plugin will detect and load this profile when you open SQL files inside that project.

### 4. Choose connection at runtime

```vim
:SqlLensConnect          " Open picker (telescope/fzf/vim.ui.select)
:SqlLensUse dev-pg       " Switch directly by name
```

Or use the `<leader>sc` keymap to open the picker.

---

## Supported Database Clients (required)

| DB          | Required CLI | Install                         |
|-------------|-------------|---------------------------------|
| PostgreSQL  | `psql`      | `brew install postgresql`       |
| MySQL       | `mysql`     | `brew install mysql-client`     |
| SQL Server  | `sqlcmd`    | Microsoft ODBC Driver           |
| SQLite      | `sqlite3`   | `brew install sqlite` (built-in)|
| MariaDB     | `mysql`     | use MySQL adapter               |
| CockroachDB | `cockroach` | CockroachDB CLI                 |

---

## Security Best Practices

1. **Never hardcode passwords** in config — use environment variables
2. **Use .gitignore** to exclude `.sql-lens.lua` if it contains credentials
3. **Use readonly users** for explain/analysis — no write permission required
4. **Use SSH tunnels** for production databases:

```lua
{ name = "prod-via-tunnel",
  type = "postgres",
  host = "localhost",  -- local side of the tunnel
  port = 15432,        -- forwarded port
  user = "readonly",
  password = "${PROD_RO_PASS}",
  dbname = "production" }
```
