local M = {}

local function pad_right(s, width)
  local w = vim.fn.strdisplaywidth(s)
  if w >= width then
    return s
  end
  return s .. string.rep(" ", width - w)
end

local function make_scratch_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "sqllens"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  return buf
end

local function apply_hls(buf, hls)
  for _, hl in ipairs(hls or {}) do
    vim.api.nvim_buf_add_highlight(buf, -1, hl.group, hl.line, hl.col_start, hl.col_end)
  end
end

local function to_chars(s)
  return vim.fn.split(s, "\\zs")
end

local function from_chars(chars)
  return table.concat(chars, "")
end

local function ensure_width(chars, width)
  while #chars < width do
    chars[#chars + 1] = " "
  end
end

local function merge_char(old, new)
  if old == nil or old == " " then
    return new
  end
  if old == new then
    return old
  end
  if (old == "─" and new == "│") or (old == "│" and new == "─") then
    return "┼"
  end
  if old == "┼" then
    return old
  end
  if old == "┤" and (new == "─" or new == "┼") then
    return old
  end
  if new == "┤" and (old == "─" or old == "┼") then
    return "┤"
  end
  return new
end

local function put(canvas, x, y, ch)
  if not canvas[y] then return end
  if x < 1 then return end
  ensure_width(canvas[y], x)
  canvas[y][x] = merge_char(canvas[y][x], ch)
end

local function draw_h(canvas, x1, x2, y, ch)
  if x2 < x1 then
    x1, x2 = x2, x1
  end
  for x = x1, x2 do
    put(canvas, x, y, ch)
  end
end

local function draw_v(canvas, x, y1, y2, ch)
  if y2 < y1 then
    y1, y2 = y2, y1
  end
  for y = y1, y2 do
    put(canvas, x, y, ch)
  end
end

local function add_connectors(lines, box_w, table_anchor, edges)
  local track_intervals = {}
  local assigned = {}

  local function overlaps(a1, a2, b1, b2)
    return not (a2 < b1 or b2 < a1)
  end

  for i, e in ipairs(edges) do
    local y1 = e.from_y
    local y2 = table_anchor[e.to_table]
    if y1 and y2 and y1 ~= y2 then
      local lo = math.min(y1, y2)
      local hi = math.max(y1, y2)
      local t = 1
      while true do
        track_intervals[t] = track_intervals[t] or {}
        local ok = true
        for _, iv in ipairs(track_intervals[t]) do
          if overlaps(lo, hi, iv[1], iv[2]) then
            ok = false
            break
          end
        end
        if ok then
          table.insert(track_intervals[t], { lo, hi })
          assigned[i] = { track = t, to_y = y2 }
          break
        end
        t = t + 1
      end
    end
  end

  local track_count = #track_intervals
  local gutter_w = math.max(8, track_count * 2 + 4)

  local canvas = {}
  for _, line in ipairs(lines) do
    local chars = to_chars(line)
    ensure_width(chars, box_w + gutter_w)
    canvas[#canvas + 1] = chars
  end

  local x0 = box_w + 2
  for i, e in ipairs(edges) do
    local a = assigned[i]
    if a then
      local y1 = e.from_y
      local y2 = a.to_y
      local track_x = x0 + (a.track - 1) * 2

      put(canvas, x0, y1, "┤")
      put(canvas, x0, y2, "┤")

      if track_x > x0 + 1 then
        draw_h(canvas, x0 + 1, track_x - 1, y1, "─")
        draw_h(canvas, x0 + 1, track_x - 1, y2, "─")
      end

      put(canvas, track_x, y1, "┼")
      put(canvas, track_x, y2, "┼")
      local lc = e.left_char or "N"
      local rc = e.right_char or "1"
      put(canvas, track_x + 1, y1, lc)
      put(canvas, track_x + 1, y2, rc)

      if math.abs(y2 - y1) > 1 then
        draw_v(canvas, track_x, y1 + 1, y2 - 1, "│")
      end
    end
  end

  local out = {}
  for _, row in ipairs(canvas) do
    out[#out + 1] = from_chars(row)
  end
  return out
end

local function open_tui_split(title, left, left_hls, right, right_hls)
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  local left_buf = make_scratch_buf(left)
  vim.api.nvim_win_set_buf(0, left_buf)

  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  local right_buf = make_scratch_buf(right)
  vim.api.nvim_win_set_buf(right_win, right_buf)

  local w = vim.o.columns
  local left_w = math.floor(w * 0.65)
  if left_w < 70 then left_w = math.floor(w * 0.55) end
  if left_w < 60 then left_w = math.floor(w * 0.5) end
  if left_w > w - 30 then left_w = w - 30 end
  vim.api.nvim_win_set_width(vim.api.nvim_list_wins()[1], left_w)

  apply_hls(left_buf, left_hls)
  apply_hls(right_buf, right_hls)

  local function close()
    if vim.api.nvim_tabpage_is_valid(tab) then
      vim.cmd("tabclose")
    end
  end

  local function copy_all()
    local text = table.concat(left, "\n") .. "\n\n" .. table.concat(right, "\n")
    vim.fn.setreg("+", text)
    vim.notify("SqlLens: Copied diagram to clipboard", vim.log.levels.INFO)
  end

  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.keymap.set("n", "q", close, { buffer = buf })
    vim.keymap.set("n", "<Esc>", close, { buffer = buf })
    vim.keymap.set("n", "y", copy_all, { buffer = buf })
    vim.keymap.set("n", "gg", "gg", { buffer = buf, remap = true })
    vim.keymap.set("n", "G", "G", { buffer = buf, remap = true })
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    vim.api.nvim_set_option_value("wrap", false, { win = win })
    vim.api.nvim_set_option_value("cursorline", true, { win = win })
  end

  vim.api.nvim_set_option_value("winhl", "Normal:SqlLensBg", { win = vim.api.nvim_tabpage_list_wins(tab)[1] })
  vim.api.nvim_set_option_value("winhl", "Normal:SqlLensBg", { win = right_win })
end

---Fetch schema info and generate ER diagram
function M.generate()
  local conn_mgr = require("sql-lens.connections")
  local bufnr = vim.api.nvim_get_current_buf()
  local conn = conn_mgr.get_active(bufnr)
  if not conn then
    vim.notify("SqlLens: No active connection", vim.log.levels.WARN)
    return
  end

  vim.notify("SqlLens: Building ER diagram...", vim.log.levels.INFO)

  conn:list_tables(function(err, tables)
    if err or #tables == 0 then
      vim.notify("SqlLens: No tables found", vim.log.levels.WARN)
      return
    end

    -- Fetch columns for all tables
    local table_cols = {}
    local done_cols = 0
    local total = #tables

    for _, tbl in ipairs(tables) do
      conn:list_columns(tbl, function(_, cols)
        table_cols[tbl] = cols or {}
        done_cols = done_cols + 1
        if done_cols == total then
          local function with_fks(fks)
            local function with_unique_and_null(uniq)
              if conn.list_nullability then
                conn:list_nullability(function(_, nulmap)
                  M._build(tables, table_cols, fks or {}, conn, uniq or nil, nulmap or nil)
                end)
              else
                M._build(tables, table_cols, fks or {}, conn, uniq or nil, nil)
              end
            end
            if conn.list_unique_info then
              conn:list_unique_info(function(_, uniq) with_unique_and_null(uniq) end)
            else
              with_unique_and_null(nil)
            end
          end
          if conn.list_foreign_keys then
            conn:list_foreign_keys(function(_, fks) with_fks(fks) end)
          else
            with_fks({})
          end
        end
      end)
    end
  end)
end

function M._build(tables, table_cols, fks, conn, unique_info, nullability)
  local fk_set = {}
  for _, fk in ipairs(fks) do
    fk_set[fk.from_table .. "." .. fk.from_column] = fk.to_table .. "." .. fk.to_column
  end

  local function parse_col(col_info)
    local name = col_info:match("^(%S+)")
    if not name then return nil, "" end
    local rest = col_info:match("%s+(.+)$") or ""
    return name, rest
  end

  local db_name = (conn.config.dbname or conn.config.name or "database")

  local unique_single = (unique_info and unique_info.unique_single) or {}
  local unique_pairs = {}
  if unique_info and unique_info.unique_composites then
    for tbl, lists in pairs(unique_info.unique_composites) do
      unique_pairs[tbl] = {}
      for _, cols in ipairs(lists) do
        local copy = vim.deepcopy(cols)
        table.sort(copy)
        table.insert(unique_pairs[tbl], table.concat(copy, ","))
      end
    end
  end

  local left = {}
  local left_hls = {}
  local table_anchor = {}
  local edges = {}

  local function push_line(s)
    table.insert(left, s)
    return #left - 1
  end

  local function build_table_block(tbl, cols)
    local rows = {}
    local name_w, type_w, tag_w = 6, 4, 4
    for _, col_info in ipairs(cols) do
      local col_name, col_type = parse_col(col_info)
      if col_name and col_name ~= "" then
        local tag = ""
        if col_name:lower() == "id" then
          tag = "PK"
        end
        local fk_target = fk_set[tbl .. "." .. col_name]
        if fk_target then
          if tag ~= "" then
            tag = tag .. ", FK→" .. fk_target
          else
            tag = "FK→" .. fk_target
          end
        end
        name_w = math.max(name_w, vim.fn.strdisplaywidth(col_name))
        type_w = math.max(type_w, vim.fn.strdisplaywidth(col_type))
        tag_w = math.max(tag_w, vim.fn.strdisplaywidth(tag))
        table.insert(rows, { name = col_name, type = col_type, tag = tag, fk_target = fk_target })
      end
    end

    if #rows == 0 then
      name_w = math.max(name_w, vim.fn.strdisplaywidth("(no columns)"))
      type_w = math.max(type_w, 0)
      tag_w = math.max(tag_w, 0)
    end

    local inner_w = 2 + name_w + 3 + type_w + 3 + tag_w + 2
    local top = "┌" .. string.rep("─", inner_w - 2) .. "┐"
    local bottom = "└" .. string.rep("─", inner_w - 2) .. "┘"
    local sep = "├" .. string.rep("─", inner_w - 2) .. "┤"

    push_line(top)
    local title = "│ " .. pad_right(tbl, inner_w - 4) .. " │"
    local title_line = push_line(title)
    table.insert(left_hls, { group = "SqlLensInfo", line = title_line, col_start = 2, col_end = 2 + #tbl })
    table_anchor[tbl] = title_line + 1

    push_line(sep)
    push_line("│ " .. pad_right("Column", name_w) .. " │ " .. pad_right("Type", type_w) .. " │ " .. pad_right("Tags", tag_w) .. " │")
    push_line(sep)

    if #rows == 0 then
      push_line("│ " .. pad_right("(no columns)", name_w) .. " │ " .. pad_right("", type_w) .. " │ " .. pad_right("", tag_w) .. " │")
    else
      for _, r in ipairs(rows) do
        local line = "│ "
          .. pad_right(r.name, name_w)
          .. " │ "
          .. pad_right(r.type, type_w)
          .. " │ "
          .. pad_right(r.tag, tag_w)
          .. " │"
        local lno = push_line(line)

        if r.tag ~= "" then
          local pk_s, pk_e = line:find("PK", 1, true)
          if pk_s and pk_e then
            table.insert(left_hls, { group = "SqlLensWarn", line = lno, col_start = pk_s - 1, col_end = pk_e })
          end
          local fk_s, fk_e = line:find("FK→", 1, true)
          if fk_s and fk_e then
            table.insert(left_hls, { group = "SqlLensErrorToken", line = lno, col_start = fk_s - 1, col_end = fk_e })
            table.insert(left_hls, { group = "SqlLensDim", line = lno, col_start = fk_e, col_end = #line })
            if r.fk_target then
              local to_tbl = r.fk_target:match("^([^%.]+)%.") or r.fk_target
              -- Determine cardinality label at source side
              local is_unique = unique_single[tbl] and unique_single[tbl][r.name or ""] or false
              local is_nullable = false
              if nullability and nullability[tbl] and r.name then
                is_nullable = nullability[tbl][r.name] and true or false
              end
              local left_char = is_unique and "1" or "N"
              table.insert(edges, { from_y = lno + 1, to_table = to_tbl, left_char = left_char, right_char = "1", from_table = tbl, from_col = r.name or "" })
            end
          end
        end
      end
    end

    push_line(bottom)
    push_line("")
  end

  push_line("SqlLens ER — " .. db_name)
  table.insert(left_hls, { group = "SqlLensOk", line = 0, col_start = 0, col_end = -1 })
  push_line("")

  for _, tbl in ipairs(tables) do
    build_table_block(tbl, table_cols[tbl] or {})
  end

  local box_w = 0
  for _, l in ipairs(left) do
    box_w = math.max(box_w, vim.fn.strdisplaywidth(l))
  end
  for i, l in ipairs(left) do
    left[i] = pad_right(l, box_w)
  end
  left = add_connectors(left, box_w, table_anchor, edges)

  local right = {}
  local right_hls = {}

  local function push_right(s)
    table.insert(right, s)
    return #right - 1
  end

  push_right("Relationships")
  table.insert(right_hls, { group = "SqlLensInfo", line = 0, col_start = 0, col_end = -1 })
  push_right("")
  if #fks == 0 then
    push_right("(no foreign keys found)")
  else
    -- Detect junction (M:N): table with exactly two FKs to different tables and composite unique on those columns
    local by_table = {}
    for _, fk in ipairs(fks) do
      by_table[fk.from_table] = by_table[fk.from_table] or {}
      table.insert(by_table[fk.from_table], fk)
    end
    local printed_mn = {}
    for tbl, list in pairs(by_table) do
      if #list >= 2 and unique_pairs[tbl] and #unique_pairs[tbl] > 0 then
        local cols = {}
        local targets = {}
        for _, fk in ipairs(list) do
          table.insert(cols, fk.from_column)
          targets[fk.to_table] = true
        end
        if vim.tbl_count(targets) >= 2 then
          table.sort(cols)
          local key = table.concat(cols, ",")
          local has = false
          for _, k in ipairs(unique_pairs[tbl]) do
            if k == key then has = true; break end
          end
          if has then
            local tnames = {}
            for tname in pairs(targets) do table.insert(tnames, tname) end
            table.sort(tnames)
            local line = string.format("%s ↔ %s (M:N via %s)", tnames[1], tnames[2], tbl)
            if not printed_mn[line] then
              push_right(line)
              printed_mn[line] = true
            end
          end
        end
      end
    end
    -- Print individual FK lines with detected cardinality
    for _, fk in ipairs(fks) do
      local is_unique = unique_single[fk.from_table] and unique_single[fk.from_table][fk.from_column] or false
      local is_nullable = false
      if nullability and nullability[fk.from_table] and nullability[fk.from_table][fk.from_column] then
        is_nullable = true
      end
      local left_mult
      if is_unique then
        left_mult = is_nullable and "0..1" or "1"
      else
        left_mult = is_nullable and "0..N" or "N"
      end
      local s = string.format("%s.%s -> %s.%s (%s:1)", fk.from_table, fk.from_column, fk.to_table, fk.to_column, left_mult)
      push_right(s)
    end
  end
  push_right("")
  push_right("Keys")
  table.insert(right_hls, { group = "SqlLensInfo", line = #right - 1, col_start = 0, col_end = -1 })
  push_right("  N:1  many-to-one (FK → PK)")
  push_right("  q / <Esc>  close")
  push_right("  y          copy")

  open_tui_split("SqlLens ER", left, left_hls, right, right_hls)
end

return M
