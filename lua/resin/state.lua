local a = vim.api

local M = {}

M._senders = {}
M._receivers = {}

function M.add_sender(sender)
  if not M._senders[sender.bufnr] then
    a.nvim_create_autocmd("BufUnload", {
      buffer = sender.bunfr,
      once = true,
      callback = function()
        M._senders[sender.bufnr] = nil
      end,
    })
  end
  M._senders[sender.bufnr] = sender
end

function M.add_receiver(receiver)
  table.insert(M._receivers, receiver)
end

function M.get_senders()
  return M._senders
end

return M
