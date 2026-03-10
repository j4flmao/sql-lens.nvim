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
