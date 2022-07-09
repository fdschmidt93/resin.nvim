# resin.nvim: SLIME :heart: treesitter

`resin.nvim` is a minimal **work-in-progress** (alpha stage not ready for general adoption) send-to-repl plugin that, unlike many comparable plugins, leverages neovim's native textobjects (incl. treesitter!).

# Motivation & Philosophy

* native
* minimalistic
* customizability

Many REPL plugins manually extract text as opposed to levering neovim's native textobjects, which limits flexibility while actually increasing complexity. Furthermore, managing receivers is often overly tied to plugin logic. `resin.nvim` handles both aspects in a minimalistic design, as it is a **library** that primarily handles sending to a repl ("receiver"). In doing so, it enables maximum customization through hooks into sending & receiving text and leaving REPL management entirely to the user.

# Teaser

The plugin currently is in very early stages and not ready yet for general adoption. The below GIFs tease some of its features.

## Use textobjects to send-to-repl

`<C-c>` is the default prefix to send to a REPL. The GIF shows send inside parentheses(`i(`), send line (`V<C-c>`), send outside function (`<C-c>af`) and and early version of REPL history telescope picker.

![Leveraging textobjects to send-to-repl](https://user-images.githubusercontent.com/39233597/178100976-dc1c1b60-23a8-443f-9f4d-0671dcfe763e.gif)

## Lever telescope to repeat send-to-repl fast

1. Sending the selected entry to the REPL
2. Sending multi-selections in order to the REPL
3. Telescope resume to repeat 2.

![Leveraging telescope to repeat send-to-repl fast](https://user-images.githubusercontent.com/39233597/178101000-e99a5748-07ea-4611-b857-51d78fc30e88.gif)


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

- [x] `telescope.nvim` integration (history of send-to-repl, multi-select history to send to repl again)
- [ ] Documentation
- [ ] Utilities for receiver management
- [ ] Suppport `tmux` as an extra receiver
- [ ] Maybe block-mode support

# Credits

* This plugin is largely inspired by the fantastic [vim-slime](https://github.com/jpalardy/vim-slime). `vim-slime` also inspires the name, as resin can be thought of trees(itter) `slime` ;)
