local api = vim.api
local Job = require "plenary.job"
local conf = require("telescope.config").values

local last_non_empty_line = function(lines)
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line ~= "" then
      return line
    end
  end
  return ""
end

local M = {}

M.neovim_terminal = function(self, bufnr)
  api.nvim_buf_set_lines(bufnr, 0, 0, false, api.nvim_buf_get_lines(self.buffer, 0, -1, false))
end

---@param job_opts table: see plenary.job opts table
--- - Note: `on_{stdout, exit}` are carefully tuned default functions to preview output & typically not to be overridden
---@field timeout number: preview blocks at most for `timeout` milliseconds (default: defaults.preview.timeout)
M.term_buffer = function(bufnr, job_opts)
  -- TODO upstream function to telescope
  local timeout = vim.F.if_nil(job_opts.timeout, conf.preview.timeout or 250)
  local chan = api.nvim_open_term(bufnr, {})
  local job_lines = {}
  job_opts = vim.tbl_extend("keep", job_opts, {
    on_stdout = vim.schedule_wrap(function(_, line, _)
      table.insert(job_lines, line)
    end),
    on_exit = vim.schedule_wrap(function()
      -- pcall as smashing/exiting might result into invalid channel
      local ok = pcall(api.nvim_chan_send, chan, table.concat(job_lines, "\r\n"))
      local line
      if ok then
        -- need to gsub ansi codes
        -- creds to https://stackoverflow.com/questions/48948630/lua-ansi-escapes-patternk
        line = last_non_empty_line(job_lines):gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
      end
      -- chan_send is practically async, we have to await completion
      -- until we can scroll buffer to top
      vim.wait(timeout, function()
        -- open_term results in bufnr having some empty last lines (seemingly non-deterministic number)
        -- fetch second to last line and check against command output
        local last_line
        if api.nvim_buf_is_valid(bufnr) then
          last_line = last_non_empty_line(api.nvim_buf_get_lines(bufnr, 0, -1, false))
        end
        if last_line == line then -- manually verified check passed frequently
          return true
        end
      end, 5, false)
      api.nvim_buf_call(bufnr, function()
        vim.cmd [[ normal! gg ]]
      end)
    end),
  })
  Job:new(job_opts):start()
end

M.tmux = function(self, bufnr)
  M.term_buffer(bufnr, {
    command = "tmux",
    args = {
      "capture-pane",
      "-ep",
      "-t",
      self.name,
    },
  })
end

return M
