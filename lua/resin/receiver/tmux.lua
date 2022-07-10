local Job = require "plenary.job"
local Path = require "plenary.path"

local Receiver = require "resin.receiver"
local paste_file = Path:new(vim.fn.stdpath "state"):joinpath ".resin_paste.txt"

local function get_tmux_sockets()
  local sockets = {}
  local sessions = Job:new({ command = "tmux", args = { "list-sessions", "-F", "#{session_name}" } }):sync()
  for _, session in ipairs(sessions) do
    local windows =
    Job:new({ command = "tmux", args = { "list-windows", "-F", "#{window_index}", "-t", session } }):sync()
    for _, window in ipairs(windows) do
      local pane = Job:new({
        command = "tmux",
        args = { "list-panes", "-F", "#{pane_index}", "-t", session .. ":" .. window },
      }):sync()
      table.insert(sockets, { session = session, window = window, pane = pane })
    end
  end
  return sockets
end

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
  opts.exists = function(self)
    return true
  end

  return Receiver:new(opts)
end
