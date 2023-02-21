-- Non-fuzzy, smart-case matcher. Useful for filtering grep results.
local function match_exact(str, query)
    local has_upper = query:lower() ~= query
    if not has_upper then  -- do case-insensitive search
        str = str:lower()
    end
    local starti, endi = str:find(query, 1, true)
    if not starti then
        return nil
    end
    local positions = {}
    for i = starti, endi do
        table.insert(positions, i)
    end
    return positions, 1
end

return match_exact
