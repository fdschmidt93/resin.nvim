local state = require "resin.state"
local Sender = require "resin.sender"

local M = {}

M.config = {
  enable_filetype = true,
  -- general hooks for __all__ send-to-repl
  hooks = {
    on_before_send = {},
    on_after_send = {},
    on_before_receive = {},
    on_after_receive = {},
  },
  default_mappings = true,
  filetype = {},
}

-- buf = Sender
M.send = function(opts)
  opts = opts or {}
  -- use count (like `3w` to jump to third word) for Count<C-c> to decide what receiver to send to
  -- for multi receiver senders
  opts.receiver_idx = vim.v.count > 0 and vim.v.count or 1
  local bufnr = vim.api.nvim_get_current_buf()
  local senders = state.get_senders()
  local sender = senders[bufnr]
  if not sender then
    sender = Sender:new { bufnr = bufnr }
  end
  sender:send(opts)
end

M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts)
  if M.config.default_mappings then
    vim.keymap.set({ "n", "x" }, "<C-c>", function()
      require("resin").send()
    end, { desc = "Send-to-repl" })
  end
end

return M
