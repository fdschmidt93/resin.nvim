local Job = require "plenary.job"
local Path = require "plenary.path"

local Receiver = require "resin.receiver"
local paste_file = Path:new(vim.fn.stdpath "state"):joinpath ".resin_paste.txt"

local socket_mt = {
  __tostring = function(self)
    return string.format("%s:%s.%s", self.session, self.window, self.pane)
  end,
}

return function(opts)
  opts = opts or {}

  -- TODO notify more nicley with vim.notiy
  assert(opts.socket, "Must pass valid socket!")

  opts.socket = setmetatable(opts.socket, socket_mt)

  opts.receiver_fn = function(self, data)
    paste_file:write(table.concat(data, "\n"), "w")
    Job:new({
      command = "tmux",
      args = { "load-buffer", paste_file:absolute() },
    }):sync()
    Job:new({
      command = "tmux",
      args = { "paste-buffer", "-d", "-t", tostring(self.socket) },
    }):sync()
    return Receiver:new(opts)
  end
  -- TODO: session/window/pane tracking
  opts._exists = function(self)
    return true
  end

  opts._tostring = function(self)
    return tostring(self.socket)
  end

  return Receiver:new(opts)
end
