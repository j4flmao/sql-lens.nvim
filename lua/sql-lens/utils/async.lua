local M = {}

function M.job(cmd, cb)
  local stdout_data = {}
  local stderr_data = {}

  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,

    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_data, data)
      end
    end,

    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr_data, data)
      end
    end,

    on_exit = function(_, code)
      local out = table.concat(stdout_data, "\n"):gsub("^\n+", ""):gsub("\n+$", "")
      local err = table.concat(stderr_data, "\n"):gsub("^\n+", ""):gsub("\n+$", "")
      vim.schedule(function()
        cb(code, out, err)
      end)
    end,
  })

  if job <= 0 then
    cb(1, "", "Failed to start job: " .. table.concat(cmd, " "))
  end
end

return M
