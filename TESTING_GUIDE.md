# TESTING_GUIDE.md — sql-lens.nvim

## Setup Test Environment

```bash
# Use plenary.nvim to run tests
cd sql-lens.nvim
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

### `tests/minimal_init.lua`
```lua
vim.opt.rtp:prepend(".")
vim.opt.rtp:prepend("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim")
require("sql-lens").setup({})
```

---

## Unit Tests

### `tests/spec/parser_spec.lua`

```lua
local parser = require("sql-lens.analyzer.parser")

describe("PostgreSQL parser", function()
  local sample_pg = {
    {
      Plan = {
        ["Node Type"]    = "Seq Scan",
        ["Relation Name"] = "users",
        ["Total Cost"]   = 1234.5,
        ["Plan Rows"]    = 1000,
        ["Actual Rows"]  = 50000,
        ["Actual Total Time"] = 123.4,
      },
      ["Execution Time"] = 125.0,
    }
  }

  it("parses node type", function()
    local node = parser.parse(sample_pg, "postgres")
    assert.equals("Seq Scan", node.node_type)
  end)

  it("parses total cost", function()
    local node = parser.parse(sample_pg, "postgres")
    assert.equals(1234.5, node.total_cost)
  end)

  it("parses execution time", function()
    local node = parser.parse(sample_pg, "postgres")
    assert.equals(125.0, node.execution_time)
  end)
end)
```

### `tests/spec/hints_spec.lua`

```lua
local hints_mod = require("sql-lens.analyzer.hints")
hints_mod.setup({ cost_warn = 100, cost_error = 1000, seq_scan_warn = true })

describe("hints analyzer", function()
  it("warns on Seq Scan", function()
    local plan = {
      node_type = "Seq Scan",
      relation_name = "orders",
      total_cost = 50,
      rows = 100,
      plans = {},
    }
    local hints = hints_mod.analyze(plan)
    assert.is_true(#hints > 0)
    assert.equals("warn", hints[1].level)
  end)

  it("errors on very high cost", function()
    local plan = {
      node_type = "Hash Join",
      total_cost = 99999,
      rows = 0,
      plans = {},
    }
    local hints = hints_mod.analyze(plan)
    local errors = vim.tbl_filter(function(h) return h.level == "error" end, hints)
    assert.is_true(#errors > 0)
  end)
end)
```

---

## Mock DB for Integration Tests

### `tests/helpers/mock_db.lua`

```lua
-- Create a mock connection that returns a fixed plan to test the UI
local M = {}

function M.new_postgres_mock(plan_data)
  return {
    type = "postgres",
    explain = function(self, sql, cb)
      vim.schedule(function()
        cb(nil, plan_data)
      end)
    end,
  }
end

function M.new_error_mock()
  return {
    type = "postgres",
    explain = function(self, sql, cb)
      vim.schedule(function()
        cb("Connection refused", nil)
      end)
    end,
  }
end

return M
```

---

## CI GitHub Actions

### `.github/workflows/ci.yml`

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Neovim
        uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: stable

      - name: Install plenary.nvim
        run: |
          mkdir -p ~/.local/share/nvim/site/pack/vendor/start
          git clone --depth 1 https://github.com/nvim-lua/plenary.nvim \
            ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim

      - name: Install nvim-treesitter + SQL parser
        run: |
          git clone --depth 1 https://github.com/nvim-treesitter/nvim-treesitter \
            ~/.local/share/nvim/site/pack/vendor/start/nvim-treesitter
          nvim --headless -c "TSInstallSync sql" -c "qa"

      - name: Run tests
        run: |
          nvim --headless \
            -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
            -c "qa"
```
