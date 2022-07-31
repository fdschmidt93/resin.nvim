local entry_display = require "telescope.pickers.entry_display"

local M = {}

local NAME_WIDTH = 25

function M.neovim_terminal(entry)
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

function M.tmux(entry)
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

return M
