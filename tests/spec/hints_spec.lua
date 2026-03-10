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
