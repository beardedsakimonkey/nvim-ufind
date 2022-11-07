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
  - [ ] `open` should take a command spec so the window opens immediately
  - [ ] multiselect
  - [ ] configurable layout
  - [ ] configurable mappings
  - [ ] expose more highlight groups
  - [ ] lua type annotations
  - [ ] ansi parsing for `open`?
  - [ ] implement exact match query syntax
  - [ ] implement OR query syntax?

Copyright
---------
MIT License
