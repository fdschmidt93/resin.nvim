# resin.nvim: SLIME :heart: treesitter

`resin.nvim` is a minimal work-in-progress send-to-repl plugin that, unlike many comparable plugins, leverages neovim's native textobjects (incl. treesitter!).

# Motivation & Philosophy

* native
* minimalistic
* customizability

Many REPL plugins manually extract text as opposed to levering neovim's native textobjects, which limits flexibility while actually increasing complexity. Furthermore, managing receivers is often overly tied to plugin logic. `resin.nvim` handles both aspects in a minimalistic design, as it is a **library** that primarily handles sending to a repl ("receiver"). In doing so, it enables maximum customization through hooks into sending & receiving text and leaving REPL management entirely to the user.

# Setup

For very early adopters, here's an example of how I (currently) manage my REPL for `python`. Whenever I first enter a python file, a hidden terminal buffer with `ipython` in the corresponding `conda` environment is already launched. The below setup function makes sure, that for the (single) terminal buffer, each `python` buffer will send to that terminal buffer.

```lua
require("resin").setup {
  filetype = {
    python = {
    -- A receiver is set up for each sender
      setup_receiver = function(sender)
        local bufnr = vim.tbl_filter(function(b)
          return vim.bo[b].buftype == "terminal"
        end, vim.api.nvim_list_bufs())
        if #bufnr > 1 then
          print "Too many terminals open"
          return
        end
        if bufnr then
          bufnr = bufnr[1]
          return require "resin.receiver.neovim_terminal" {
            chan = vim.b[bufnr].terminal_job_id,
            filetype = sender.filetype,
          }
        end
      end,
    },
  },
}

```
# Usage

By default, `resin.nvim` like `vim-slime` maps `<C-c>` in `{n, x}` modes to send to your set up REPL. You can then leverage any kind of text object to send to the repl, for instance, `<C-c>ip` for sending the currently selected paragraph, `V<C-c>` for sending the current line. This principle seamlessly extends to [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) though key chords depend on your setup.

# TODO

- [ ] Documentation
- [ ] `telescope.nvim` integration (history of send-to-repl, multi-select history to send to repl again)
- [ ] (only!) utilities for receiver management
- [ ] Suppport `tmux` as an extra receiver
- [ ] Maybe block-mode support

# Credits

* This plugin is largely inspired by the fantastic [vim-slime](https://github.com/jpalardy/vim-slime). `vim-slime` also inspires the name, as resin can be thought of trees(itter) `slime` ;)
