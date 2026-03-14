local M = {}

function M.parse_postgres(json_data)
  local plan_wrapper = json_data[1] or json_data
  local plan = plan_wrapper["Plan"] or plan_wrapper

  local function parse_node(node)
    local result = {
      node_type     = node["Node Type"] or "Unknown",
      relation_name = node["Relation Name"],
      total_cost    = node["Total Cost"] or 0,
      startup_cost  = node["Startup Cost"] or 0,
      rows          = node["Plan Rows"] or 0,
      actual_rows   = node["Actual Rows"],
      actual_time   = node["Actual Total Time"],
      loops         = node["Actual Loops"] or 1,
      buffers_hit   = node["Shared Hit Blocks"],
      buffers_read  = node["Shared Read Blocks"],
      filter        = node["Filter"],
      index_cond    = node["Index Cond"],
      sort_key      = node["Sort Key"],
      hash_cond     = node["Hash Cond"],
      join_filter   = node["Join Filter"],
      plans         = {},
      warnings      = {},
    }

    if node["Plans"] then
      for _, subplan in ipairs(node["Plans"]) do
        table.insert(result.plans, parse_node(subplan))
      end
    end

    return result
  end

  local root = parse_node(plan)
  root.planning_time  = plan_wrapper["Planning Time"]
  root.execution_time = plan_wrapper["Execution Time"]
  return root
end

function M.parse_mysql(json_data)
  local qb = json_data["query_block"] or {}
  local function parse_node(n)
    return {
      node_type     = n["select_type"] or n["table"] or "Step",
      relation_name = n["table_name"],
      total_cost    = tonumber(n["cost_info"] and n["cost_info"]["query_cost"]) or 0,
      rows          = tonumber(n["rows_examined_per_scan"]) or 0,
      access_type   = n["access_type"],
      key           = n["key"],
      plans         = {},
      warnings      = {},
    }
  end
  return parse_node(qb)
end

function M.parse_sqlite(data)
  local root = { node_type = "Query Plan", plans = {}, warnings = {}, total_cost = 0, rows = 0 }
  for _, row in ipairs(data.rows or {}) do
    table.insert(root.plans, {
      node_type     = row.detail,
      relation_name = row.detail:match("TABLE (%w+)"),
      total_cost    = 0,
      rows          = 0,
      plans         = {},
      warnings      = {},
    })
  end
  return root
end

---Parse SQL Server SHOWPLAN_ALL + STATISTICS TIME/IO output
---Format: pipe-separated columns from SHOWPLAN_ALL, plus STATISTICS text
function M.parse_sqlserver(data)
  local raw = data.raw or ""
  local root = {
    node_type = "Query Plan",
    plans = {},
    warnings = {},
    total_cost = 0,
    rows = 0,
  }

  -- === 1. Parse STATISTICS TIME: elapsed time ===
  local cpu_time = raw:match("CPU time = (%d+) ms")
  local elapsed  = raw:match("elapsed time = (%d+) ms")
  -- Take the LAST occurrence (that's from the actual execution, not SHOWPLAN)
  for cpu, el in raw:gmatch("CPU time = (%d+) ms,%s+elapsed time = (%d+) ms") do
    cpu_time = cpu
    elapsed  = el
  end
  root.execution_time = tonumber(elapsed)
  root.cpu_time       = tonumber(cpu_time)

  -- === 2. Parse STATISTICS IO: logical/physical reads ===
  local io_stats = {}
  for tbl, scan_count, logical, physical in
    raw:gmatch("Table '([^']+)'.-%Scan count (%d+), logical reads (%d+), physical reads (%d+)") do
    table.insert(io_stats, {
      table_name = tbl,
      scan_count = tonumber(scan_count),
      logical_reads = tonumber(logical),
      physical_reads = tonumber(physical),
    })
  end
  root.io_stats = io_stats

  -- === 3. Parse SHOWPLAN_ALL tab-separated rows ===
  -- Columns: StmtText \t StmtId \t NodeId \t Parent \t PhysicalOp \t LogicalOp \t Argument \t
  --          DefinedValues \t EstimateRows \t EstimateIO \t EstimateCPU \t AvgRowSize \t
  --          TotalSubtreeCost \t OutputList \t Warnings \t Type \t Parallel \t EstimateExecutions
  for line in raw:gmatch("[^\r\n]+") do
    local fields = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do
      table.insert(fields, field:match("^%s*(.-)%s*$"))
    end

    -- PLAN_ROW lines have PhysicalOp in field 5 and Type = "PLAN_ROW" in field 16
    if #fields >= 16 and fields[16] == "PLAN_ROW" then
      local phys_op       = fields[5] or ""
      local logical_op    = fields[6] or ""
      local argument      = fields[7] or ""
      local est_rows      = tonumber(fields[9]) or 0
      local est_io        = tonumber(fields[10]) or 0
      local est_cpu       = tonumber(fields[11]) or 0
      local subtree_cost  = tonumber(fields[13]) or 0

      -- Extract table name from argument: [db].[dbo].[tablename].[index] AS [alias]
      local relation = argument:match("%[dbo%]%.%[([%w_]+)%]")

      local node_type = phys_op
      -- Normalize for hints
      if phys_op == "Clustered Index Scan" or phys_op == "Table Scan" then
        node_type = "Seq Scan"
      elseif phys_op == "Clustered Index Seek" then
        node_type = "Index Seek"
      end

      local node = {
        node_type     = node_type,
        physical_op   = phys_op,
        logical_op    = logical_op,
        relation_name = relation,
        total_cost    = subtree_cost,
        est_io        = est_io,
        est_cpu       = est_cpu,
        rows          = est_rows,
        plans         = {},
        warnings      = {},
      }

      table.insert(root.plans, node)

      -- Track highest subtree cost as root cost
      if subtree_cost > root.total_cost then
        root.total_cost = subtree_cost
      end
    end
  end

  -- === 4. Calculate total logical reads ===
  local total_reads = 0
  for _, io in ipairs(io_stats) do
    total_reads = total_reads + io.logical_reads
  end
  root.logical_reads = total_reads

  -- Fallback
  if #root.plans == 0 then
    table.insert(root.plans, {
      node_type = raw:sub(1, 200),
      total_cost = 0,
      rows = 0,
      plans = {},
      warnings = {},
    })
  end

  return root
end

function M.parse(raw_data, db_type)
  if db_type == "postgres" then
    return M.parse_postgres(raw_data)
  elseif db_type == "mysql" then
    return M.parse_mysql(raw_data)
  elseif db_type == "sqlite" then
    return M.parse_sqlite(raw_data)
  elseif db_type == "sqlserver" then
    return M.parse_sqlserver(raw_data)
  else
    return { node_type = "Unknown", plans = {}, warnings = {}, total_cost = 0, rows = 0 }
  end
end

return M
