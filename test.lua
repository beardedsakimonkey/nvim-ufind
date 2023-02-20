--[[
     Run these tests with `:so`
--]]
package.loaded['ufind.query'] = nil
package.loaded['ufind.arg'] = nil
package.loaded['ufind.ansi'] = nil
package.loaded['ufind.util'] = nil  -- clear out transitive deps as well

local split_cmd = require'ufind.arg'.split_cmd_aux
local parse = require'ufind.ansi'.parse
local query = require'ufind.query'
local match = query.match
local find_last_newline = require'ufind.util'.find_last_newline
local fuzzy_match = require'ufind.fuzzy_match.default'

local function asserteq(a, b)
    assert(
        vim.deep_equal(a, b),
        string.format('Expected %s to equal %s', vim.inspect(a), vim.inspect(b))
    )
end

local pat = require'ufind.arg'.inject_empty_captures '^(.*)$'
local pat_colon = require'ufind.arg'.inject_empty_captures '^([^:]-):(.*)$'

asserteq(
    match({'x'}, {'x.lua', 'y.lua'}, pat, require'ufind.fuzzy_match.default'),
    {{index = 1, positions = {1}, score = 1}}
)

asserteq(
    match({'fil', 'foo'}, {'file.lua: print(foo)'}, pat_colon, fuzzy_match),
    {{index = 1, positions = {1, 2, 3, 17, 18, 19}, score = 12}}
)

asserteq(
    match({'lua$', 'a'}, {'file.lua: a', 'file.c: x'}, pat_colon, fuzzy_match),
    {{index = 1, positions = {11}, score = 1}}
)

asserteq(
    match({'', 'zxczxc'}, {'file: a', 'file: x'}, pat_colon, fuzzy_match),
    {}
)

asserteq(
    match({'', 'zxc'}, {'file: zxc', 'file: x'}, pat_colon, fuzzy_match),
    {{index = 1, positions = {7, 8, 9}, score = 5}}
)

asserteq(
    match({'', 'sub'}, {'file: s:sub()', 'file: x'}, pat_colon, fuzzy_match),
    {{index = 1, positions = {9, 10, 11}, score = 5}}
)

-- Exact match fails
asserteq(
    match({"'la"}, {'foo.lua', 'bar.lua'}, pat, fuzzy_match),
    {}
)

-- Exact match succeeds
asserteq(
    match({"'fo"}, {'foo.lua', 'bar.lua'}, pat, fuzzy_match),
    {{index = 1, positions = {}, score = 0}}
)

asserteq(split_cmd('rg -f'), {'rg', '-f'})
asserteq(split_cmd(' rg  -f '), {'rg', '-f'})
asserteq(split_cmd('rg -f x'), {'rg', '-f', 'x'})

asserteq(split_cmd([[rg -f "/Some path/"]]), {'rg', '-f', '/Some path/'})
asserteq(split_cmd([[rg -f '/Some path/']]), {'rg', '-f', '/Some path/'})
asserteq(split_cmd([[rg -f "/Some 'path'/"]]), {'rg', '-f', "/Some 'path'/"})

asserteq(parse({[[[35mtest:[mYo]]}), {'test:Yo'})
asserteq(parse({[[[01;31m[Kex[m[K =]]}), {'ex ='})
asserteq(
    parse({[[[0m[35mufind.lua[0m:[0m[32m25[0m: open({'~/[0m[1m[31mfoo[0m'})]]}),
    {"ufind.lua:25: open({'~/foo'})"}
)

asserteq(find_last_newline("aa\naa"), 3)
asserteq(find_last_newline("aaaa\n"), 5)
asserteq(find_last_newline("\na"), 1)
asserteq(find_last_newline("aaaa"), nil)

print('ok')
