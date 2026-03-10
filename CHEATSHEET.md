# CHEATSHEET.md — sql-lens.nvim Dev Reference

## Neovim API Hay Dùng Nhất

```lua
-- Buffer
vim.api.nvim_get_current_buf()               -- bufnr hiện tại
vim.api.nvim_buf_get_lines(buf, 0, -1, false) -- lấy toàn bộ lines
vim.api.nvim_buf_set_lines(buf, start, end, strict, lines)

-- Window / Cursor
vim.api.nvim_win_get_cursor(0)    -- {row, col}, row là 1-indexed
vim.api.nvim_open_win(buf, enter, config)  -- tạo float window

-- Virtual Text (Extmarks)
local ns = vim.api.nvim_create_namespace("my_ns")
vim.api.nvim_buf_set_extmark(buf, ns, line, col, {
  virt_text = { {"text", "HighlightGroup"} },
  virt_text_pos = "eol",         -- eol | overlay | right_align
  virt_lines = { {{"line", "HL"}} },  -- extra lines dưới
})
vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

-- Notify
vim.notify("message", vim.log.levels.INFO)   -- INFO WARN ERROR
vim.notify("message", vim.log.levels.WARN)

-- Async Job
vim.fn.jobstart(cmd_table, {
  on_stdout = fn,  on_stderr = fn,  on_exit = fn,
  stdout_buffered = true,
})

-- Schedule (chạy callback trong main loop — bắt buộc sau async)
vim.schedule(function() ... end)

-- Timer (debounce)
local t = vim.loop.new_timer()
t:start(delay_ms, 0, vim.schedule_wrap(callback))
t:stop(); t:close()

-- Autocmd
vim.api.nvim_create_autocmd("TextChangedI", {
  buffer = bufnr,
  group  = vim.api.nvim_create_augroup("MyGroup", {clear=true}),
  callback = fn,
})

-- Keymap
vim.keymap.set("n", "<leader>x", fn, { desc = "Do thing", buffer = bufnr })

-- Highlight Group
vim.api.nvim_set_hl(0, "MyHL", { fg = "#ff0000", bold = true })
```

---

## Treesitter Cheatsheet

```lua
-- Lấy parser cho buffer
local parser = vim.treesitter.get_parser(bufnr, "sql")
local tree   = parser:parse()[1]
local root   = tree:root()

-- Query
local q = vim.treesitter.query.parse("sql", "(statement) @s")
for id, node, meta in q:iter_captures(root, bufnr, 0, -1) do
  local text = vim.treesitter.get_node_text(node, bufnr)
  local sr, sc, er, ec = node:range()  -- 0-indexed
end

-- Node dưới cursor
local node = vim.treesitter.get_node()
```

---

## vim.ui.select — Connection Picker

```lua
vim.ui.select(connections, {
  prompt = "Chọn connection:",
  format_item = function(c) return c.name .. " (" .. c.type .. ")" end,
}, function(choice)
  if choice then conn_mgr.set_active(bufnr, choice) end
end)
```

---

## Plugin Hay Integrate

| Plugin | Tác dụng |
|--------|----------|
| `nvim-treesitter` | Parse SQL statement chính xác |
| `telescope.nvim`  | Picker cho connections |
| `nui.nvim`        | UI đẹp hơn cho floating panels |
| `plenary.nvim`    | Test framework + async utils |
| `which-key.nvim`  | Tự động đăng ký keymaps với mô tả |

---

## Lazy.nvim Spec Mẫu (cho user)

```lua
{
  "yourname/sql-lens.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  ft = { "sql", "plpgsql", "mysql" },
  keys = {
    { "<leader>sq", desc = "SqlLens Toggle" },
    { "<leader>sc", desc = "SqlLens Connect" },
    { "<leader>se", desc = "SqlLens Explain" },
    { "<leader>sd", desc = "SqlLens Detail" },
  },
  opts = {
    connections = {
      { name = "local", type = "postgres",
        host = "localhost", dbname = "dev",
        user = "postgres", password = "secret" },
    },
  },
},
```

---

## Debug Tips

```lua
-- In ra plan object để xem structure
vim.notify(vim.inspect(plan_node), vim.log.levels.DEBUG)

-- Xem tất cả extmarks trong buffer
local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details=true })
vim.notify(vim.inspect(marks))

-- Check treesitter có hoạt động không
:checkhealth nvim-treesitter

-- Test connection thủ công
:lua require("sql-lens.connections").get_active(0):ping(function(ok) print(ok) end)
```
