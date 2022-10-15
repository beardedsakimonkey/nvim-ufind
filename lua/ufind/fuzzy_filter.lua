local util = require('ufind.util')

local function calc_score(positions, str)
    local tail = str:find('[^/]+/?$')
    local score = 0
    local prev_pos = -1
    for _, pos in ipairs(positions) do
        if pos == prev_pos + 1 then score = score + 1 end -- consecutive char
        if tail and pos >= tail then score = score + 1 end -- path tail
        prev_pos = pos
    end
    return score
end

local function fuzzy_match(str, queries)
    if not str or #str == 0 or vim.tbl_isempty(queries) then return nil end
    str = str:lower()
    local positions = {}
    for _, q in ipairs(queries) do
        q.term = q.term:lower()
        if q.prefix and q.suffix then
            local match = str == q.term
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.prefix then
            local match = vim.startswith(str, q.term)
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.suffix then
            local match = vim.endswith(str, q.term)
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.invert then
            if str:find(q.term, 1, true) then return nil end
        else
            for _, v in ipairs(util.find_min_subsequence(str, q.term)) do
                table.insert(positions, v)
            end
        end
    end
    if vim.tbl_isempty(positions) then
        return nil
    else
        table.sort(positions) -- For calculating consecutive char bonus
        return positions, calc_score(positions, str)
    end
end

local function parse_query(query_part)
    local invert, prefix, suffix = false, false, false
    local ts, te = 1, -1 -- Start/end indices of the search term
    if query_part:sub(ts, ts) == '!' then
        ts = ts + 1
        invert = true
    end
    if query_part:sub(ts, ts) == '^' then
        ts = ts + 1
        prefix = true
    end
    if query_part:sub(te) == '$' then
        te = te - 1
        suffix = true
    end
    local term = query_part:sub(ts, te)
    return term and {
        invert = invert, -- !
        prefix = prefix, -- ^
        suffix = suffix, -- $
        term = term,
    } or nil
end

local function sort_queries(queries)
    table.sort(queries, function(a, b)
        if a.prefix ~= b.prefix then return a.prefix     -- Prefix queries come first
        elseif a.suffix ~= b.suffix then return a.suffix -- Then suffix queries
        elseif a.invert ~= b.invert then return a.invert -- Then inverted queries
        else return #a.term < #b.term end                -- Then shorter queries
    end)
end

local function filter(raw_queries, lines, delimiter)
    local matches = {}
    -- Parse queries
    local query_sets = vim.tbl_map(function(raw_query)
        local query_set = {}
        for query_part in vim.gsplit(raw_query, " +") do
            table.insert(query_set, parse_query(query_part)) -- Inserting `nil` no-ops
        end
        return query_set
    end, raw_queries)
    -- Sort queries for performance
    for _, queries in ipairs(query_sets) do
        sort_queries(queries)
    end
    for i, line in ipairs(lines) do
        local j = 1
        local match = {index = i, positions = {}, score = 0}
        for line_part, start in util.gsplit(line, delimiter or '$', false) do
            local positions, score = fuzzy_match(line_part, query_sets[j])
            if positions then
                -- Adjust positions
                for _, pos in ipairs(positions) do
                    table.insert(match.positions, start-1+pos)
                end
                match.score = match.score + score
            end
            j = j + 1
        end
        if not vim.tbl_isempty(match.positions) then
            table.insert(matches, match)
        end
    end
    return matches
end

return {filter = filter}
