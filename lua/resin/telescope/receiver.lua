local a = vim.api
local action_set = require "telescope.actions.set"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values
local finders = require "telescope.finders"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local history = require "resin.history"
local pfiletype = require "plenary.filetype"
local entry_display = require "telescope.pickers.entry_display"
local tele_utils = require "telescope.utils"
local previewers = require "telescope.previewers.buffer_previewer"
local preview_utils = require "telescope.previewers.utils"
local resin = require "resin"
local Job = require "plenary.job"

local last_non_empty_line = function(lines)
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line ~= "" then
      return line
    end
  end
  return ""
end

--- Move the selection to the previous entry
---@param job_opts table: see plenary.job opts table
--- - Note: `on_{stdout, exit}` are carefully tuned default functions to preview output & typically not to be overridden
---@field timeout number: preview blocks at most for `timeout` milliseconds (default: defaults.preview.timeout)
local buf_term_preview = function(bufnr, job_opts)
  local timeout = vim.F.if_nil(job_opts.timeout, conf.preview.timeout or 250)
  local chan = vim.api.nvim_open_term(bufnr, {})
  local job_lines = {}
  job_opts = vim.tbl_extend("keep", job_opts, {
    on_stdout = vim.schedule_wrap(function(_, line, _)
      table.insert(job_lines, line)
    end),
    on_exit = vim.schedule_wrap(function()
      -- pcall as smashing/exiting might result into invalid channel
      local ok = pcall(vim.api.nvim_chan_send, chan, table.concat(job_lines, "\r\n"))
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
        if vim.api.nvim_buf_is_valid(bufnr) then
          last_line = last_non_empty_line(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        end
        if last_line == line then -- manually verified check passed frequently
          return true
        end
      end, 5, false)
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd [[ normal! gg ]]
      end)
    end),
  })
  Job:new(job_opts):start()
end

local preview_tmux = function(self, bufnr)
  buf_term_preview(bufnr, {
    command = "tmux",
    args = {
      "capture-pane",
      "-ep",
      "-t",
      string.format("%s:%s.%s", self.session, self.window_index, self.pane_index),
    },
  })
end

local function tmux_entry_maker(entry)
  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 4 },
      { width = 10, right_justify = true },
      { remaining = true },
    },
  }
  local socket = string.format("%s:%s.%s", entry.session, entry.window_index, entry.pane_index)
  return {
    value = entry,
    display = function()
      -- telescope oddity: displayer handles formatting of each item in display; outer hl_group table is post-hoc highlighting
      return displayer {
        "tmux",
        { socket, "TelescopeResultsNumber" },
        entry.pane_title,
      }
    end,
    ordinal = "tmux" .. " " .. socket .. " " .. entry.pane_title,
  }
end

local function get_tmux_sockets(filetype)
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
          preview_function = preview_tmux,
          entry_maker = tmux_entry_maker,
          return_receiver = function(self)
            local tmux = require "resin.receiver.tmux"
            return tmux {
              socket = { session = self.session, window = self.window_index, pane = self.pane_index },
              filetype = filetype,
            }
          end,
        })
      end
    end
  end
  return sockets
end

local previewer = function(opts)
  opts = opts or {}
  return previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      -- require "telescope.log".warn(entry)
      entry.value.preview_function(entry.value, self.state.bufnr)
    end,
  }
end

local preview_terminal = function(self, bufnr)
  a.nvim_buf_set_lines(bufnr, 0, 0, false, a.nvim_buf_get_lines(self.buffer, 0, -1, false))
end

local function buffer_entry_maker(entry)
  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 4 },
      { width = 10, right_justify = true },
      { remaining = true },
    },
  }
  return {
    value = entry,
    display = function()
      -- telescope oddity: displayer handles formatting of each item in display; outer hl_group table is post-hoc highlighting
      return displayer {
        "nvim",
        { entry.buffer, "TelescopeResultsNumber" },
        table.concat(entry.argv, " "),
      }
    end,
    ordinal = "nvim" .. " " .. tostring(entry.bufnr) .. " " .. table.concat(entry.argv, " "),
  }
end

local get_neovim_terminals = function(filetype)
  local buffers = vim.tbl_filter(function(chan)
    return chan.mode == "terminal" and chan.stream == "job"
  end, vim.api.nvim_list_chans())
  for _, b in ipairs(buffers) do
    b.preview_function = preview_terminal
    b.entry_maker = buffer_entry_maker
    b.return_receiver = function(self)
      local nvim = require "resin.receiver.neovim_terminal"
      return nvim { bufnr = self.buffer, filetype = filetype }
    end
  end
  return buffers
end

local function entry_maker(entry)
  return entry:entry_maker()
end

return function(opts)
  opts = opts or {}
  opts.bufnr = vim.F.if_nil(opts.bufnr, a.nvim_get_current_buf())
  -- local sender = vim.F.if_nil(opts.sender, resin.get_sender(opts.bufnr))
  local sender = resin.get_sender(opts.bufnr)
  local filetype = vim.bo[opts.bufnr].filetype

  local data = {}
  local terminals = get_neovim_terminals(filetype)
  local tmux_panes = get_tmux_sockets(filetype)
  for _, v in ipairs(terminals) do
    table.insert(data, v)
  end
  for _, v in ipairs(tmux_panes) do
    table.insert(data, v)
  end
  pickers
    .new(opts, {
      prompt_title = "Receivers",
      finder = finders.new_table {
        results = data,
        entry_maker = entry_maker,
      },
      previewer = previewer(opts),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        action_set.select:replace(function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local selections = current_picker:get_multi_selection()
          if vim.tbl_isempty(selections) then
            table.insert(selections, action_state.get_selected_entry())
          end
          actions.close(prompt_bufnr)
          for _, selection in ipairs(selections) do
            sender:add_receiver(selection.value:return_receiver())
          end
        end)
        return true
      end,
    })
    :find()
end
