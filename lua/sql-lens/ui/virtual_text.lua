local M = {}

local NS = vim.api.nvim_create_namespace("sql_lens")

local HL = {
  info  = "SqlLensInfo",
  warn  = "SqlLensWarn",
  error = "SqlLensError",
  ok    = "SqlLensOk",
  dim   = "SqlLensDim",
}

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

return M
