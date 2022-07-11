local state = require "resin.state"
local Sender = require "resin.sender"
local os_sep = require("plenary.path").path.sep

local M = {}

M.config = {
  enable_filetype = true,
  history = {
    path = vim.fn.stdpath "state" .. os_sep .. "resin_history.json",
    limit = 20,
    save_on_exit = true,
  },
  highlight = {
    timeout = 200,
    group = "IncSearch",
  },
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

M.get_sender = function(bufnr)
  bufnr = vim.F.if_nil(bufnr, vim.api.nvim_get_current_buf())
  local senders = state.get_senders()
  local sender = senders[bufnr]
  if not sender then
    sender = Sender:new { bufnr = bufnr }
  end
  return sender
end

-- buf = Sender
M.send = function(opts)
  opts = opts or {}
  -- use count (like `3w` to jump to third word) for Count<C-c> to decide what receiver to send to
  -- for multi receiver senders
  opts.receiver_idx = vim.v.count > 0 and vim.v.count or 1
  local bufnr = vim.api.nvim_get_current_buf()
  local sender = M.get_sender(bufnr)
  sender:send(opts)
end

M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts)
  if M.config.default_mappings then
    vim.keymap.set({ "n", "x" }, "<C-c>", function()
      require("resin").send()
    end, { desc = "Send-to-repl" })
  end
  if M.config.history.save_on_exit then
    vim.api.nvim_create_autocmd("VimLeave", {
      callback = function()
        local resin_extmarks = require "resin.extmarks"
        -- history was changed
        if not vim.tbl_isempty(resin_extmarks._marks) then
          require("resin.history").write { convert = true }
        end
      end,
    })
  end
end

return M
