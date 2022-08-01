---@mod resin.Sender Introduction
---@brief [[
---
---NOTE: remember there is no formatting or text wrapping
---@brief ]]

local api = vim.api
local resin_history = require "resin.history"
local state = require "resin.state"
local extmarks = require "resin.extmarks"
local utils = require "resin.utils"

local resin_ns = api.nvim_create_namespace "ResinMarks"

---@class resin.Sender
---@field bufnr number Buffer handle to create |Sender| for (default: current buffer)
---@field filetype string filetype to create |Sender| for (default: filetype of current buffer)
---@field receivers table array of |Receiver|s for Sender (default: empty table)
---@field on_before_send table<function> table of functions executed before sending (default: empty table)
---@field on_after_send table<function> table of functions executed before sending (default: empty table)
local Sender = {}
Sender.__index = Sender

function Sender:new(opts)
  opts = opts or {}
  opts.bufnr = vim.F.if_nil(opts.bufnr, api.nvim_get_current_buf())

  -- each Sender can have multiple Receivers; for simplicity, redirect into receivers
  opts.receivers = vim.F.if_nil(opts.receivers, {})
  if opts.receiver then
    table.insert(opts.receivers, opts.receiver)
    opts.receiver = nil
  end

  local sender = setmetatable(opts, Sender)
  state.add_sender(sender)
  return sender
end

function Sender._setup_hooks(opts)
  opts = opts or {}
  local hooks = {}
  local config = require("resin").config or {}
  hooks.on_before_send = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_before_send, config.hooks.on_before_send))
  hooks.on_after_send = utils.fn_wrap_tbl(vim.F.if_nil(opts.on_after_send, config.hooks.on_after_send))
  local filetype_config = utils.get_filetype_config(opts)
  local filetype_hooks =
    vim.tbl_deep_extend("keep", vim.deepcopy(config.filetype[opts.filetype]) or {}, filetype_config)
  hooks.on_before_send.filetype = filetype_hooks.on_before_send
  hooks.on_after_send.filetype = filetype_hooks.on_after_send
  return hooks
end

-- TODO: block mode support but makes impl likely needlessly complex
-- TODO: multi-width chars? see above
-- TODO: carve-out post-processing
function Sender._operatorfunc(motion)
  local begin_pos = api.nvim_buf_get_mark(0, "[")
  local end_pos = api.nvim_buf_get_mark(0, "]")
  local max_col = #api.nvim_buf_get_lines(0, end_pos[1] - 1, end_pos[1], false)[1]
  -- handle line motions
  begin_pos[2] = motion == "line" and 0 or begin_pos[2]
  end_pos[2] = motion ~= "line" and math.min(end_pos[2], max_col) or max_col -- end_pos[2] may be inf (eg inside paragraph)

  -- buf_get_text exclusive: add end_pos + 1
  local data = api.nvim_buf_get_text(0, begin_pos[1] - 1, begin_pos[2], end_pos[1] - 1, end_pos[2] + 1, {})
  -- clean up tabs
  local spaces = {}
  for _ = 1, vim.bo.tabstop do
    table.insert(spaces, " ")
  end
  spaces = table.concat(spaces, "")
  for i = 1, #data do
    data[i] = string.gsub(data[i], "\t", spaces)
  end
  local begin_extmark_id = api.nvim_buf_set_extmark(0, resin_ns, begin_pos[1] - 1, begin_pos[2], {})
  local end_extmark_id = api.nvim_buf_set_extmark(0, resin_ns, end_pos[1] - 1, end_pos[2], {})
  -- pos: {1, 0}-indexed
  return data,
    {
      motion = motion,
      begin_pos = begin_pos,
      end_pos = end_pos,
      begin_extmark_id = begin_extmark_id,
      end_extmark_id = end_extmark_id,
    }
end

function Sender:send_history(opts)
  opts = opts or {}
  opts.count = vim.F.if_nil(opts.count, 1)
  local history = utils.parse_history(opts)
  local data = {}
  for i = 1, opts.count do
    for _, line in ipairs(history[i].data) do
      table.insert(data, line)
    end
  end
  self:send(data, { history = false })
