local a = vim.api
local action_set = require "telescope.actions.set"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local entry_display = require "telescope.pickers.entry_display"
local previewers = require "telescope.previewers.buffer_previewer"
local resin = require "resin"
local Job = require "plenary.job"
local utils = require "resin.utils"

local last_non_empty_line = function(lines)
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line ~= "" then
      return line
    end
  end
  return ""
end

local NAME_WIDTH = 25

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
      self.name,
    },
  })
end

local function tmux_entry_maker(entry)
  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 4 },
      { width = 1 },
      { width = NAME_WIDTH },
      { remaining = true },
    },
  }
  return {
    value = entry,
    display = function()
      -- telescope oddity: displayer handles formatting of each item in display; outer hl_group table is post-hoc highlighting
      return displayer {
        "tmux",
        { vim.F.if_nil(entry.priority, "-"), "TelescopeResultsVariable" },
        { entry.name, "TelescopeResultsNumber" },
        { entry.pane_title, "Title" },
      }
    end,
    ordinal = "tmux" .. " " .. entry.name .. " " .. entry.pane_title,
  }
end

local previewer = function(opts)
  opts = opts or {}
  return previewers.new_buffer_previewer {
    define_preview = function(self, entry)
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
      { width = 1 },
      { width = NAME_WIDTH },
      { remaining = true },
    },
  }
  return {
    value = entry,
    display = function()
      -- telescope oddity: displayer handles formatting of each item in display; outer hl_group table is post-hoc highlighting
      return displayer {
        "nvim",
        { vim.F.if_nil(entry.priority, "-"), "TelescopeResultsVariable" },
        { entry.buffer, "TelescopeResultsNumber" },
        { entry.name, "Title" },
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
    b.name = a.nvim_buf_get_name(b.buffer)
    b.preview_function = preview_terminal
    b.entry_maker = buffer_entry_maker
    b.return_receiver = function(self)
      local nvim = require "resin.receiver.neovim_terminal"
      return nvim { bufnr = self.buffer }
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
  local tmux_panes = {}
  for _, pane in ipairs(utils.get_tmux_sockets()) do
    pane.preview_function = preview_tmux
    pane.entry_maker = tmux_entry_maker
    pane.return_receiver = function(self)
      local tmux = require "resin.receiver.tmux"
      return tmux {
        socket = { session = self.session, window = self.window_index, pane = self.pane_index },
      }
    end
    table.insert(tmux_panes, pane)
  end
  for _, v in ipairs(terminals) do
    table.insert(data, v)
  end
  for _, v in ipairs(tmux_panes) do
    table.insert(data, v)
  end
  pickers
    .new(opts, {
      prompt_title = "Available Receivers",
      finder = finders.new_table {
        results = data,
        entry_maker = entry_maker,
      },
      previewer = previewer(opts),
      sorter = conf.file_sorter(opts),
      on_complete = {
        function(current_picker)
          local receivers = {}
          for _, receiver in ipairs(sender.receivers) do
            receivers[tostring(receiver)] = receiver
          end
          if not vim.tbl_isempty(receivers) then
            local priority = 1
            for entry in current_picker.manager:iter() do
              if receivers[entry.value.name] then
                entry.value.priority = priority
                current_picker._multi:toggle(entry)
                priority = priority + 1
              end
            end
          end
          current_picker:clear_completion_callbacks()
          current_picker:refresh()
        end,
      },
      attach_mappings = function(prompt_bufnr)
        local set_receivers = function()
          local receivers = require("resin.state").get_receivers()
          sender:remove_receiver()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local selections = current_picker:get_multi_selection()
          if vim.tbl_isempty(selections) then
            table.insert(selections, action_state.get_selected_entry())
          end
          -- clear multi-selections to not re-replace close
          actions.drop_all(prompt_bufnr)
          actions.close(prompt_bufnr)
          for _, selection in ipairs(selections) do
            local receiver = receivers[selection.value.name]
            if not receiver then
              receiver = selection.value:return_receiver()
            end
            sender:add_receiver(receiver)
          end
        end
        action_set.select:replace(set_receivers)

        -- if a value has (a) priority, (un-)set it
        -- update priorities of other selections
        -- incrementally update row depending on where it may be after selection
        -- leverage completion callback to return to original row after refresh (required for redraw)
        local selected_entry
        local priority
        local row
        actions.toggle_selection:enhance {
          pre = function()
            selected_entry = action_state.get_selected_entry()
            priority = selected_entry.value.priority
          end,
          post = function()
            local current_picker = action_state.get_current_picker(prompt_bufnr)
            local selections = current_picker:get_multi_selection()
            if not selected_entry.value.priority then
              selected_entry.value.priority = #selections
            else
              priority = selected_entry.value.priority
              selected_entry.value.priority = nil
              for _, selection in ipairs(selections) do
                if priority < selection.value.priority then
                  selection.value.priority = selection.value.priority - 1
                end
              end
            end
            local fn_index = #current_picker._completion_callbacks
            row = current_picker:get_selection_row()
            current_picker:register_completion_callback(function(self)
              current_picker:set_selection(row)
              self:set_selection(row)
              table.remove(self._completion_callbacks, fn_index)
            end)
            current_picker:refresh()
          end,
        }
        -- update where row goes after selection appropriately
        actions.move_selection_worse:enhance {
          post = function()
            local current_picker = action_state.get_current_picker(prompt_bufnr)
            row = current_picker:get_selection_row()
          end,
        }
        actions.move_selection_better:enhance {
          post = function()
            local current_picker = action_state.get_current_picker(prompt_bufnr)
            row = current_picker:get_selection_row()
          end,
        }
        return true
      end,
    })
    :find()
end
