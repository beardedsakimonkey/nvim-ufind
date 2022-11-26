ufind
=====

WIP

Features
--------
  - Fuzzy filtering that's scoped to fields defined by a regex
    - e.g. `^([^:]-):%d+:(.*)$` enables filtering against the filename and the line seperately in
      the output of a grep command.
  - fzf style query syntax
    - (e.g. `.c$ !^foo bar`)
  - ANSI escape code parsing
  - No dependencies, no C FFI code to compile
  - Fairly simple codebase (under 1k sloc)

TODO
----
  - [x] `open` should take a command spec so the window opens immediately
  - [ ] multiselect
  - [x] configurable layout
  - [x] configurable mappings
  - [x] expose more highlight groups
  - [x] lua type annotations
  - [x] ansi parsing for `open`?
  - [x] implement exact match query syntax
  - [ ] implement OR query syntax?
  - [ ] documentation

Example config
--------------
```lua
local ufind = require'ufind'

local function cfg(t)
  return vim.tbl_deep_extend('keep', t or {}, {
    layout = { border = 'single' },
    keymaps = { open_vsplit = '<C-l>' },
  })
end

local function on_complete_grep(cmd, line)
  local found, _, fname, linenr = line:find('^([^:]-):(%d+):')
  if found then
    vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(fname) .. '|' .. linenr)
  end
end

-- Grep
local function grep(query)
  ufind.open('rg --vimgrep --no-column --fixed-strings --color=ansi -- ' .. query, cfg{
    pattern = '^([^:]-):%d+:(.*)$',  -- enables scoped filtering
    ansi = true,
    on_complete = on_complete_grep,
  })
end
vim.api.nvim_create_user_command('Grep', function(o) grep(o.args) end, {nargs = '+'})

-- Live grep (command is rerun every time query is changed)
local function live_grep()
  ufind.open_live('rg --vimgrep --no-column --fixed-strings --color=ansi -- ', cfg{
    ansi = true,
    on_complete = on_complete_grep,
  })
end
vim.keymap.set('n', '<space>g', live_grep)

-- Live find
local function find()
  ufind.open_live('fd --color=always --type=file --', cfg{ansi = true})
end
vim.keymap.set('n', '<space>f', find)

-- Buffers (using a built-in helper)
local function buffers()
  ufind.open(require'ufind.source.buffers'(), cfg{})
end
vim.keymap.set('n', '<space>b', buffers)

-- Oldfiles
local function oldfiles()
  ufind.open(require'ufind.source.oldfiles'(), cfg{})
end
vim.keymap.set('n', '<space>o', oldfiles)
```

Copyright
---------
MIT License
