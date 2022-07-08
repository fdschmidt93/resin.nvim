local Sender = require "resin.sender"

local M = {}

M.config = {
  enable_filetype = true,
  -- general hooks for __all__ send-to-repl
  on_before_send = {},
  on_after_send = {},
  on_before_receive = {},
  on_after_receive = {},
  default_mappings = true,
  filetype = {},
}

-- buf = Sender
M._senders = {}
M._receivers = {}

M.send = function(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  if not M._senders[bufnr] then
    M._senders[bufnr] = Sender:new { bufnr = bufnr }
  end
  M._senders[bufnr]:send(opts)
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
