local utils = require "resin.utils"
local state = require "resin.state"

local Receiver = {}
Receiver.__index = Receiver

function Receiver:new(opts)
  opts = opts or {}

  opts.senders = vim.F.if_nil(opts.senders, {})
  if opts.sender then
    table.insert(opts.senders, opts.sender)
    opts.sender = nil
  end
  local receiver = setmetatable(opts, Receiver)
  state.add_receiver(receiver)
  return receiver
end

function Receiver:add_sender(sender)
  table.insert(self.senders, sender)
end

function Receiver._setup_hooks(opts)
  opts = opts or {}
  local hooks = {}
  local config = require("resin").config or {}
  hooks.on_before_receive = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_before_receive, config.hooks.on_before_receive))
  hooks.on_after_receive = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_after_receive, config.hooks.on_after_receive))

  local filetype_config = utils.get_filetype_config(opts)
  local filetype_hooks =
    vim.tbl_deep_extend("keep", vim.deepcopy(config.filetype[opts.filetype]) or {}, filetype_config)
  hooks.on_before_receive.filetype = filetype_hooks.on_before_receive
  hooks.on_after_receive.filetype = filetype_hooks.on_after_receive
  return hooks
end

function Receiver:receive(data, opts)
  opts = opts or {}
  local hooks = self._setup_hooks(opts)
  for hook, fn in pairs(hooks.on_before_receive) do
    if type(fn) == "function" then
      fn(self, data, opts)
    else
      vim.notify(
        string.format("%s hook is not a valid function but %s", hook, type(hook)),
        vim.log.levels.WARN,
        { title = "resin.receive" }
      )
    end
  end
  self:receiver_fn(data, opts)
  for hook, fn in pairs(hooks.on_after_receive) do
    if type(fn) == "function" then
      fn(self, data, opts)
    else
      vim.notify(
        string.format("%s hook is not a valid function but %s", hook, type(hook)),
        vim.log.levels.WARN,
        { title = "resin.receive" }
      )
    end
  end
end

function Receiver:exists()
  assert(self._exists, "`_exists` needs to be implemented!")
  local exists = self:_exists()
  for name, receiver in pairs(state._receivers) do
    if vim.deep_equal(self, receiver) then
      state._receivers[name] = nil
    end
  end
  return exists
end

function Receiver:__tostring()
  assert(self._tostring, "`_tostring` needs to be implemented!")
  return self:_tostring()
end

return Receiver
