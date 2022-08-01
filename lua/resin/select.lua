local api = vim.api
local resin = require "resin"
local utils = require "resin.utils"
local M = {}

M.receiver = function(opts)
  opts = opts or {}
  local bufnr = api.nvim_get_current_buf()
  local items = {}

  local neovim_terminals = vim.tbl_filter(function(chan)
    return chan.mode == "terminal" and chan.stream == "job"
  end, vim.api.nvim_list_chans())
  for _, b in ipairs(neovim_terminals) do
    b.name = api.nvim_buf_get_name(b.buffer)
    b.format_item = function()
      return "nvim" .. " " .. tostring(b.buffer) .. " " .. table.concat(b.argv, " ")
    end
    b.return_receiver = function()
      local nvim = require "resin.receiver.neovim_terminal"
      return nvim { bufnr = b.buffer }
    end
    table.insert(items, b)
  end

  if vim.fn.executable "tmux" == 1 then
    for _, pane in ipairs(utils.get_tmux_sockets()) do
      pane.format_item = function()
        return "tmux" .. " " .. pane.name .. " " .. pane.pane_title
      end
      pane.return_receiver = function()
        local tmux = require "resin.receiver.tmux"
        return tmux {
          socket = { session = pane.session, window = pane.window_index, pane = pane.pane_index },
        }
      end
      table.insert(items, pane)
    end
  end

  if vim.tbl_isempty(items) then
    vim.notify("No receivers available.", vim.log.levels.INFO, { title = "resin.telescope.receivers" })
    return
  end

  vim.ui.select(items, {
    prompt = "Available Receivers",
    format_item = function(item)
      return item:format_item()
    end,
  }, function(choice)
    if choice then
      local sender = resin.get_sender(bufnr)
      sender:remove_receiver()
      local receiver = choice:return_receiver()
      sender:add_receiver(receiver)
    end
  end)
end

M.repl_history = function(opts)
  opts = opts or {}
  opts.limit_filetype = vim.F.if_nil(opts.limit_filetype, true)
  opts.limit_file = vim.F.if_nil(opts.limit_file, false)

  local bufnr = api.nvim_get_current_buf()
  local sender = vim.F.if_nil(opts.sender, require("resin").get_sender(bufnr))
  local items = utils.parse_history(opts)
  vim.ui.select(items, {
    prompt = "Available Receivers",
    format_item = function(item)
      -- TODO: maybe add more info
      -- local name = vim.fn.fnamemodify(item.filename, ":t")
      -- local status = item.active and "R" or "D"
      -- local time = os.date("%Y/%m/%d", item.time)
      local string = table.concat(item.data, " ")
      return string
    end,
  }, function(choice)
    if choice then
      local bufnames = {}
      for _, b in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(b) then
          bufnames[api.nvim_buf_get_name(b)] = true
        end
      end
      sender:send(choice.data, { history = bufnames[choice.filename] })
    end
  end)
end

return M
