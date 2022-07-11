local utils = require "resin.utils"
local state = require "resin.state"

local Receiver = {}
Receiver.__index = Receiver

function Receiver:new(opts)
  opts = opts or {}
  local config = require("resin").config

  opts.senders = vim.F.if_nil(opts.senders, {})
  if opts.sender then
    table.insert(opts.senders, opts.sender)
    opts.sender = nil
  end
  opts.on_before_receive = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_before_receive, config.hooks.on_before_receive))
  opts.on_after_receive = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_after_receive, config.hooks.on_after_receive))

  opts.enable_filetype = vim.F.if_nil(opts.enable_filetype, true)
  if opts.enable_filetype then
    local filetype_hooks = vim.tbl_deep_extend(
      "keep",
      vim.deepcopy(config.filetype[opts.filetype]) or {},
      require(string.format("resin.ft.%s", opts.filetype))
    )
    opts.on_before_receive.filetype = filetype_hooks.on_before_receive
    opts.on_after_receive.filetype = filetype_hooks.on_after_receive
  end
  local receiver = setmetatable(opts, Receiver)
  state.add_receiver(receiver)
  return receiver
end

function Receiver:add_sender(sender)
  table.insert(self.senders, sender)
end

function Receiver:receive(data, opts)
  if type(self.on_before_receive) == "table" then
    for _, fn in pairs(self.on_before_receive) do
      fn(self, data, opts)
    end
  end
  self:receiver_fn(data, opts)
  if type(self.on_after_receive) == "table" then
    for _, fn in pairs(self.on_after_receive) do
      fn(self, data, opts)
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
