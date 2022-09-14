local os_sep = require("plenary.path").path.sep
local resin_api = require "resin.api"

---@tag resin.nvim
---@config { ["name"] = "INTRODUCTION" }
---@brief [[
---
--- resin.nvim is a send-to-repl plugin leveraging neovim's native textobjects.
--- The primary motivation is to "modernize" the excellent vim-slime.
---
--- Core features of resin.nvim are:
---     1. Use operators (incl. treesitter objects) to send-to-repl
---     2. Hook functionality based on user functions and filetype configuration
---     3. Leverage vim.ui.select or telescope to select a single or multiple receivers
---     4. History module to enable non-sequential sending of history powered by telescope
---     5. Highlighting of sent text
--- 
--- A key non-goal is to manage tie in receiver set up into |resin.nvim|, that is the
--- plugin provides utilities to attach a receiver, but not to manage the receiver itself, such
--- as launching commands etc. This is left entirely, on purpose, to the user.
---
--- An exemplary python configuration may look like the following:<br>
---     - The function below tries to find a terminal buf upon |resin.send| for python buffers<br>
---     - This can be paired with a filetype autocmd to automatically open an unlisted terminal buffer<br>
---
--- <code>
--- require("resin").setup {
---   history = {
---     path = vim.env.HOME .. "/.local/share/nvim/resin_history.json",
---     limit = 10,
---   },
---   filetype = {
---     python = {
---       setup_receiver = function()
---         local bufnr = vim.tbl_filter(function(b)
---           return vim.bo[b].buftype == "terminal"
---         end, vim.api.nvim_list_bufs())
---         if #bufnr > 1 then
---           vim.notify("Too many terminals open", vim.log.levels.INFO, { title = "resin.nvim" })
---           return
---         end
---         if bufnr then
---           bufnr = bufnr[1]
---           return require "resin.receiver.neovim_terminal" {
---             bufnr = bufnr,
---           }
---         end
---       end,
---     },
---   },
--- }
--- </code>
---
---@brief ]]

local resin = {}

resin.config = {
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
  enable_filetype = true,
  filetype = {},
}

--- Configure |resin.nvim|. Note some flags denote tables with further configuration.
--- - history:
---     - path string: where to store `resin_history.json` (default: $XDG_STATE_HOME/nvim/resin_history.json)
---     - limit number: store last `limit` entries
---     - save_on_exit boolean: synchronize extmarks as text on exit
--- - highlight:
---     - timeout number: remove highlighting after `timeout` ms (default: 200)
---     - group string: group to highlight sent region (default: "IncSearch")
--- - hooks:
---     - on_before_send function|table: (table of) function(s) that affects ALL send text and history
---     - on_after_send function|table: (table of) function(s) for your needs after sending
---     - on_before_receive function|table: (table of) function(s) that affects ALL send text but not history
---     - on_after_receive function|table: (table of) function(s) for your needs after receiving
--- - filetype:
---     - Comprises "filetype" tables (e.g. filetype { python = { ... } } with below elements
---     - hooks (as per above)
---     - setup_receiver function: attach receiver to sender with function, re-executed if receiver ceases to exist
---
---@param opts table: options to pass to |resin.nvim| setup
---@field history table|booealn: false to deactivate, see history defaults above
---@field highlight table|boolean: false to deactivate, see highlight defaults above
---@field filetype table: see filetype above
---@field default_mappings boolean: setup default mappings
resin.setup = function(opts)
  resin.config = vim.tbl_deep_extend("force", resin.config, opts)
  if resin.config.default_mappings then
    vim.keymap.set({ "n", "x" }, "<C-c><C-c>", function()
      require("resin.api").send {}
    end, { desc = "resin.nvim: send-operator-to-repl" })
    vim.keymap.set({ "n" }, "<C-c><C-h>", function()
      require("resin.api").send_history {}
    end, { desc = "resin.nvim: send-history-to-repl" })
    vim.keymap.set({ "n" }, "<C-c>v", function()
      require("resin.api").select_receiver {}
    end, { desc = "resin.nvim: select-repl" })
    vim.keymap.set({ "n" }, "<C-c>h", function()
      require("resin.api").select_history {}
    end, { desc = "resin.nvim: select-send-history-to-repl" })
  end
  if resin.config.history.save_on_exit then
    vim.api.nvim_create_autocmd("VimLeave", {
      callback = function()
        local resin_extmarks = require "resin.extmarks"
        -- history was changed
        if not vim.tbl_isempty(resin_extmarks._marks) then
          local resin_history = require "resin.history"
          local history = resin_history.read_history()
          resin_history.write(history, { convert = true })
        end
        vim.cmd [[redraw!]]
      end,
    })
  end
end

return resin
