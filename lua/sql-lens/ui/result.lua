local M = {}

local result_buf = nil
local result_win = nil

---Check if a line is a SQL Server error/warning message
local function is_sql_error(line)
  return line:match("^Msg %d+, Level %d+, State %d+")
      or line:match("^Msg %d+, Niveau %d+")
end

---Parse raw sqlcmd output into structured data
local function parse_output(raw)
  local sections = { headers = {}, rows = {}, stats = {}, affected = nil, errors = {} }
  local lines = {}
  for line in raw:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  local header_line = nil
  local data_started = false
  local in_error = false

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "" then
      in_error = false
      -- skip
    elseif is_sql_error(line) then
      table.insert(sections.errors, trimmed)
      in_error = true
    elseif in_error then
      -- Continuation line after a Msg line (e.g. the actual error detail)
      table.insert(sections.errors, trimmed)
    elseif line:match("SQL Server Execution Times") or line:match("SQL Server parse and compile") then
      -- skip header
    elseif line:match("CPU time = %d+ ms") then
      table.insert(sections.stats, trimmed)
    elseif line:match("^Table '") then
      table.insert(sections.stats, trimmed)
    elseif line:match("^%((%d+) rows? affected%)") then
      sections.affected = trimmed
    elseif line:match("^%-%-") and not data_started then
      -- Separator line => previous line was header
      data_started = true
      if header_line then
        sections.headers = {}
        for col in (header_line .. "\t"):gmatch("([^\t]*)\t") do
          table.insert(sections.headers, col:match("^%s*(.-)%s*$"))
        end
      end
    elseif not data_started and not line:match("Changed database") then
      header_line = line
    elseif data_started and not line:match("^%(") and not line:match("SQL Server")
           and not line:match("CPU time") and not line:match("^Table '") then
      local cols = {}
      for col in (line .. "\t"):gmatch("([^\t]*)\t") do
        table.insert(cols, col:match("^%s*(.-)%s*$"))
      end
      if #cols > 0 then
        table.insert(sections.rows, cols)
      end
    end
  end

  return sections
end

