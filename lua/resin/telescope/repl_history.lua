local api = vim.api
local utils = require "resin.utils"
local action_set = require "telescope.actions.set"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local entry_display = require "telescope.pickers.entry_display"
local tele_utils = require "telescope.utils"
local previewers = require "telescope.previewers.buffer_previewer"
local preview_utils = require "telescope.previewers.utils"

-- TODO: extract treesitter highlights for repl ordinal
local function history_previewer(opts)
  opts = opts or {}
  return previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      api.nvim_buf_set_lines(self.state.bufnr, 0, 0, false, entry.value.data)
      if entry.value.filetype then
        preview_utils.ts_highlighter(self.state.bufnr, entry.value.filetype)
      end
    end,
  }
end

local function history_entry_maker(opts)
  local path_display = vim.F.if_nil(opts.path_display, { ["tail"] = true })
  return function(entry)
    local displayer = entry_display.create {
      separator = " │ ",
      items = {
        { width = 15 },
        { width = 1 },
        { width = 10 },
        { remaining = true },
      },
    }

    local tail = tele_utils.transform_path({ path_display = path_display }, entry.filename)
    local time = os.date("%Y/%m/%d", entry.time)
    local string = table.concat(entry.data, " ")

    return {
      value = entry,
      display = function()
        local display, hl_group = tele_utils.transform_devicons(entry.filename, tail, false)
        if hl_group then
          -- telescope oddity: displayer handles formatting of each item in display; outer hl_group table is post-hoc highlighting
          return displayer {
            {
              display,
              function()
                return { { { 1, 3 }, hl_group } }
              end,
            },
            entry.active and { "R", "DiagnosticHint" } or { "D", "DiagnosticError" },
            { time, vim.F.if_nil("TelescopeResultsNumber", opts.date_hl) },
            string,
          }
        else
          return displayer {
            display,
            { time, vim.F.if_nil("TelescopeResultsNumber", opts.date_hl) },
            string,
          }
        end
      end,
      ordinal = tail .. " " .. time .. " " .. string,
    }
  end
end

return function(opts)
  opts = opts or {}
  opts.limit_filetype = vim.F.if_nil(opts.limit_filetype, true)
  opts.limit_file = vim.F.if_nil(opts.limit_file, false)

  local bufnr = api.nvim_get_current_buf()
  local sender = vim.F.if_nil(opts.sender, require("resin.api").get_sender(bufnr))
  local data = utils.parse_history(opts)

  pickers
    .new(opts, {
      prompt_title = "REPL history",
      finder = finders.new_table {
        results = data,
        entry_maker = vim.F.if_nil(opts.entry_maker, history_entry_maker(opts)),
      },
      previewer = history_previewer(opts),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        action_set.select:replace(function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local selections = current_picker:get_multi_selection()
          if vim.tbl_isempty(selections) then
            table.insert(selections, action_state.get_selected_entry())
          end
          actions.close(prompt_bufnr)
          local bufnames = {}
          for _, b in ipairs(api.nvim_list_bufs()) do
            if api.nvim_buf_is_loaded(b) then
              bufnames[api.nvim_buf_get_name(b)] = true
            end
          end
          for _, selection in ipairs(selections) do
            sender:send(selection.value.data, { history = bufnames[selection.value.filename] })
          end
        end)
        return true
      end,
    })
    :find()
end
