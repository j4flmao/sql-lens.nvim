local M = {}

function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(delay, 0, vim.schedule_wrap(function()
      timer:close()
      timer = nil
      fn(unpack(args))
    end))
  end
end

return M