---Calculate column widths
local function calc_widths(headers, rows)
  local widths = {}
  for i, h in ipairs(headers) do
    widths[i] = #h
  end
  for _, row in ipairs(rows) do
    for i, col in ipairs(row) do
      widths[i] = math.max(widths[i] or 0, #col)
    end
  end
  -- Cap max width per column
  for i, w in ipairs(widths) do
    widths[i] = math.min(w, 40)
  end
  return widths
end

---Pad string to width
local function pad(str, width, align_right)
  str = str or ""
  if #str > width then str = str:sub(1, width - 1) .. "…" end
  if align_right then
    return string.rep(" ", width - #str) .. str
  else
    return str .. string.rep(" ", width - #str)
  end
end

---Check if string looks like a number
local function is_number(s)
  return s and s:match("^%-?%d+%.?%d*$") ~= nil
end

---Build a horizontal border line
local function border(widths, left, mid, right, fill)
  local parts = {}
  for _, w in ipairs(widths) do
    table.insert(parts, string.rep(fill, w + 2))
  end
  return left .. table.concat(parts, mid) .. right
end

---Build a data row
local function build_row(cols, widths, sep)
  local parts = {}
  for i, w in ipairs(widths) do
    local val = cols[i] or ""
    local aligned = pad(val, w, is_number(val))
    table.insert(parts, " " .. aligned .. " ")
  end
  return sep .. table.concat(parts, sep) .. sep
end

---Check if raw output is already a formatted table (mysql -t produces bordered tables)
local function is_preformatted(raw)
  return raw:match("^[%s]*[+|%-]") ~= nil
end

---Format pre-formatted output (mysql -t produces bordered tables)
local function format_preformatted(raw, sql)
  local output = {}

  table.insert(output, "")
  table.insert(output, "  ╔══ SqlLens Result ══╗")
  table.insert(output, "")

  local sql_display = sql:gsub("\n", " "):gsub("%s+", " ")
  if #sql_display > 90 then
    sql_display = sql_display:sub(1, 87) .. "..."
  end
  table.insert(output, "  SQL: " .. sql_display)
  table.insert(output, "")

  for line in raw:gmatch("[^\r\n]+") do
    if line:match("^ERROR") then
      table.insert(output, "  ❌ " .. line)
    elseif line:match("^(%d+) rows? in set") or line:match("^Query OK") then
      table.insert(output, "")
      table.insert(output, "  " .. line)
    else
      table.insert(output, "  " .. line)
    end
  end

  table.insert(output, "")
  return output
end

---Check if output is tab-separated (psql -A, mysql --silent)
local function is_tsv(raw)
  local first = raw:match("^([^\r\n]+)")
  return first and first:find("\t") ~= nil
end

---Check if line is a result set footer/status
local function is_footer(line)
  return line:match("^%((%d+) rows?%)")
      or line:match("^(%d+) rows? in set")
      or line:match("^Query OK")
      or line:match("^INSERT %d+")
      or line:match("^UPDATE %d+")
      or line:match("^DELETE %d+")
      or line:match("^CREATE ")
      or line:match("^DROP ")
      or line:match("^ALTER ")
end

---Split a tsv line into columns
local function split_tsv_line(line)
  local cols = {}
  for col in (line .. "\t"):gmatch("([^\t]*)\t") do
    table.insert(cols, col)
  end
  return cols
end

---Parse tab-separated output into multiple result sets
local function parse_tsv_multi(raw)
  local lines = {}
  for line in raw:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  local result_sets = {}
  local cur = { headers = {}, rows = {}, footer = nil }
  local need_header = true

  for _, line in ipairs(lines) do
    if is_footer(line) then
      cur.footer = line
      table.insert(result_sets, cur)
      cur = { headers = {}, rows = {}, footer = nil }
      need_header = true
    elseif need_header then
      cur.headers = split_tsv_line(line)
      need_header = false
    else
      local cols = split_tsv_line(line)
      if #cols > 0 then
        table.insert(cur.rows, cols)
      end
    end
  end

  -- Remaining (no footer, e.g. DDL)
  if #cur.headers > 0 or #cur.rows > 0 then
    table.insert(result_sets, cur)
  end

  return result_sets
end

---Render a single result set as a bordered table
local function render_one_result(output, rs)
  if #rs.headers == 0 and #rs.rows == 0 then
    if rs.footer then
      table.insert(output, "  " .. rs.footer)
    else
      table.insert(output, "  (No result set)")
    end
    return
  end

  local widths = calc_widths(rs.headers, rs.rows)
  local top    = "  " .. border(widths, "┌", "┬", "┐", "─")
  local hdrsep = "  " .. border(widths, "├", "┼", "┤", "─")
  local bottom = "  " .. border(widths, "└", "┴", "┘", "─")

  table.insert(output, top)
  table.insert(output, "  " .. build_row(rs.headers, widths, "│"))
  table.insert(output, hdrsep)

  for _, row in ipairs(rs.rows) do
    table.insert(output, "  " .. build_row(row, widths, "│"))
  end

  table.insert(output, bottom)

  if rs.footer then
    table.insert(output, "  " .. rs.footer)
  end
end

---Format tab-separated output as bordered tables (supports multiple result sets)
local function format_tsv(raw, sql)
  local output = {}
  local result_sets = parse_tsv_multi(raw)

  table.insert(output, "")
  table.insert(output, "  ╔══ SqlLens Result ══╗")
  table.insert(output, "")

  local sql_display = sql:gsub("\n", " "):gsub("%s+", " ")
  if #sql_display > 90 then
    sql_display = sql_display:sub(1, 87) .. "..."
  end
  table.insert(output, "  SQL: " .. sql_display)
  table.insert(output, "")

  if #result_sets == 0 then
    table.insert(output, "  (No result set)")
  else
    for i, rs in ipairs(result_sets) do
      if i > 1 then
        table.insert(output, "")
      end
      render_one_result(output, rs)
    end
  end

  table.insert(output, "")
  return output
end

---Format result as a nice bordered table
local function format_result(raw, sql)
  if is_tsv(raw) then
    return format_tsv(raw, sql)
  end

  if is_preformatted(raw) then
    return format_preformatted(raw, sql)
  end

  local output = {}
  local sections = parse_output(raw)

  -- Title
  table.insert(output, "")
  table.insert(output, "  ╔══ SqlLens Result ══╗")
  table.insert(output, "")

  -- SQL query (truncated)
  local sql_display = sql:gsub("\n", " "):gsub("%s+", " ")
  if #sql_display > 90 then
    sql_display = sql_display:sub(1, 87) .. "..."
  end
  table.insert(output, "  SQL: " .. sql_display)
  table.insert(output, "")

  -- SQL Server errors embedded in output (exit code 0)
  if #sections.errors > 0 then
    table.insert(output, "  ── Errors ──")
    for _, e in ipairs(sections.errors) do
      table.insert(output, "  ❌ " .. e)
    end
    table.insert(output, "")
  end

  if #sections.headers == 0 and #sections.rows == 0 and #sections.errors == 0 then
    table.insert(output, "  (No result set)")
  elseif #sections.headers == 0 and #sections.rows == 0 then
    -- errors already shown above, skip "No result set"
  else
    local widths = calc_widths(sections.headers, sections.rows)

    -- Table borders
    local top    = "  " .. border(widths, "┌", "┬", "┐", "─")
    local hdrsep = "  " .. border(widths, "├", "┼", "┤", "─")
    local bottom = "  " .. border(widths, "└", "┴", "┘", "─")

    -- Header
    table.insert(output, top)
    table.insert(output, "  " .. build_row(sections.headers, widths, "│"))
    table.insert(output, hdrsep)

    -- Data rows
    for _, row in ipairs(sections.rows) do
      table.insert(output, "  " .. build_row(row, widths, "│"))
    end

    table.insert(output, bottom)
  end

  -- Row count
  if sections.affected then
    table.insert(output, "")
    table.insert(output, "  " .. sections.affected)
  end

  -- Stats
  if #sections.stats > 0 then
    table.insert(output, "")
    table.insert(output, "  ── Performance ──")
    for _, s in ipairs(sections.stats) do
      -- Simplify IO stats
      local tbl, scans, logical, physical = s:match(
        "Table '([^']+)'.- Scan count (%d+), logical reads (%d+), physical reads (%d+)"
      )
      if tbl then
        table.insert(output, string.format(
          "  📊 Table '%s': scans=%s  logical_reads=%s  physical_reads=%s",
          tbl, scans, logical, physical
        ))
      elseif s:match("CPU time") then
        table.insert(output, "  ⏱  " .. s)
      end
    end
  end

  table.insert(output, "")
  return output
end

---Check if output looks like sqlcmd format (has --- separator or SQL Server markers)
local function is_sqlcmd(raw)
  return raw:match("\n%-%-") ~= nil
      or raw:match("SQL Server Execution Times")
      or raw:match("rows? affected%)")
end

---Render parsed sqlcmd sections into output
local function render_sqlcmd_result(output, sections)
  if #sections.errors > 0 then
    for _, e in ipairs(sections.errors) do
      table.insert(output, "  ❌ " .. e)
    end
  end

  if #sections.headers > 0 then
    local widths = calc_widths(sections.headers, sections.rows)
    local top    = "  " .. border(widths, "┌", "┬", "┐", "─")
    local hdrsep = "  " .. border(widths, "├", "┼", "┤", "─")
    local bottom = "  " .. border(widths, "└", "┴", "┘", "─")

    table.insert(output, top)
    table.insert(output, "  " .. build_row(sections.headers, widths, "│"))
    table.insert(output, hdrsep)
    for _, row in ipairs(sections.rows) do
      table.insert(output, "  " .. build_row(row, widths, "│"))
    end
    table.insert(output, bottom)
  end

  if sections.affected then
    table.insert(output, "  " .. sections.affected)
  end

  if #sections.stats > 0 then
    for _, s in ipairs(sections.stats) do
      local tbl, scans, logical, physical = s:match(
        "Table '([^']+)'.- Scan count (%d+), logical reads (%d+), physical reads (%d+)"
      )
      if tbl then
        table.insert(output, string.format(
          "  📊 Table '%s': scans=%s  logical=%s  physical=%s",
          tbl, scans, logical, physical
        ))
      elseif s:match("CPU time") then
        table.insert(output, "  ⏱  " .. s)
      end
    end
  end

  if #sections.headers == 0 and #sections.rows == 0 and #sections.errors == 0 and not sections.affected then
    table.insert(output, "  (OK)")
  end
end

---Format multiple labeled results into output lines
local function format_multi_results(results)
  local output = {}

  table.insert(output, "")
  table.insert(output, string.format("  ╔══ SqlLens Result (%d queries) ══╗", #results))

  for i, r in ipairs(results) do
    table.insert(output, "")
    table.insert(output, string.format("  ── Query %d ──", i))

    local sql_display = r.sql:gsub("\n", " "):gsub("%s+", " ")
    if #sql_display > 90 then
      sql_display = sql_display:sub(1, 87) .. "..."
    end
    table.insert(output, "  SQL: " .. sql_display)
    table.insert(output, "")

    if r.err then
      table.insert(output, "  ❌ " .. tostring(r.err))
    elseif r.output == "" then
      table.insert(output, "  (OK)")
    elseif is_sqlcmd(r.output) then
      local sections = parse_output(r.output)
      render_sqlcmd_result(output, sections)
    elseif is_tsv(r.output) then
      local result_sets = parse_tsv_multi(r.output)
      for _, rs in ipairs(result_sets) do
        render_one_result(output, rs)
      end
    elseif is_preformatted(r.output) then
      for line in r.output:gmatch("[^\r\n]+") do
        table.insert(output, "  " .. line)
      end
    else
      for line in r.output:gmatch("[^\r\n]+") do
        table.insert(output, "  " .. line)
      end
    end
  end

  table.insert(output, "")
  return output
end

---Show multiple query results in result window
function M.show_multi(results)
  if result_buf and vim.api.nvim_buf_is_valid(result_buf) then
    -- reuse
  else
    result_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[result_buf].buftype   = "nofile"
    vim.bo[result_buf].bufhidden = "hide"
    vim.bo[result_buf].swapfile  = false
    vim.api.nvim_buf_set_name(result_buf, "[SqlLens Result]")
  end

  local lines = format_multi_results(results)

  vim.bo[result_buf].modifiable = true
  vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, lines)
  vim.bo[result_buf].modifiable = false

  if result_win and vim.api.nvim_win_is_valid(result_win) then
    vim.api.nvim_set_current_win(result_win)
    vim.api.nvim_win_set_buf(result_win, result_buf)
  else
    local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.45))
    vim.cmd("botright " .. height .. "split")
    result_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(result_win, result_buf)
  end

  vim.wo[result_win].number = false
  vim.wo[result_win].relativenumber = false
  vim.wo[result_win].signcolumn = "no"
  vim.wo[result_win].winfixheight = true
  vim.wo[result_win].cursorline = true
  vim.wo[result_win].wrap = false

  M._highlight(result_buf, lines)

  local opts = { buffer = result_buf, nowait = true }
  vim.keymap.set("n", "q", function()
    if result_win and vim.api.nvim_win_is_valid(result_win) then
      vim.api.nvim_win_close(result_win, true)
      result_win = nil
    end
  end, opts)
  vim.keymap.set("n", "<Left>",  function() vim.cmd("normal! zh") end, opts)
  vim.keymap.set("n", "<Right>", function() vim.cmd("normal! zl") end, opts)
  vim.keymap.set("n", "H", function() vim.cmd("normal! zH") end, opts)
  vim.keymap.set("n", "L", function() vim.cmd("normal! zL") end, opts)
end

---Show result in a bottom split window
function M.show(raw, sql)
  if result_buf and vim.api.nvim_buf_is_valid(result_buf) then
    -- reuse
  else
    result_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[result_buf].buftype   = "nofile"
    vim.bo[result_buf].bufhidden = "hide"
    vim.bo[result_buf].swapfile  = false
    vim.api.nvim_buf_set_name(result_buf, "[SqlLens Result]")
  end

  local lines = format_result(raw, sql)

  vim.bo[result_buf].modifiable = true
  vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, lines)
  vim.bo[result_buf].modifiable = false

  -- Open or focus the result window (bottom split)
  if result_win and vim.api.nvim_win_is_valid(result_win) then
    vim.api.nvim_set_current_win(result_win)
    vim.api.nvim_win_set_buf(result_win, result_buf)
  else
    local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.45))
    vim.cmd("botright " .. height .. "split")
    result_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(result_win, result_buf)
  end

  vim.wo[result_win].number = false
  vim.wo[result_win].relativenumber = false
  vim.wo[result_win].signcolumn = "no"
  vim.wo[result_win].winfixheight = true
  vim.wo[result_win].cursorline = true
  vim.wo[result_win].wrap = false

  -- Apply highlights
  M._highlight(result_buf, lines)

  -- Keymaps
  local opts = { buffer = result_buf, nowait = true }
  vim.keymap.set("n", "q", function()
    if result_win and vim.api.nvim_win_is_valid(result_win) then
      vim.api.nvim_win_close(result_win, true)
      result_win = nil
    end
  end, opts)
  vim.keymap.set("n", "<Left>", function()
    vim.cmd("normal! zh")
  end, opts)
  vim.keymap.set("n", "<Right>", function()
    vim.cmd("normal! zl")
  end, opts)
  vim.keymap.set("n", "H", function()
    vim.cmd("normal! zH")
  end, opts)
  vim.keymap.set("n", "L", function()
    vim.cmd("normal! zL")
  end, opts)