end

function Sender:send_operator(opts)
  opts = opts or {}
  -- save cursor for restoring post-sending
  local cursor = api.nvim_win_get_cursor(0)
  _ResinOperatorFunc = function(motion)
    local data, meta_data = Sender._operatorfunc(motion)
    if motion == "block" then
      vim.notify("Sending from visual block mode not supported.", vim.log.levels.WARN, { title = "resin.nvim" })
      return
    end
    self:send(data, vim.tbl_deep_extend("force", opts, meta_data))
    api.nvim_win_set_cursor(0, cursor)
  end
  vim.go.operatorfunc = "v:lua._ResinOperatorFunc"
  api.nvim_feedkeys("g@", "n", false)
end

function Sender:send(data, opts)
  local config = require("resin").config
  local history_config = require("resin").config.history
  opts = opts or {}
  opts.filetype = vim.F.if_nil(opts.filetype, vim.bo[self.bufnr].filetype)
  opts.receiver_idx = vim.F.if_nil(opts.receiver_idx, 1)
  local receiver = self:_get_receiver(opts.receiver_idx)
  if not receiver then
    return
  end
  local orig_data
  if not (opts.history == false) and history_config then
    orig_data = vim.deepcopy(data)
  end
  local hooks = self._setup_hooks(opts)
  for hook, fn in pairs(hooks.on_before_send) do
    if type(fn) == "function" then
      fn(self, data, opts)
    else
      vim.notify(
        string.format("%s hook is not a valid function but %s", hook, type(hook)),
        vim.log.levels.WARN,
        { title = "resin.send" }
      )
    end
  end
  receiver:receive(data, opts)
  local highlight = vim.F.if_nil(opts.highlight, {})
  -- not valid if sent from history
  if type(highlight) == "table" and opts.begin_pos then
    utils.hl_on_send {
      regtype = opts.motion,
      begin_pos = opts.begin_pos,
      end_pos = opts.end_pos,
      timeout = vim.F.if_nil(highlight.timeout, config.highlight.timeout),
      hl_group = vim.F.if_nil(highlight.group, config.highlight.group),
    }
  end
  if not (opts.history == false) and history_config then
    local history = resin_history.read_history()
    -- check availability of marks
    if vim.deep_equal(orig_data, data) and opts.begin_extmark_id and opts.end_extmark_id then
      extmarks.add(opts.begin_extmark_id, opts.end_extmark_id)
    else
      resin_history.add_entry(history, { filename = api.nvim_buf_get_name(self.bufnr), time = os.time(), data = data })
    end
    resin_history.write(history)
  end
  for hook, fn in pairs(hooks.on_after_send) do
    if type(fn) == "function" then
      fn(self, data, opts)
    else
      vim.notify(
        string.format("%s hook is not a valid function but %s", hook, type(hook)),
        vim.log.levels.WARN,
        { title = "resin.send" }
      )
    end
  end
end

function Sender:_get_receiver(receiver_idx, opts)
  opts = opts or {}
  local receiver = self.receivers and self.receivers[receiver_idx]
  -- attempt to auto-add a receiver
  if not receiver or (receiver and not receiver:exists()) then
    if receiver then
      table.remove(self.receivers, receiver_idx)
    end
    self:add_receiver(nil, vim.tbl_deep_extend("force", opts, { receiver_idx = receiver_idx }))
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

-- how to identify receiver
function Sender:add_receiver(receiver, opts)
  opts = opts or {}
  opts.filetype = vim.F.if_nil(opts.filetype, vim.bo[self.bufnr].filetype)
  local filetype_config = utils.get_filetype_config(opts)
  local setup_receiver = vim.F.if_nil(opts.setup_receiver, filetype_config.setup_receiver)
  if receiver == nil and setup_receiver then
    receiver = filetype_config.setup_receiver(self.bufnr)
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
