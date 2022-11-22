local fuzzy_filter = require('ufind.fuzzy_filter')
local filter = fuzzy_filter.filter
local find_min_subsequence = fuzzy_filter._find_min_subsequence

local function asserteq(a, b)
    assert(
        vim.deep_equal(a, b),
        string.format('Expected %s to equal %s', vim.inspect(a), vim.inspect(b))
    )
end

asserteq(
    find_min_subsequence('~/foo/bar/foo.txt', 'foo'),
    {11, 12, 13}
)

asserteq(
    find_min_subsequence('~/foo/bar/frodo.txt', 'foo'),
    {3, 4, 5}
)

asserteq(
    find_min_subsequence('~/foo/bar/frodo.txt', 'oof'),
    {4, 5, 11}
)

asserteq(
    find_min_subsequence('~/foo/bar/frodo.txt', 'to'),
    nil
)

local pat = require'ufind.arg'.inject_empty_captures '^(.*)$'
local pat_colon = require'ufind.arg'.inject_empty_captures '^([^:]-):(.*)$'

asserteq(
    filter({'x'}, {'x.lua', 'y.lua'}, pat),
    {{index = 1, positions = {1}, score = 1}}
)

asserteq(
    filter({'fil', 'foo'}, {'file.lua: print(foo)'}, pat_colon),
    {{index = 1, positions = {1, 2, 3, 17, 18, 19}, score = 10}}
)

asserteq(
    filter({'lua$', 'a'}, {'file.lua: a', 'file.c: x'}, pat_colon),
    {{index = 1, positions = {11}, score = 1}}
)

asserteq(
    filter({'', 'zxczxc'}, {'file: a', 'file: x'}, pat_colon),
    {}
)

asserteq(
    filter({'', 'zxc'}, {'file: zxc', 'file: x'}, pat_colon),
    {{index = 1, positions = {7, 8, 9}, score = 5}}
)

asserteq(
    filter({'', 'sub'}, {'file: s:sub()', 'file: x'}, pat_colon),
    {{index = 1, positions = {9, 10, 11}, score = 5}}
)

-- Exact match fails
asserteq(
    filter({"'la"}, {'foo.lua', 'bar.lua'}, pat),
    {}
)

-- Exact match succeeds
asserteq(
    filter({"'fo"}, {'foo.lua', 'bar.lua'}, pat),
    {{index = 1, positions = {1, 2}, score = 3}}
)

print('ok')
