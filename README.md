ufind
=====

A simple finder plugin for neovim.

https://user-images.githubusercontent.com/54521218/206877185-454b8174-b16f-41c2-9cb8-5d389f8923d5.mov

Features
--------
  - Fuzzy filtering that's scoped to fields defined by a regex
    - e.g. `^([^:]-):%d+:(.*)$` enables querying against the filename and the line seperately in
      the output of a grep command.
  - fzf style query syntax
    - e.g. `.c$ !^foo 'bar baz`
  - ANSI escape code parsing
    - preserve color, bold, etc. of command output
  - Easy to debug
    - ~1k sloc, no coroutines, no dependencies

Non-features
------------
  - Rich feature set
    - no file previews, no icons
  - Lots of built-in sources
    - currently only `buffers` and `oldfiles` are provided
  - Lots of configuration options

API
---
Ufind provides just two functions:

```lua
---@param source string[] | string | fun():string,string[]?
---@param config UfindConfig?
require'ufind'.open(source, config)

---@param source string | fun(query: string):string,string[]?
---@param config UfindConfig?
require'ufind'.open_live(source, config)
```

### `open(source [, config])`

`open()` opens a finder window populated based on the `source` parameter, which can be an array of
strings (e.g. `{'~/foo', '~/bar'}`). You can also pass a string command as `source` to run a command
asynchronously (e.g. `'rg --vimgrep foo'`). The output of the command will be used to populate the
finder. In rare cases when you want more control over the argument breakdown of the command, you can
instead pass a function that returns the command name and an array of arguments (e.g. `function()
return 'rg', {'--vimgrep', 'foo'} end`).

Results in the finder window can be filtered using the same syntax as
[fzf](https://github.com/junegunn/fzf/#search-syntax). (Note: the OR operator is not yet supported).

### `open_live(source [, config])`

Typing a query in an `open_live()` window causes the command to be re-run. `open_live()` has a
nearly identical API as `open()`, except that `source` cannot be an array of strings (it must be a
command). In the case of a string command, the current query will be implicitly added as the last
argument (e.g. `'rg --vimgrep -- '`). If `source` is a function, the query will be passed in as a
parameter (e.g. `function(query) return 'rg', {'--vimgrep', '--', query} end`).

### `config`

Both `open()` and `open_live()` accept an optional `config` argument. They are identical except that
`scopes` is not supported by `open_live()`. The passed in `config` will be deep-merged with the
default config:

```lua
local default_config = {
    -- Called when selecting an item to open.
    ---@type fun(cmd: 'edit'|'split'|'vsplit'|'tabedit', lines: string[])
    on_complete = function(cmd, lines)
        for i, line in ipairs(lines) do
            if i == #lines then  -- open the file
                vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(line))
            else  -- create a buffer
                local buf = vim.fn.bufnr(line, true)
                vim.bo[buf].buflisted = true
            end
        end
    end,
    -- Returns custom highlight ranges to highlight the result line.
    ---@type fun(line: string): {col_start: number, col_end: number, hl_group: string}[]?
    get_highlights = nil,
    -- Lua pattern with capture groups that defines scopes that will be queried individually.
    scopes = '^(.*)$',
    -- Whether to parse ansi escape codes.
    ansi = false,
    -- Initial query to use when first opened.
    initial_query = '',
    -- Initial scope to use when first opened.
    initial_scope = 1,
    layout = {
        ---@type 'none'|'single'|'double'|'rounded'|'solid'|string[]
        border = 'none',
        height = 0.8,
        width = 0.7,
        input_on_top = true,
    },
    keymaps = {
        quit = '<Esc>',
        open = '<CR>',
        open_split = '<C-s>',
        open_vsplit = '<C-v>',
        open_tab = '<C-t>',
        up = {'<C-k>', '<Up>'},
        down = {'<C-j>', '<Down>'},
        page_up = {'<C-b>', '<PageUp>'},
        page_down = {'<C-f>', '<PageDown>'},
        home = '<Home>',
        ['end'] = '<End>',
        wheel_up = '<ScrollWheelUp>',
        wheel_down = '<ScrollWheelDown>',
        prev_scope = '<C-p>',
        next_scope = '<C-n>',
        toggle_select = '<Tab>',
        toggle_select_all = '<C-a>',
    },
}
```

### sources

For convenience, ufind also provides a few built-in sources.

#### `require'ufind.source.buffers'`

A function that returns an array of buffer names.  The buffers only include named, listed, existing
buffers, and excludes the current buffer. ([source code](./lua/ufind/source/buffers.lua))

#### `require'ufind.source.oldfiles'`

A function that returns an array of oldfiles. The list excludes oldfiles that are directories or
are wildignored. ([source code](./lua/ufind/source/oldfiles.lua))

Example configuration
---------------------
```lua
local ufind = require'ufind'

local function cfg(t)
    return vim.tbl_deep_extend('keep', t, {
        layout = { border = 'single' },
        keymaps = { open_vsplit = '<C-l>' },
    })
end

-- Buffers
vim.keymap.set('n', '<space>b', function()
    ufind.open(require'ufind.source.buffers'(), cfg{})
end)

-- Oldfiles
vim.keymap.set('n', '<space>o', function()
    ufind.open(require'ufind.source.oldfiles'(), cfg{})
end)

-- Live find (command is rerun every time query is changed)
vim.keymap.set('n', '<space>f', function()
    ufind.open_live('fd --color=always --type=file --', cfg{ansi = true})
end)

local function on_complete_grep(cmd, lines)
    for i, line in ipairs(lines) do
        local found, _, fname, linenr = line:find('^([^:]-):(%d+):')
        if found then
            if i == #lines then  -- edit the last file
                vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(fname) .. '|' .. linenr)
            else  -- create a buffer
                local buf = vim.fn.bufnr(fname, true)
                vim.bo[buf].buflisted = true
            end
        end
    end
end

-- Grep
vim.api.nvim_create_user_command('Grep', function(o)
    ufind.open('rg --vimgrep --no-column --fixed-strings --color=ansi -- ' .. o.args, cfg{
        scopes = '^([^:]-):%d+:(.*)$',
        ansi = true,
        on_complete = on_complete_grep,
    })
end, {nargs = '+'})

-- Live grep
vim.keymap.set('n', '<space>g', function()
    ufind.open_live('rg --vimgrep --no-column --fixed-strings --color=ansi -- ', cfg{
        ansi = true,
        on_complete = on_complete_grep,
    })
end)
```

Similar plugins
---------------
  - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
  - [telescope](https://github.com/nvim-telescope/telescope.nvim)
  - [snap](https://github.com/camspiers/snap)

Copyright
---------
MIT License
