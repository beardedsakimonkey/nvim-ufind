local util = require('ufind.util')

---Find the minimum subsequence in `str` containing `chars` (in order) using a
---sliding window algorithm.
local function find_min_subsequence(str, chars)
    local s, c = 1, 1
    local seq = {
        length = -1,
        start_index = nil,
        positions = {},
    }
    while s <= #str do
        -- Increment `s` until it is on the character that `c` is on
        while c <= #chars and s <= #str do
            if chars:sub(c, c) == str:sub(s, s) then
                break
            end
            s = s + 1
        end
        if s > #str then break end
        -- Find the next valid subsequence in `str`
        local new_min = {
            length = 1,
            start_index = s,
            positions = {},
        }
        while c <= #chars and s <= #str do
            if chars:sub(c, c) ~= str:sub(s, s) then
                s = s + 1
                new_min.length = new_min.length + 1
            else
                new_min.positions[#new_min.positions+1] = s
                c = c + 1
                s = s + 1
            end
        end
        if c > #chars and (new_min.length <= seq.length or seq.length == -1) then
            seq = new_min
        end
        c = 1
        s = new_min.start_index + 1
    end
    if seq.start_index == nil then
        return nil
    else
        return seq.positions
    end
end


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
---@param queries UfindQuery[]
local function fuzzy_match(str, queries)
    if not str or #str == 0 or vim.tbl_isempty(queries) then return nil end
    str = str:lower()
    local positions = {}
    for _, q in ipairs(queries) do
        q.term = q.term:lower()
        if q.exact then  -- has '
            local starti, endi = str:find(q.term, 1, true)
            if not starti then
                return nil
            else
                for i = starti, endi do
                    positions[#positions+1] = i
                end
            end
        elseif q.prefix and q.suffix then  -- has ^ and $
            local match = str == q.term  -- so do a full match
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.prefix then  -- has ^
            local match = vim.startswith(str, q.term)
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.suffix then  -- has $
            local match = vim.endswith(str, q.term)
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.invert then  -- has !
            if str:find(q.term, 1, true) then
                return nil
            end
        else
            local results = find_min_subsequence(str, q.term)
            if not results then return nil end
            for _, pos in ipairs(results) do
                positions[#positions+1] = pos
            end
        end
    end
    -- Invariant: none of the matches failed
    table.sort(positions)  -- for calculating consecutive char bonus
    return positions, calc_score(positions, str)
end


---@return UfindQuery?
local function parse_query(query_part)
    local invert, prefix, exact, suffix = false, false, false, false
    local ts, te = 1, -1  -- term start/end
    -- Check exact match first. A ' that comes after another sigil (! or ^) is
    -- useless. If it comes before other sigils, we treat those as literal
    -- characters instead.
    if query_part:sub(ts, ts) == "'" then
        ts = ts + 1
        exact = true
    else
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
    end
    local term = query_part:sub(ts, te)
    return #term > 0 and
        ---@class UfindQuery
        {
            exact = exact,    -- '
            invert = invert,  -- !
            prefix = prefix,  -- ^
            suffix = suffix,  -- $
            term = term,
        } or nil  -- don't score results if there's no term
end


local function sort_queries(queries)
    table.sort(queries, function(a, b)
        if a.prefix ~= b.prefix then return a.prefix      -- prefix queries come first
        elseif a.suffix ~= b.suffix then return a.suffix  -- then suffix queries
        elseif a.invert ~= b.invert then return a.invert  -- then inverted queries
        else return #a.term < #b.term end                 -- then shorter queries
    end)
end


---@return UfindQuery[][]
local function parse_queries(raw_queries)
    local query_sets = vim.tbl_map(function(raw_query)
        if raw_query:match('^%s*$') then -- is empty
            return {}
        end
        local query_set = {}
        for query_part in vim.gsplit(raw_query, " +") do
            query_set[#query_set+1] = parse_query(query_part)
        end
        return query_set
    end, raw_queries)
    -- Sort queries for performance
    for _, queries in ipairs(query_sets) do
        sort_queries(queries)
    end
    return query_sets
end


---@param raw_queries string[]
---@param lines string[]
---@param pattern string
local function filter(raw_queries, lines, pattern)
    local query_sets = parse_queries(raw_queries)
    local res = {}

    local has_any_query = util.tbl_some(function(query_set)
        return not vim.tbl_isempty(query_set)
    end, query_sets)

    if not has_any_query then
        for i = 1, #lines do
            res[#res+1] = {index = i, positions = {}, score = 0}
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
                        pos[#pos+1] = cap_pos - 1 + mp
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
            res[#res+1] = {index = i, positions = pos, score = score}
        end
    end

    table.sort(res, function(a, b) return a.score > b.score end)
    return res
end


return {
    filter = filter,
    _find_min_subsequence = find_min_subsequence,  -- for testing
}
