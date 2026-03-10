local M = {}

function M.setup()
  local groups = {
    SqlLensOk    = { fg = "#4ade80", bold = false },
    SqlLensInfo  = { fg = "#60a5fa", bold = false },
    SqlLensWarn  = { fg = "#facc15", bold = true  },
    SqlLensError = { fg = "#f87171", bold = true  },
    SqlLensDim   = { fg = "#6b7280", bold = false },
    SqlLensBg    = { bg = "#1e2030"               },
  }

  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
