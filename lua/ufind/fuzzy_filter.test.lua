local fuzzy_filter = require('ufind.fuzzy_filter')
local util = require('ufind.util')
local helpers = require('ufind.helpers')
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

local get_iter = function(line) return ipairs({line}) end
local get_iter_colon = function(line) return helpers.splitonce(line, ':') end

asserteq(
    filter({'x'}, {'x.lua', 'y.lua'}, get_iter),
    {{index = 1, positions = {1}, score = 1}}
)

asserteq(
    filter({'fil', 'foo'}, {'file.lua: print(foo)'}, get_iter_colon),
    {{index = 1, positions = {1, 2, 3, 17, 18, 19}, score = 10}}
)

asserteq(
    filter({'lua$', 'a'}, {'file.lua: a', 'file.c: x'}, get_iter_colon),
    {{index = 1, positions = {11}, score = 1}}
)

asserteq(
    filter({'', 'zxczxc'}, {'file: a', 'file: x'}, get_iter_colon),
    {}
)

asserteq(
    filter({'', 'zxc'}, {'file: zxc', 'file: x'}, get_iter_colon),
    {{index = 1, positions = {7, 8, 9}, score = 5}}
)

asserteq(
    filter({'', 'sub'}, {'file: s:sub()', 'file: x'}, get_iter_colon),
    {{index = 1, positions = {9, 10, 11}, score = 5}}
)

print('ok')
