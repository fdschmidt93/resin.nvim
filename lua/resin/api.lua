local state = require "resin.state"
local Sender = require "resin.sender"

local resin_api = {}

---@tag resin.api
---@config { ["name"] = "API" }
---@brief [[
---
--- The resin.api denotes the user-facing functions.
---
---@brief ]]

--- Primary send-to-repl function.
--- - Note:
---     - Leverages operators to e.g. <C-c><c-c>ip for inside paragraph or <c-c><c-c>iW for inside WORD
---     - Can be prefixed by a count eg 2<C-c><C-c> to send to the second receiver
---@param opts table: options to pass to send
---@field on_before_send function|table: (table of) function(s) that affects send text and history
---@field on_after_send function|table: (table of) function(s) for your needs after sending
---@field on_before_receive function|table: (table of) function(s) that affects send text but not history
---@field on_after_receive function|table: (table of) function(s) for your needs after receiving
---@field setup_receiver function: function to automatically setup a receiver, supersedes filetype cfg
---@field history boolean: enable or disable history for sending, fo (default: true)
---@field highlight boolean|table: enable or disable highlight for sending, cf. |resin.setup| (default: true)
resin_api.send = function(opts)
  opts = opts or {}
  -- use count (like `3w` to jump to third word) for Count<C-c> to decide what receiver to send to
  -- for multi receiver senders
  opts.receiver_idx = vim.v.count > 0 and vim.v.count or 1
  local bufnr = vim.api.nvim_get_current_buf()
  local sender = resin_api.get_sender(bufnr)
  sender:send_operator(opts)
end

--- Send last `count` history to receiver of current buffer.
--- - Note:
---     - The keymapping can be preseded by a count, e.g. 2<C-c><C-h> sends last 2 entries by default
---     - Avoids further adding to history
---@param opts table: see |resin.send|
resin_api.send_history = function(opts)
  opts = opts or {}
  opts.count = vim.v.count > 0 and vim.v.count or 1
  opts.limit_filetype = vim.F.if_nil(opts.limit_filetype, true)
  opts.limit_file = vim.F.if_nil(opts.limit_file, false)
  local bufnr = vim.api.nvim_get_current_buf()
  local sender = resin_api.get_sender(bufnr)
  sender:send_history(opts)
end

--- Launches selector interface to attach receiver.
--- - Note:
---     - The telescope picker allows to set multiple receivers with multi-selections
---@param opts table: see |resin.send|
resin_api.select_receiver = function(opts)
  local has, _ = pcall(require, "telescope")
  if has then
    require("resin.telescope").receiver(opts)
  else
    require("resin.select").receiver(opts)
  end
end

--- Launches selector interface to send history to the receiver of the current buffer.
--- - Note:
---     - The telescope picker allows to select multiple entries to send to receiver in order of selection
---@param opts table: options to pass to picker
---@field limit_filetype boolean: limit to entries of the current filetype (default: true)
---@field limit_file boolean: limit to entries of the current file (default: false)
resin_api.select_history = function(opts)
  opts = opts or {}
  local has, _ = pcall(require, "telescope")
  if has then
    require("resin.telescope").repl_history(opts)
  else
    require("resin.select").repl_history(opts)
  end
end

--- Get or create Sender for buffer, a utility function for customization.
---@param bufnr number: the buffer to get sender for (default: current buffer)
resin_api.get_sender = function(bufnr)
  bufnr = vim.F.if_nil(bufnr, vim.api.nvim_get_current_buf())
  local senders = state.get_senders()
  local sender = senders[bufnr]
  if not sender then
    sender = Sender:new { bufnr = bufnr }
  end
  return sender
end


return resin_api
