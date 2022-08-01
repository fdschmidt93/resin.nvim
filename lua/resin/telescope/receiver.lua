local api = vim.api
local action_set = require "telescope.actions.set"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local previewers = require "telescope.previewers.buffer_previewer"
local resin = require "resin"
local utils = require "resin.utils"
local resin_make_entry = require "resin.telescope.make_entry"
local resin_previewers = require "resin.telescope.previewers"

local preview_from_entry = function(opts)
  opts = opts or {}
  return previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      entry.value.preview_function(entry.value, self.state.bufnr)
    end,
  }
end

local get_neovim_terminals = function()
  local buffers = vim.tbl_filter(function(chan)
    return chan.mode == "terminal" and chan.stream == "job"
  end, vim.api.nvim_list_chans())
  for _, b in ipairs(buffers) do
    b.name = api.nvim_buf_get_name(b.buffer)
    b.preview_function = resin_previewers.neovim_terminal
    b.entry_maker = resin_make_entry.neovim_terminal
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
  opts.bufnr = vim.F.if_nil(opts.bufnr, api.nvim_get_current_buf())
  local sender = resin.get_sender(opts.bufnr)

  local receivers = {}
  local terminals = get_neovim_terminals()
  for _, v in ipairs(terminals) do
    table.insert(receivers, v)
  end
  local tmux_panes = {}
  if vim.fn.executable "tmux" == 1 then
    for _, pane in ipairs(utils.get_tmux_sockets()) do
      pane.preview_function = resin_previewers.tmux
      pane.entry_maker = resin_make_entry.tmux
      pane.return_receiver = function(self)
        local tmux = require "resin.receiver.tmux"
        return tmux {
          socket = { session = self.session, window = self.window_index, pane = self.pane_index },
        }
      end
      table.insert(tmux_panes, pane)
    end
  end
  for _, v in ipairs(tmux_panes) do
    table.insert(receivers, v)
  end
  if vim.tbl_isempty(receivers) then
    vim.notify("No receivers available.", vim.log.levels.INFO, { title = "resin.telescope.receivers" })
    return
  end
  pickers
      .new(opts, {
        prompt_title = "Available Receivers",
        finder = finders.new_table {
          results = receivers,
          entry_maker = entry_maker,
        },
        previewer = preview_from_entry(opts),
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
