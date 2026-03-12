# CONNECTION_GUIDE.md — sql-lens.nvim

## Managing Connections

### 1. Configure directly in setup()

```lua
require("sql-lens").setup({
  connections = {
    { name = "dev-pg",    type = "postgres",  ... },  -- dbname optional
    { name = "dev-mysql", type = "mysql",     ... },  -- dbname optional
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
:SqlLensConnect          " Open picker
:SqlLensUse dev-pg       " Switch directly by name
:SqlLensDB               " Pick database from server (dynamic list)
```

Or use `<leader>sc` to open the connection picker, `<leader>sD` to pick a database.

### 5. Dynamic database selection

Connect to a server without specifying `dbname`, then pick a database at runtime:

```lua
require("sql-lens").setup({
  connections = {
    { name = "dev-mysql", type = "mysql",
      host = "127.0.0.1", port = 3306,
      user = "root", password = "" },
      -- no dbname → will prompt to pick after connecting
  }
})
```

Workflow:
1. `:SqlLensConnect` → pick connection (auto-prompts database picker if no `dbname`)
2. `:SqlLensDB` or `<leader>sD` → pick/switch database anytime
3. Run queries on the selected database
4. Create a new database → `:SqlLensDB` again to see it in the list

---

## Supported Database Clients (required)

| DB          | Required CLI | Install                         |
|-------------|-------------|---------------------------------|
| PostgreSQL  | `psql`      | `brew install postgresql`       |
| MySQL       | `mysql`     | `brew install mysql-client`     |
| SQL Server  | `sqlcmd`    | Microsoft ODBC Driver           |
| SQLite      | `sqlite3`   | `brew install sqlite` (built-in)|
| MongoDB     | `mongosh`   | MongoDB Shell                   |
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
  dbname = "production" }  -- optional: omit to pick later via :SqlLensDB
```
