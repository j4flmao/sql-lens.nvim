# Changelog

## [0.3.0] - 2026-03-12

### Added
- Dynamic database selection: `dbname` is now optional for MySQL, PostgreSQL, and SQL Server
- `:SqlLensDB` command and `<leader>sD` keymap to pick a database from the server
- Custom floating picker with search filtering and scroll (max 5 visible items)
- `list_databases()` method for MySQL adapter (using `SHOW DATABASES`)
- Auto-prompt database picker when connecting without `dbname`
- MongoDB adapter with `mongosh` support (execute, ping, list_databases, explain)
- Table Explorer: `:SqlLensTables` / `<leader>st` — browse tables/collections, generate preview queries
- Query History: `:SqlLensHistory` / `<leader>sh` — browse and re-run previous queries
  - Persisted to JSON file across sessions (`~/.local/share/nvim/sql-lens-history.json`)
  - `<Tab>` cycles filter: current conn+db → current conn (all dbs) → all connections
  - Preview pane shows full SQL of selected entry
  - Configurable `max_entries` (200) and `max_days` (7) auto-cleanup
- Auto-completion: nvim-cmp source for table and column names (`sql_lens`)
- `list_tables()` and `list_columns()` methods for all adapters

### Changed
- PostgreSQL `_connstr()` defaults to `"postgres"` database when `dbname` is omitted
- Connection picker now shows database status on connect

## [0.2.0] - 2026-03-11

### Added
- MySQL `execute()` and `ping()` methods
- PostgreSQL `execute()` method and `sslmode` support
- Support for preformatted output (mysql `-t`) in result UI
- Laragon/XAMPP setup guide in README

### Fixed
- MySQL empty password causing hang (Laragon/XAMPP)
- `SqlLensDisconnect` not working with single connection

## [0.1.0] - 2026-03-10

### Added
- Initial release
- PostgreSQL support with EXPLAIN ANALYZE JSON
- MySQL support with EXPLAIN FORMAT=JSON
- SQL Server support with SHOWPLAN_XML
- SQLite support with EXPLAIN QUERY PLAN
- Inline virtual text display
- Floating detail window
- Connection picker (vim.ui.select)
- Smart performance hints (Seq Scan, high cost, row estimate drift)
- Treesitter-based SQL statement extraction
- Fallback statement extraction without Treesitter
- .env credential loading
- Debounced real-time analysis
