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

local function on_complete_grep(cmd, item)
  local found, _, fname, linenr = item:find('^([^:]-):(%d+):')
  if found then
    vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(fname) .. '|' .. linenr)
  end
end

-- Single-shot grep
local function grep(query)
  ufind.open('rg --vimgrep --no-column --fixed-strings --color=ansi --' .. query, {
    pattern = '^([^:]-):%d+:(.*)$',
    ansi = true,
    on_complete = on_complete_grep,
  })
end
vim.api.nvim_create_user_command('Grep', function(o) grep(o.args) end, {nargs = '+'})

-- Live grep (command is rerun every time query is changed)
local function live_grep()
  ufind.open_live('rg --vimgrep --no-column --fixed-strings --color=ansi -- ', {
    ansi = true,
    on_complete = on_complete_grep,
  })
end
vim.keymap.set('n', '<space>G', live_grep)

-- Live find using a string command (the query is implicitly added to the end)
local function find()
  ufind.open_live('fd --color=always --type=file --', {ansi = true})
end
vim.keymap.set('n', '<space>f', find)

-- Buffers (using a built-in helper)
local function buffers()
  ufind.open(require'ufind.source.buffers'())
end
vim.keymap.set('n', '<space>b', buffers)

-- Oldfiles (using a built-in helper)
local function oldfiles()
  ufind.open(require'ufind.source.oldfiles'())
end
vim.keymap.set('n', '<space>o', oldfiles)
```

Copyright
---------
MIT License