end

---Apply highlight to result buffer
function M._highlight(bufnr, lines)
  local ns = vim.api.nvim_create_namespace("sql_lens_result")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("╔══") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("^%s*SQL:") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensDim", row, 0, -1)
    elseif line:match("^%s*┌") or line:match("^%s*├") or line:match("^%s*└") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensDim", row, 0, -1)
    elseif line:match("^%s*│") and not line:match("──") then
      -- Header row (first │ row after ┌)
      local is_header = false
      if i >= 3 then
        local prev = lines[i - 1]
        if prev and prev:match("^%s*┌") then
          is_header = true
        end
      end
      if is_header then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensWarn", row, 0, -1)
      end
    elseif line:match("── Query %d+") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("── Errors") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensError", row, 0, -1)
    elseif line:match("❌") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensError", row, 0, -1)
    elseif line:match("── Performance") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensInfo", row, 0, -1)
    elseif line:match("📊") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("⏱") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensOk", row, 0, -1)
    elseif line:match("rows? affected") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "SqlLensDim", row, 0, -1)
    end
  end
end

---Show error in result window
function M.show_error(err, sql)
  local lines = {
    "",
    "  ╔══ SqlLens Error ══╗",
    "",
  }

  local sql_display = (sql or ""):gsub("\n", " "):gsub("%s+", " ")
  if #sql_display > 80 then
    sql_display = sql_display:sub(1, 77) .. "..."
  end
  table.insert(lines, "  SQL: " .. sql_display)
  table.insert(lines, "")

  local err_str = tostring(err or "Unknown error"):gsub("\r", "")
  local added = false
  for line in err_str:gmatch("[^\n]+") do
    table.insert(lines, "  ❌ " .. line)
    added = true
  end
  if not added then
    table.insert(lines, "  ❌ (no details)")
  end
  table.insert(lines, "")

  if result_buf and vim.api.nvim_buf_is_valid(result_buf) then
    -- reuse
  else
    result_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[result_buf].buftype   = "nofile"
    vim.bo[result_buf].bufhidden = "hide"
    vim.bo[result_buf].swapfile  = false
  end

  vim.bo[result_buf].modifiable = true
  vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, lines)
  vim.bo[result_buf].modifiable = false

  if result_win and vim.api.nvim_win_is_valid(result_win) then
    vim.api.nvim_set_current_win(result_win)
  else
    vim.cmd("botright 10split")
    result_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(result_win, result_buf)
  end

  local ns = vim.api.nvim_create_namespace("sql_lens_result")
  vim.api.nvim_buf_clear_namespace(result_buf, ns, 0, -1)
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("SqlLens Error") or line:match("❌") then
      vim.api.nvim_buf_add_highlight(result_buf, ns, "SqlLensError", row, 0, -1)
    elseif line:match("^%s*SQL:") then
      vim.api.nvim_buf_add_highlight(result_buf, ns, "SqlLensDim", row, 0, -1)
    end
  end
end

function M.close()
  if result_win and vim.api.nvim_win_is_valid(result_win) then
    vim.api.nvim_win_close(result_win, true)
    result_win = nil
  end
end

return M
