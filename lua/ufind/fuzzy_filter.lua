local util = require('ufind.util')

-- TODO: Prioritize by # matches to tail length ratio
local function calc_score(positions, str)
    local tail = str:find('[^/]+/?$')
    local score = 0
    local prev_pos = -1
    for _, pos in ipairs(positions) do
        if pos == prev_pos + 1 then score = score + 1 end   -- consecutive char
        if tail and pos >= tail then score = score + 1 end  -- path tail
        prev_pos = pos
    end
    return score
end


-- Precondition: has queries
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
            local results = util.find_min_subsequence(str, q.term)
            if not results then return nil end
            for _, pos in ipairs(results) do
                table.insert(positions, pos)
            end
        end
    end
    -- Invariant: none of the matches failed
    table.sort(positions)  -- for calculating consecutive char bonus
    return positions, calc_score(positions, str)
end


local function parse_query(query_part)
    local invert, prefix, suffix = false, false, false
    local ts, te = 1, -1  -- term start/end
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
        invert = invert,  -- !
        prefix = prefix,  -- ^
        suffix = suffix,  -- $
        term = term,
    } or nil
end


local function sort_queries(queries)
    table.sort(queries, function(a, b)
        if a.prefix ~= b.prefix then return a.prefix      -- prefix queries come first
        elseif a.suffix ~= b.suffix then return a.suffix  -- then suffix queries
        elseif a.invert ~= b.invert then return a.invert  -- then inverted queries
        else return #a.term < #b.term end                 -- then shorter queries
    end)
end


local function parse_queries(raw_queries)
    local query_sets = vim.tbl_map(function(raw_query)
        if raw_query:match('^%s*$') then -- is empty
            return {}
        end
        local query_set = {}
        for query_part in vim.gsplit(raw_query, " +") do
            table.insert(query_set, parse_query(query_part))  -- inserting `nil` no-ops
        end
        return query_set
    end, raw_queries)
    -- Sort queries for performance
    for _, queries in ipairs(query_sets) do
        sort_queries(queries)
    end
    return query_sets
end


local function filter(raw_queries, lines, pattern)
    local query_sets = parse_queries(raw_queries)
    local res = {}

    local has_any_query = util.tbl_some(function(queries)
        return not vim.tbl_isempty(queries)
    end, query_sets)

    if not has_any_query then
        for i = 1, #lines do
            table.insert(res, {index = i, positions = {}, score = 0})
        end
        return res
    end

    for i, line in ipairs(lines) do
        local fail = false
        local pos = {}
        local score = 0
        local matches = util.pack(string.match(line, pattern))
        local j = 1
        for m = 1, #matches, 2 do  -- for each capture
            local cap_pos, cap = matches[m], matches[m+1]
            local query_set = query_sets[j]
            if query_set and not vim.tbl_isempty(query_set) then  -- has query
                local mpos, mscore = fuzzy_match(cap, query_set)
                if mpos then  -- match success
                    for _, mp in ipairs(mpos) do
                        table.insert(pos, cap_pos-1+mp)
                    end
                    score = score + mscore
                else
                    fail = true
                    break
                end
            end
            j = j + 1
        end
        if not fail then
            table.insert(res, {index = i, positions = pos, score = score})
        end
    end

    table.sort(res, function(a, b) return a.score > b.score end)
    return res
end

return {filter = filter}
