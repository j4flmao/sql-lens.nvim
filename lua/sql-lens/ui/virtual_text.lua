local M = {}

local NS = vim.api.nvim_create_namespace("sql_lens")

local HL = {
  info  = "SqlLensInfo",
  warn  = "SqlLensWarn",
  error = "SqlLensError",
  ok    = "SqlLensOk",
  dim   = "SqlLensDim",
}

local MSSQL_KEYWORDS = {
  "select", "from", "where", "group", "by", "order", "having",
  "join", "inner", "left", "right", "full", "cross", "on",
  "union", "all", "insert", "into", "values", "update", "set",
  "delete", "create", "alter", "drop", "with", "as", "top",
}

local MSSQL_FUNCTIONS = {
  "getdate", "getutcdate", "sysdatetime", "sysutcdatetime",
  "current_timestamp",
  "dateadd", "datediff", "datediff_big", "datename", "datepart", "eomonth",
  "datefromparts", "datetime2fromparts", "datetimefromparts", "timefromparts",
  "switchoffset", "todatetimeoffset",
  "cast", "convert", "try_cast", "try_convert",
  "isnull", "nullif", "coalesce",
  "iif", "choose",
  "count", "sum", "avg", "min", "max",
  "row_number", "rank", "dense_rank", "ntile",
  "lag", "lead", "first_value", "last_value",
  "len", "upper", "lower",
}

local function levenshtein(a, b)
  local la, lb = #a, #b
  if la == 0 then return lb end
  if lb == 0 then return la end
  local prev = {}
  local curr = {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    curr[0] = i
    local ca = a:sub(i, i)
    for j = 1, lb do
      local cb = b:sub(j, j)
      local cost = (ca == cb) and 0 or 1
      curr[j] = math.min(
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost
      )
    end
    prev, curr = curr, prev
  end
  return prev[lb]
end

local function suggest_token(token, err)
  local t = token:lower()
  local e = (err or ""):lower()
  local candidates = MSSQL_KEYWORDS
  if e:find("built%-in function") then
    candidates = MSSQL_FUNCTIONS
  end
  local best, bestd
  for _, c in ipairs(candidates) do
    local d = levenshtein(t, c)
    if not bestd or d < bestd then
      bestd = d
      best = c
    end
  end
  if best and bestd and bestd <= 3 then
    return best
  end
end

function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

---Render summary line at end of the SQL statement's last line
function M.render_summary(bufnr, line, summary, level)
  local hl = HL[level] or HL.info
  local prefix = level == "error" and "󰀪 "
              or level == "warn"  and "󰀦 "
              or "󰋼 "

  vim.api.nvim_buf_set_extmark(bufnr, NS, line, 0, {
    virt_text = {
      { "  " .. prefix .. summary, hl },
    },
    virt_text_pos = "eol",
    priority      = 100,
  })
end

---Render hints as virtual lines below
function M.render_hints(bufnr, line, hints)
  local show = vim.list_slice(hints, 1, 3)

  local virt_lines = {}
  for _, hint in ipairs(show) do
    local hl = HL[hint.level] or HL.info
    table.insert(virt_lines, {
      { "    " .. hint.icon .. " " .. hint.message, hl }
    })
  end

  if #hints > 3 then
    table.insert(virt_lines, {
      { string.format("    ... and %d more (use :SqlLensFloatDetail)", #hints - 3), HL.dim }
    })
  end

  vim.api.nvim_buf_set_extmark(bufnr, NS, line, 0, {
    virt_lines       = virt_lines,
    virt_lines_above = false,
  })
end

---Render lint errors inline (offline lint)
function M.render_lint_errors(bufnr, lint_errors)
  for _, e in ipairs(lint_errors) do
    local hl = HL[e.level] or HL.error
    local icon = e.level == "error" and "✗" or "⚠"

    -- Underline the offending token if we have col info
    if e.token and e.col then
      local line_text = vim.api.nvim_buf_get_lines(bufnr, e.line, e.line + 1, false)[1] or ""
      local s, en = line_text:lower():find(e.token:lower(), e.col + 1, true)
      if s then
        vim.api.nvim_buf_set_extmark(bufnr, NS, e.line, s - 1, {
          end_col  = en,
          hl_group = "SqlLensErrorToken",
          priority = 120,
        })
      end
    end

    -- Virtual text at end of line
    vim.api.nvim_buf_set_extmark(bufnr, NS, e.line, 0, {
      virt_text = {
        { "  " .. icon .. " " .. e.message, hl },
      },
      virt_text_pos = "eol",
      priority      = 110,
    })
  end
end

function M.highlight_error_token(bufnr, start_line, sql, err)
  if not sql or not err then
    return
  end
  local token = err:match("near%s+'([^']+)'")
  if not token or token == "" then
    token = err:match("name%s+'([^']+)'")
  end
  if not token or token == "" then
    token = err:match("'([^']+)' is not a recognized")
  end
  if not token or token == "" then
    return
  end
  local lines = vim.split(sql, "\n", { plain = true })
  local token_l = token:lower()
  for i, line in ipairs(lines) do
    local s, e = line:lower():find(token_l, 1, true)
    if s then
      local row = (start_line or 0) + (i - 1)
      vim.api.nvim_buf_set_extmark(bufnr, NS, row, s - 1, {
        end_col = e,
        hl_group = "SqlLensErrorToken",
        priority = 120,
      })
      local err_l = (err or ""):lower()
      local suggestion = suggest_token(token, err)
      local msg
      if err_l:find("built%-in function") then
        if suggestion then
          msg = string.format("Unknown function '%s'. Did you mean '%s()'?", token, suggestion)
        else
          msg = string.format("Unknown function '%s'. Check function name.", token)
        end
      elseif err_l:find("invalid column name") then
        msg = string.format("Invalid column name '%s'. Check spelling or aliases.", token)
      else
        if suggestion then
          msg = string.format("Unexpected token '%s'. Did you mean '%s'?", token, suggestion)
        else
          msg = string.format("Check token '%s' near this position.", token)
        end
      end
      M.render_hints(bufnr, row, {
        { level = "error", icon = "󰋗", message = msg },
      })
      break
    end
  end
end

return M
