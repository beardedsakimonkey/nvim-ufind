local fuzzy_filter = require('ufind.fuzzy_filter')
local util = require('ufind.util')
local filter = fuzzy_filter.filter
local find_min_subsequence = util.find_min_subsequence

local function assert_eq(a, b)
    assert(
        vim.deep_equal(a, b),
        string.format("Expected %s to equal %s", vim.inspect(a), vim.inspect(b))
    )
end

assert_eq(
    find_min_subsequence('~/foo/bar/foo.txt', 'foo'),
    {11, 12, 13}
)

assert_eq(
    find_min_subsequence('~/foo/bar/frodo.txt', 'foo'),
    {3, 4, 5}
)

assert_eq(
    find_min_subsequence('~/foo/bar/frodo.txt', 'oof'),
    {4, 5, 11}
)

assert_eq(
    find_min_subsequence('~/foo/bar/frodo.txt', 'to'),
    {}
)

assert_eq(
    filter({"x"}, {"x.lua", "y.lua"}),
    {{index = 1, positions = {1}, score = 0}}
)

assert_eq(
    filter({"fil", "foo"}, {"file.lua: print(foo)"}, ":"),
    {{index = 1, positions = {1, 2, 3, 17, 18, 19}, score = 0}}
)

print("ok")
