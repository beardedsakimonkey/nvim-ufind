local fuzzy_filter = require('ufind.fuzzy_filter')
local util = require('ufind.util')
local filter = fuzzy_filter.filter
local find_min_subsequence = util.find_min_subsequence

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

asserteq(
    filter({'x'}, {'x.lua', 'y.lua'}, '$'),
    {{index = 1, positions = {1}, score = 1}}
)

asserteq(
    filter({'fil', 'foo'}, {'file.lua: print(foo)'}, ':'),
    {{index = 1, positions = {1, 2, 3, 17, 18, 19}, score = 10}}
)

asserteq(
    filter({'lua$', 'a'}, {'file.lua: a', 'file.c: x'}, ':'),
    {{index = 1, positions = {11}, score = 1}}
)

print('ok')
