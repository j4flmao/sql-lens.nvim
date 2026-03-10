# PUBLISH_GUIDE.md — sql-lens.nvim

## Checklist Trước Khi Publish

- [ ] Plugin hoạt động với ít nhất 1 DB (PostgreSQL)
- [ ] `doc/sql-lens.txt` viết xong (`:help sql-lens` hoạt động)
- [ ] README có gif/screenshot demo
- [ ] Tests pass
- [ ] LICENSE file (MIT recommended)
- [ ] CHANGELOG.md có entry v0.1.0

---

## Cấu Trúc `doc/sql-lens.txt`

```
*sql-lens.txt*  Real-time SQL query plan analyzer

Author: Your Name
License: MIT

CONTENTS                                                    *sql-lens-contents*

1. Introduction .............. |sql-lens-intro|
2. Setup ..................... |sql-lens-setup|
3. Commands .................. |sql-lens-commands|
4. Configuration ............. |sql-lens-config|
5. Connections ............... |sql-lens-connections|

==============================================================================
INTRODUCTION                                                  *sql-lens-intro*

sql-lens.nvim shows PostgreSQL/MySQL/SQLServer query execution plans
inline in your buffer as you type SQL.

==============================================================================
COMMANDS                                                   *sql-lens-commands*

:SqlLensConnect         Open connection picker
:SqlLensToggle          Enable/disable inline analysis
:SqlLensExplain         Manually trigger explain on current statement
:SqlLensFloatDetail     Show full plan in floating window
:SqlLensUse {name}      Set active connection by name

 vim:tw=78:ts=8:ft=help:norl:
```

---

## README Template

```markdown
# sql-lens.nvim

Real-time SQL query plan analyzer — see EXPLAIN output inline as you type.

![demo](./demo.gif)

## Features

- ⚡ Real-time EXPLAIN as you type (debounced)
- 🔌 PostgreSQL, MySQL, SQL Server, SQLite
- 💡 Smart hints: missing indexes, high cost, row estimate drift
- 🎨 Inline virtual text + floating detail window
- 🔐 .env credential loading

## Installation

**lazy.nvim:**
\`\`\`lua
{
  "yourname/sql-lens.nvim",
  ft = { "sql", "plpgsql" },
  config = function()
    require("sql-lens").setup({
      connections = {
        { name = "local", type = "postgres",
          host = "localhost", dbname = "mydb",
          user = "postgres", password = "secret" },
      }
    })
  end,
}
\`\`\`

## Requirements

- Neovim >= 0.9
- `psql` / `mysql` / `sqlcmd` CLI in PATH
- nvim-treesitter with SQL parser (optional, improves detection)
```

---

## Đăng lên awesome-neovim

1. Fork https://github.com/rockerBOO/awesome-neovim
2. Thêm vào section "Database" hoặc "Code Analysis":

```markdown
- [yourname/sql-lens.nvim](https://github.com/yourname/sql-lens.nvim) -
  Real-time SQL query plan analyzer with inline EXPLAIN output.
```

3. Gửi PR với title: `Add sql-lens.nvim`

---

## Versioning

```bash
# v0.1.0 — initial release
git tag -a v0.1.0 -m "Initial release: PostgreSQL support"
git push origin v0.1.0

# Lazy.nvim users dùng tag này:
# { "yourname/sql-lens.nvim", version = "v0.1.0" }
```

---

## Roadmap Gợi Ý

| Version | Features |
|---------|----------|
| v0.1.0  | PostgreSQL, virtual text |
| v0.2.0  | MySQL, SQLite |
| v0.3.0  | Floating detail window, SQL Server |
| v0.4.0  | Telescope picker cho connections |
| v0.5.0  | AI-powered index suggestions |
| v1.0.0  | Stable API, full test coverage |
