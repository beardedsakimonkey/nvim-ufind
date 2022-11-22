-- Helper functions for preprocessing user-provided arguments

local function inject_empty_captures(pat)
    local n = 0  -- number of captures found
    local sub = pat:gsub('%%?%b()', function(match)
        -- TODO: we shouldn't inject for [(]%)
        if vim.endswith(match, '()') or  -- (), %b()
            vim.startswith(match, '%(') then  -- %(
            return
        end
        n = n + 1
        return '()' .. match
    end)
    assert(n ~= 0, ('Expected at least one capture in pattern %q'):format(pat))
    return sub, n
end


return {
    inject_empty_captures = inject_empty_captures,
}
