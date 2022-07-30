local api = vim.api
local Job = require "plenary.job"

M = {}

local resin_ns = vim.api.nvim_create_namespace "Resin"

local REGTYPES = { line = "V", char = "v", block = "" }

-- adapted from hl on yank
function M.hl_on_send(opts)
  opts = opts or {}
  local regtype = vim.F.if_nil(REGTYPES[opts.regtype], "v")
  local higroup = opts.hl_group or "IncSearch"
  local timeout = opts.timeout or 300
  local inclusive = vim.F.if_nil(opts.inclusive, true)

  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_clear_namespace(bufnr, resin_ns, 0, -1)

  -- begin_pos = { begin_pos[2] - 1, begin_pos[3] - 1 + begin_pos[4] }
  -- end_pos = { end_pos[2] - 1, end_pos[3] - 1 + end_pos[4] }

  vim.highlight.range(
    bufnr,
    resin_ns,
    higroup,
    { opts.begin_pos[1] - 1, opts.begin_pos[2] },
    { opts.end_pos[1] - 1, opts.end_pos[2] },
    { regtype = regtype, inclusive = inclusive, priority = 200 }
  )

  vim.defer_fn(function()
    if api.nvim_buf_is_valid(bufnr) then
      api.nvim_buf_clear_namespace(bufnr, resin_ns, 0, -1)
    end
  end, timeout)
end

-- Ensure original config is not copied and `function` is sanitized
function M.fn_wrap_tbl(obj)
  return type(obj) == "function" and { obj } or vim.tbl_deep_extend("force", {}, obj)
end

function M.get_filetype_config(opts)
  opts = opts or {}
  local config = require("resin").config or {}
  local user_ft_config = config.filetype[opts.filetype] or {}
  local enable_filetype = vim.F.if_nil(opts.enable_filetype, config.enable_filetype or false)
  if enable_filetype then
    local exists, resin_ft_config = pcall(require, string.format("resin.ft.%s", opts.filetype))
    if exists then
      user_ft_config = vim.tbl_deep_extend("keep", user_ft_config, resin_ft_config)
    end
  end
  return user_ft_config
end

function M.get_tmux_sockets()
  local sockets = {}
  local sessions = Job:new({ command = "tmux", args = { "list-sessions", "-F", "#{session_name}" } }):sync()
  for _, session in ipairs(sessions) do
    local windows =
      Job:new({ command = "tmux", args = { "list-windows", "-F", "#{window_index} #{window_name}", "-t", session } })
        :sync()
    for _, window in ipairs(windows) do
      local window_substring = vim.split(window, " ")
      local window_index = table.remove(window_substring, 1)
      local window_name = table.concat(window_substring, " ")
      local panes = Job:new({
        command = "tmux",
        args = { "list-panes", "-F", "#{pane_index} #{pane_title}", "-t", session .. ":" .. window_index },
      }):sync()
      for _, pane in ipairs(panes) do
        local pane_substring = vim.split(pane, " ")
        local pane_index = table.remove(pane_substring, 1)
        local pane_title = table.concat(pane_substring, " ")
        table.insert(sockets, {
          session = session,
          window_index = window_index,
          window_name = window_name,
          pane_index = pane_index,
          pane_title = pane_title,
          name = string.format("%s:%s.%s", session, window_index, pane_index),
        })
      end
    end
  end
  return sockets
end

return M
