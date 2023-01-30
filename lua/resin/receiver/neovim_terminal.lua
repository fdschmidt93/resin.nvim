local Receiver = require "resin.receiver"

return function(opts)
  opts = opts or {}

  -- TODO notify more nicley with vim.notiy
  assert(opts.bufnr, "Must pass valid bufnr!")
  assert(vim.b[opts.bufnr].terminal_job_id, "Must be terminal buffer!")

  opts.receiver_fn = function(self, data)
    local send_data = vim.trim(table.concat(data, "\n"))
    vim.api.nvim_chan_send(
      vim.b[self.bufnr].terminal_job_id,
      string.format("%s%s%s", "\27[200~", send_data, "\27[201~\13\13")
    )
  end

  -- being passed through to metatable
  opts._exists = function(self)
    local exists, _ = pcall(vim.api.nvim_buf_get_var, self.bufnr, "terminal_job_id")
    return exists
  end

  opts._tostring = function(self)
    return vim.api.nvim_buf_get_name(self.bufnr)
  end

  return Receiver:new(opts)
end
