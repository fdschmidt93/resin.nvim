local Receiver = {}
Receiver.__index = Receiver

function Receiver:new(opts)
  opts = opts or {}

  opts.on_before_receive = vim.F.if_nil(opts.on_before_receive, {})
  opts.on_after_receive = vim.F.if_nil(opts.on_after_receive, {})

  opts.enable_filetype = vim.F.if_nil(opts.enable_filetype, true)
  if opts.enable_filetype then
    local filetype_hooks = vim.tbl_deep_extend(
      "keep",
      require("resin").config.filetype[opts.filetype] or {},
      require(string.format("resin.ft.%s", opts.filetype))
    )
    opts.on_before_receive.filetype = filetype_hooks.on_before_receive
    opts.on_after_receive.filetype = filetype_hooks.on_after_receive
  end
  return setmetatable(opts, Receiver)
end

function Receiver:set_sender(sender)
  self.sender = sender
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

return Receiver