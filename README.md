# resin.nvim: SLIME :heart: treesitter

`resin.nvim` is a send-to-repl plugin leveraging neovim's native operator motions.
The primary motivation is to "modernize" the excellent vim-slime.


# Core Features

Core features of `resin.nvim` are:

1. Lever operators (incl. treesitter objects) to send-to-repl
2. `on_{before, after}_{send, receive}` hooks for user functions and filetype customization
3. Leverage vim.ui.select or telescope to attach a one or many `receivers` (neovim terminal, tmux panes)
4. History module to enable non-sequential sending of history powered by `vim.ui.select` or `telescope.nvim`
5. Highlighting of sent text

# Installation

```lua
use {
  'fdschmidt93/resin.nvim'
  requires = { 
  {'nvim-lua/plenary.nvim'} -- strict dependency
  {'nvim-telescope/telescope.nvim'} -- recommended finder
  }
}
```
`telescope.nvim` is the preferred fuzzy finder as `resin.nvim` leverages custom `entry_maker`s and `previewer`s to significantly enhance attaching receivers and sending history.

# Usage

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
      setup_receiver = function()
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
            bufnr = bufnr,
          }
        end
      end,
    },
  }
}
```
## Filetype configuration

For some filetypes, send-to-repl needs to be sanitized. One more involved example is the `ipython` repl, which is the current Python default.

```lua
-- lua/resin/ft/python.lua
return {
  on_before_receive = function(receiver)
    receiver:receiver_fn { "%cpaste -q" } -- sending ipython header
    vim.wait(50) -- waiting required
  end,
  on_after_receive = function(receiver)
    receiver:receiver_fn { "--" } -- sending ipython tail
  end,
}
```

# Usage

By default, `resin.nvim` like `vim-slime` maps `<C-c>` in `{n, x}` modes to send to your set up REPL. You can then leverage any kind of text object to send to the repl, for instance, `<C-c>ip` for sending the currently selected paragraph, `V<C-c>` for sending the current line. This principle seamlessly extends to [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) though key chords depend on your setup.

# TODO

- [x] `telescope.nvim` integration (history of send-to-repl, multi-select history to send to repl again)
- [x] Suppport `tmux` as an extra receiver
- [x] Utilities for receiver management
- [ ] Documentation: 
- [ ] Maybe block-mode support

# Contributing

Please consider a PR (esp. for sensible filetype defaults!) as opposed to raising an issue. The core logic (send-to-repl) is comparably simple with primary complexity stemming from enhancing UX and UI with history modules and selection interfaces.

# Credits

* This plugin is largely inspired by the fantastic [vim-slime](https://github.com/jpalardy/vim-slime). `vim-slime` also inspires the name, as resin can be thought of trees(itter) `slime` ;)

