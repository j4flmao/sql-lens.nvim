local M = {}

M._templates = {
  {
    name = "SELECT basic",
    desc = "Simple SELECT with WHERE",
    sql = "SELECT\n  *\nFROM {{table}}\nWHERE {{column}} = {{value}}\nLIMIT 50;",
  },
  {
    name = "INSERT",
    desc = "Insert single row",
    sql = "INSERT INTO {{table}} ({{columns}})\nVALUES ({{values}});",
  },
  {
    name = "UPDATE",
    desc = "Update with WHERE",
    sql = "UPDATE {{table}}\nSET {{column}} = {{value}}\nWHERE {{condition}};",
  },
  {
    name = "DELETE",
    desc = "Delete with WHERE",
    sql = "DELETE FROM {{table}}\nWHERE {{condition}};",
  },
  {
    name = "JOIN",
    desc = "Inner join two tables",
    sql = "SELECT\n  a.*,\n  b.*\nFROM {{table_a}} a\nINNER JOIN {{table_b}} b\n  ON a.{{column}} = b.{{column}}\nLIMIT 50;",
  },
  {
    name = "LEFT JOIN",
    desc = "Left join with NULL check",
    sql = "SELECT\n  a.*,\n  b.*\nFROM {{table_a}} a\nLEFT JOIN {{table_b}} b\n  ON a.{{column}} = b.{{column}}\nWHERE b.id IS NULL;",
  },
  {
    name = "GROUP BY",
    desc = "Aggregate with grouping",
    sql = "SELECT\n  {{column}},\n  COUNT(*) AS count,\n  SUM({{amount}}) AS total\nFROM {{table}}\nGROUP BY {{column}}\nHAVING COUNT(*) > 1\nORDER BY count DESC;",
  },
  {
    name = "Pagination",
    desc = "Paginated results (MySQL/PG)",
    sql = "SELECT *\nFROM {{table}}\nORDER BY {{column}}\nLIMIT {{page_size}}\nOFFSET {{offset}};",
  },
  {
    name = "Pagination (SQL Server)",
    desc = "Paginated results for SQL Server",
    sql = "SELECT *\nFROM {{table}}\nORDER BY {{column}}\nOFFSET {{offset}} ROWS\nFETCH NEXT {{page_size}} ROWS ONLY;",
  },
  {
    name = "CTE",
    desc = "Common Table Expression",
    sql = "WITH cte AS (\n  SELECT\n    {{columns}}\n  FROM {{table}}\n  WHERE {{condition}}\n)\nSELECT * FROM cte;",
  },
  {
    name = "Recursive CTE",
    desc = "Tree/hierarchy traversal",
    sql = "WITH RECURSIVE tree AS (\n  SELECT id, parent_id, name, 0 AS depth\n  FROM {{table}}\n  WHERE parent_id IS NULL\n  UNION ALL\n  SELECT t.id, t.parent_id, t.name, tree.depth + 1\n  FROM {{table}} t\n  INNER JOIN tree ON t.parent_id = tree.id\n)\nSELECT * FROM tree\nORDER BY depth, name;",
  },
  {
    name = "ROW_NUMBER",
    desc = "Window function — row numbering",
    sql = "SELECT\n  *,\n  ROW_NUMBER() OVER (\n    PARTITION BY {{partition_col}}\n    ORDER BY {{order_col}} DESC\n  ) AS rn\nFROM {{table}};",
  },
  {
    name = "Running Total",
    desc = "Window function — cumulative sum",
    sql = "SELECT\n  {{date_col}},\n  {{amount_col}},\n  SUM({{amount_col}}) OVER (\n    ORDER BY {{date_col}}\n  ) AS running_total\nFROM {{table}};",
  },
  {
    name = "UPSERT (PostgreSQL)",
    desc = "Insert or update on conflict",
    sql = "INSERT INTO {{table}} ({{columns}})\nVALUES ({{values}})\nON CONFLICT ({{unique_col}})\nDO UPDATE SET\n  {{column}} = EXCLUDED.{{column}};",
  },
  {
    name = "MERGE (SQL Server)",
    desc = "Upsert with MERGE",
    sql = "MERGE INTO {{target}} AS t\nUSING {{source}} AS s\n  ON t.{{key}} = s.{{key}}\nWHEN MATCHED THEN\n  UPDATE SET t.{{column}} = s.{{column}}\nWHEN NOT MATCHED THEN\n  INSERT ({{columns}})\n  VALUES (s.{{columns}});",
  },
  {
    name = "CREATE TABLE",
    desc = "Create table with constraints",
    sql = "CREATE TABLE {{table_name}} (\n  id INT PRIMARY KEY,\n  {{column1}} VARCHAR(255) NOT NULL,\n  {{column2}} INT DEFAULT 0,\n  created_at DATETIME DEFAULT CURRENT_TIMESTAMP\n);",
  },
  {
    name = "CREATE INDEX",
    desc = "Create an index",
    sql = "CREATE INDEX idx_{{table}}_{{column}}\n  ON {{table}} ({{column}});",
  },
  {
    name = "EXISTS subquery",
    desc = "Correlated subquery with EXISTS",
    sql = "SELECT *\nFROM {{table_a}} a\nWHERE EXISTS (\n  SELECT 1\n  FROM {{table_b}} b\n  WHERE b.{{fk}} = a.id\n    AND b.{{condition}}\n);",
  },
  {
    name = "CASE expression",
    desc = "Conditional column",
    sql = "SELECT\n  {{column}},\n  CASE\n    WHEN {{condition1}} THEN '{{value1}}'\n    WHEN {{condition2}} THEN '{{value2}}'\n    ELSE '{{default}}'\n  END AS {{alias}}\nFROM {{table}};",
  },
}

function M.pick()
  local picker = require("sql-lens.ui.picker")
  local labels = {}
  local details = {}
  for _, t in ipairs(M._templates) do
    table.insert(labels, t.name .. " — " .. t.desc)
    table.insert(details, t.sql)
  end

  picker.open(labels, {
    prompt = "SQL Snippets",
    details = details,
    on_select = function(label)
      for i, l in ipairs(labels) do
        if l == label then
          local template = M._templates[i]
          local bufnr = vim.api.nvim_get_current_buf()
          local row = vim.api.nvim_win_get_cursor(0)[1]
          local slines = vim.split(template.sql, "\n")
          vim.api.nvim_buf_set_lines(bufnr, row, row, false, slines)
          vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
          vim.notify("SqlLens: Inserted '" .. template.name .. "'", vim.log.levels.INFO)
          return
        end
      end
    end,
  })
end

return M
