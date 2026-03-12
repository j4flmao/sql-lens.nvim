local M = {}

M.defaults = {
  trigger = {
    on_write    = true,
    on_change   = true,
    debounce_ms = 500,
    min_length  = 10,
  },
  display = {
    mode          = "virtual",
    virtual_prefix = "󰋼 ",
    show_cost     = true,
    show_rows     = true,
    show_warnings = true,
    max_virtual_width = 80,
    float = {
      border  = "rounded",
      width   = 70,
      height  = 20,
    },
  },
  thresholds = {
    cost_warn     = 1000,
    cost_error    = 10000,
    rows_warn     = 100000,
    seq_scan_warn = true,
  },
  lint = {
    enable_offline = false,
  },
  connections = {},
  secrets = {
    use_env    = true,
    use_dotenv = true,
  },
  keymaps = {
    toggle        = "<leader>sq",
    explain       = "<leader>se",
    show_detail   = "<leader>sd",
    connect       = "<leader>sc",
    run           = "<leader>sr",
    run_all       = "<leader>sR",
    report        = "<leader>sH",
    pick_db       = "<leader>sD",
  },
}

function M.validate(opts)
  vim.validate({
    trigger          = { opts.trigger, "table" },
    display          = { opts.display, "table" },
    ["display.mode"] = { opts.display.mode, function(v)
      return vim.tbl_contains({"virtual","float","sidebar"}, v)
    end, "virtual | float | sidebar" },
  })
end

return M
