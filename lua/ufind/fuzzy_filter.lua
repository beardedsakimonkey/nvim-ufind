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

-- precondition: has queries
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
    -- invariant: none of the matches failed
    table.sort(positions) -- For calculating consecutive char bonus
    return positions, calc_score(positions, str)
end

local function parse_query(query_part)
    local invert, prefix, suffix = false, false, false
    local ts, te = 1, -1 -- Term start/end
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

local function parse_queries(raw_queries)
    local query_sets = vim.tbl_map(function(raw_query)
        if raw_query:match('^%s*$') then -- is empty
            return {}
        end
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
    return query_sets
end

local function filter(raw_queries, lines, delimiter)
    local query_sets = parse_queries(raw_queries)

    local has_any_query = util.tbl_some(function(queries)
        return not vim.tbl_isempty(queries)
    end, query_sets)

    local num_groups = 1
    local matches = {}

    for i, line in ipairs(lines) do
        local j = 1
        if not has_any_query then
            table.insert(matches, {index = i, positions = {}, score = 0})
            for _, _ in util.gsplit(line, delimiter, false) do
                num_groups = math.max(j, num_groups)
                j = j + 1
            end
        else -- Has at least one query
            local match_success = true
            local positions = {}
            local score = 0
            for line_part, start in util.gsplit(line, delimiter, false) do
                num_groups = math.max(j, num_groups)
                local query_set = query_sets[j]
                if query_set and not vim.tbl_isempty(query_set) then -- Has query
                    local results, score1 = fuzzy_match(line_part, query_set)
                    if results then
                        -- Append adjusted positions
                        for _, pos in ipairs(results) do
                            table.insert(positions, start-1+pos)
                        end
                        score = score + score1
                    else
                        -- Query failed to match, so stop checking line_parts
                        match_success = false
                        break
                    end
                end
                j = j + 1
            end
            if match_success then
                table.insert(matches, {index = i, positions = positions, score = score})
            end
        end
    end
    return matches, num_groups
end

return {filter = filter}
