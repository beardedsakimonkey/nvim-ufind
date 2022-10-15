local util = require('ufind.util')

-- TODO: give bonus to consecutive chars and start of word.
local function calc_score(_positions, _text)
    return 0
end

local function fuzzy_match(text, queries)
    if not text or #text == 0 or vim.tbl_isempty(queries) then return nil end
    local fuzzy_query = nil
    for _, query in ipairs(queries) do
        if query.prefix then
            local has_match = vim.startswith(text, query.term)
            if not query.invert and not has_match then return nil end
            if query.invert and has_match then return nil end
        end
        if query.suffix then
            local has_match = vim.endswith(text, query.term)
            if not query.invert and not has_match then return nil end
            if query.invert and has_match then return nil end
        end
        if query.invert and not query.prefix and not query.suffix then
            local has_match = text:find(query.term, 1, true)
            if has_match then return nil end
        end
        if not query.invert and not query.prefix and not query.suffix then
            fuzzy_query = query.term
        end
    end
    local positions = util.find_min_subsequence(text:lower(), fuzzy_query:lower())
    if vim.tbl_isempty(positions) then
        return nil
    else
        return positions, calc_score(positions, text)
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
