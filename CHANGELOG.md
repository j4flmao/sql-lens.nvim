# Changelog

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
