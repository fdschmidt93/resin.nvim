local a = vim.api
local history = require "resin.history"
local state = require "resin.state"
local extmarks = require "resin.extmarks"
local utils = require "resin.utils"

local resin_ns = a.nvim_create_namespace "ResinMarks"

local Sender = {}
Sender.__index = Sender

function Sender:new(opts)
  opts = opts or {}
  local config = require("resin").config

  -- initialize properties
  opts.bufnr = vim.F.if_nil(opts.bufnr, a.nvim_get_current_buf())
  opts.filetype = vim.F.if_nil(opts.filetype, vim.bo[opts.bufnr].filetype)

  -- each Sender can have multiple Receivers; for simplicity, redirect into receivers
  opts.receivers = vim.F.if_nil(opts.receivers, {})
  if opts.receiver then
    table.insert(opts.receivers, opts.receiver)
    opts.receiver = nil
  end

  opts.on_before_send = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_before_send, config.hooks.on_before_send))
  opts.on_after_send = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_after_send, config.hooks.on_after_send))

  opts.enable_filetype = vim.F.if_nil(opts.enable_filetype, true)
  if opts.filetype ~= "" and opts.enable_filetype then
    local filetype_hooks = vim.tbl_deep_extend(
      "keep",
      vim.deepcopy(config.filetype[opts.filetype]) or {},
      require(string.format("resin.ft.%s", opts.filetype))
    )
    opts.on_before_send.filetype = filetype_hooks.on_before_send
    opts.on_after_send.filetype = filetype_hooks.on_after_send
    opts.setup_receiver = vim.F.if_nil(opts.setup_receiver, filetype_hooks.setup_receiver)
  end
  local sender = setmetatable(opts, Sender)
  state.add_sender(sender)
  return sender
end

-- TODO: block mode support but makes impl likely needlessly complex
-- TODO: multi-width chars? see above
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
  local begin_extmark_id = a.nvim_buf_set_extmark(0, resin_ns, begin_pos[1] - 1, begin_pos[2], {})
  local end_extmark_id = a.nvim_buf_set_extmark(0, resin_ns, end_pos[1] - 1, end_pos[2], {})
  extmarks.add(begin_extmark_id, end_extmark_id)
  -- pos: {1, 0}-indexed
  return data, { motion = motion, begin_pos = begin_pos, end_pos = end_pos }
end

function Sender:_instantiate_receiver(receiver_idx)
  local receiver = self.receivers and self.receivers[receiver_idx]
  -- attempt to auto-add a receiver
  if not receiver or (receiver and not receiver:exists()) then
    table.remove(self.receivers, receiver_idx)
    self:add_receiver(nil, { receiver_idx = receiver_idx })
    receiver = self.receivers[receiver_idx]
  end
  if self.receiver and not receiver then
    vim.notify(
      string.format(
        "%s is an invalid receiver index! Only %s receivers attached to sender.",
        receiver_idx,
        #self.receivers,
        vim.log.levels.ERROR,
        { title = "resin.nvim" }
      )
    )
    return
  end
  return receiver
end

function Sender:send_fn(data, opts)
  local config = require("resin").config
  opts = opts or {}
  opts.receiver_idx = vim.F.if_nil(opts.receiver_idx, 1)
  local receiver = self:_instantiate_receiver(opts.receiver_idx)
  if not receiver then
    return
  end
  if type(self.on_before_send) == "table" then
    for _, fn in pairs(self.on_before_send) do
      fn(self, data, opts)
    end
  end
  receiver:receive(data, opts)
  local highlight = vim.F.if_nil(opts.highlight, {})
  -- not valid if sent from history
  if opts.begin_pos then
    utils.hl_on_send {
      regtype = opts.motion,
      begin_pos = opts.begin_pos,
      end_pos = opts.end_pos,
      timeout = vim.F.if_nil(highlight.timeout, config.highlight.timeout),
      hl_group = vim.F.if_nil(highlight.group, config.highlight.group),
    }
  end
  -- TODO make history opt-out for single send
  local history_config = require("resin").config.history
  if not (opts.history == false) and history_config then
    history.write()
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
    local data, meta_data = Sender._operatorfunc(motion)
    if motion == "block" then
      vim.notify("Sending from visual block mode not supported.", vim.log.levels.WARN, { title = "resin.nvim" })
      return
    end
    self:send_fn(data, vim.tbl_deep_extend("force", opts, meta_data))
    a.nvim_win_set_cursor(0, cursor)
  end
  vim.go.operatorfunc = "v:lua._ResinOperatorFunc"
  a.nvim_feedkeys("g@", "n", false)
end

-- how to identify receiver
function Sender:add_receiver(receiver, opts)
  opts = opts or {}
  if receiver == nil and self.setup_receiver then
    receiver = self:setup_receiver()
  end
  if receiver == nil then
    vim.notify("No receiver provided", vim.log.levels.WARN, { title = "resin.nvim" })
    return
  end
  if type(opts.receiver_idx) == "number" then
    table.insert(self.receivers, opts.receiver_idx, receiver)
  else
    table.insert(self.receivers, receiver)
  end
end

function Sender:remove_receiver(index)
  if index then
    table.remove(self.receivers, index)
  else
    self.receivers = {}
  end
end

return Sender
