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
  - Customizable display of results
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
  - [ ] ansi parsing for `open`?
  - [x] implement exact match query syntax
  - [ ] implement OR query syntax?
  - [ ] documentation

Usage
-----
```lua
require'ufind'.open({'~/foo', '~/bar'})

-- using a custom data structure
require'ufind'.open({{path='/home/blah/foo', label='foo'}},
                    { get_value = function(item)
                        return item.label
                      end,
                      on_complete = function(cmd, item)
                        vim.cmd(cmd .. item.path)
                      end })
```

Copyright
---------
MIT License
