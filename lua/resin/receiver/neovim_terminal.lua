local Receiver = require "resin.receiver"

return function(opts)
  opts = opts or {}

  opts.receiver_fn = function(self, data)
    vim.api.nvim_chan_send(self.chan, table.concat(data, "\n"))
  end

  return Receiver:new(opts)
end
