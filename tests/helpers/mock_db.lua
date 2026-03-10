local M = {}

function M.new_postgres_mock(plan_data)
  return {
    type = "postgres",
    explain = function(self, sql, cb)
      vim.schedule(function()
        cb(nil, plan_data)
      end)
    end,
  }
end

function M.new_error_mock()
  return {
    type = "postgres",
    explain = function(self, sql, cb)
      vim.schedule(function()
        cb("Connection refused", nil)
      end)
    end,
  }
end

return M
