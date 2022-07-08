local a = vim.api
local history = require "resin.history"

local Sender = {}
Sender.__index = Sender

function Sender:new(opts)
  opts = opts or {}

  -- initialize properties
  opts.bufnr = vim.F.if_nil(opts.bufnr, a.nvim_get_current_buf())
  opts.filetype = vim.F.if_nil(opts.filetype, vim.bo[opts.bufnr].filetype)
  opts.on_before_send = vim.F.if_nil(opts.on_before_send, {})
  opts.on_after_send = vim.F.if_nil(opts.on_after_send, {})

  opts.enable_filetype = vim.F.if_nil(opts.enable_filetype, true)
  if opts.filetype ~= "" and opts.enable_filetype then
    local filetype_hooks = vim.tbl_deep_extend(
      "keep",
      require("resin").config.filetype[opts.filetype] or {},
      require(string.format("resin.ft.%s", opts.filetype))
    )
    opts.on_before_send.filetype = filetype_hooks.on_before_send
    opts.on_after_send.filetype = filetype_hooks.on_after_send
    opts.setup_receiver = vim.F.if_nil(opts.setup_receiver, filetype_hooks.setup_receiver)
  end
  -- to add, global config hooks
  return setmetatable(opts, Sender)
end

-- TODO: block mode support
-- TODO: multi-width chars?
-- TODO: carve-out post-processing
function Sender._operatorfunc(motion)
  local begin_pos = a.nvim_buf_get_mark(0, "[")
  local end_pos = a.nvim_buf_get_mark(0, "]")
  local max_col = #a.nvim_buf_get_lines(0, end_pos[1] - 1, end_pos[1], false)[1]
  -- handle line motions
  begin_pos[2] = motion == "line" and 0 or begin_pos[2]
  end_pos[2] = motion ~= "line" and math.min(end_pos[2], max_col) or max_col -- end_pos[2] may be inf (eg inside paragraph)

  -- buf_get_text exclusive: add end_pos + 1
  local data = a.nvim_buf_get_text(0, begin_pos[1] - 1, begin_pos[2], end_pos[1] - 1, end_pos[2] + 1, {})
  -- clean up tabs
  local spaces = {}
  for _ = 1, vim.bo.tabstop do
    table.insert(spaces, " ")
  end
  spaces = table.concat(spaces, "")
  for i = 1, #data do
    data[i] = string.gsub(data[i], "\t", spaces)
  end
  return data
end

function Sender:send_fn(data, opts)
  opts = opts or {}
  if not self.receiver then
    self:set_receiver(opts.receiver)
  end
  if type(self.on_before_send) == "table" then
    for _, fn in pairs(self.on_before_send) do
      fn(self, data, opts)
    end
  end
  self.receiver:receive(data, opts)
  -- TODO make history opt-out for single send
  local history_config = require("resin").config.history
  if not (opts.history == false) and history_config then
    history.write_history(self.bufnr, data)
  end
  if type(self.on_after_send) == "table" then
    for _, fn in pairs(self.on_after_send) do
      fn(self, data, opts)
    end
  end
end

function Sender:send(opts)
  opts = opts or {}
  -- save cursor for restoring post-sending
  local cursor = a.nvim_win_get_cursor(0)
  _ResinOperatorFunc = function(motion)
    local data = Sender._operatorfunc(motion)
    self:send_fn(data, opts)
    a.nvim_win_set_cursor(0, cursor)
  end
  vim.go.operatorfunc = "v:lua._ResinOperatorFunc"
  a.nvim_feedkeys("g@", "n", false)
end

function Sender:set_receiver(receiver)
  if not receiver then
    self.receiver = self:setup_receiver()
  else
    self.receiver = receiver
  end
end

return Sender
