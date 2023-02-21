local util = require('ufind.util')

local M = {}

-- Precondition: has queries
---@param queries UfindQuery[]
---@return number[]?
local function match_capture(str, queries, match_fn)
    if not str or #str == 0 then return nil end
    local str_lc = str:lower()
    local positions = {}
    local score = 0
    for _, q in ipairs(queries) do
        local term_lc = q.term:lower()
        if q.exact then  -- has '
            local starti, endi = str_lc:find(term_lc, 1, true)
            if not starti then
                return nil
            end
        elseif q.prefix and q.suffix then  -- has ^ and $
            local match = str_lc == term_lc  -- so do a full match
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.prefix then  -- has ^
            local match = vim.startswith(str_lc, term_lc)
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.suffix then  -- has $
            local match = vim.endswith(str_lc, term_lc)
            if not q.invert and not match
                or q.invert and match then
                return nil
            end
        elseif q.invert then  -- has !
            if str_lc:find(term_lc, 1, true) then
                return nil
            end
        else
            local m_positions, m_score = match_fn(str, q.term)
            if m_positions == nil then  -- no match
                return nil
            end
            for _, m_pos in ipairs(m_positions) do
                positions[#positions+1] = m_pos
            end
            score = score + m_score
        end
    end
    -- None of the matches failed
    return positions, score
end

---@return UfindQuery?
local function parse_query(query_part)
    local invert, prefix, exact, suffix = false, false, false, false
    local ts, te = 1, -1  -- term start/end
    -- Check exact match first. A ' that comes after another sigil (! or ^) is useless. If it comes
    -- before other sigils, we treat those as literal characters instead.
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

---@param raw_queries string[]
---@return UfindQuery[][]
local function parse_queries(raw_queries)
    ---@type UfindQuery[][]
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
        table.sort(queries, function(a, b)
            if a.prefix ~= b.prefix then return a.prefix      -- prefix queries come first
            elseif a.suffix ~= b.suffix then return a.suffix  -- then suffix queries
            elseif a.invert ~= b.invert then return a.invert  -- then inverted queries
            else return #a.term < #b.term end                 -- then shorter queries
        end)
    end
    return query_sets
end

---@param raw_queries string[]
---@param lines string[]
---@param scopes string
---@param match_fn fun()?
---@return UfindOpenMatch[]
function M.match(raw_queries, lines, scopes, match_fn)
    local query_sets = parse_queries(raw_queries)
    ---@class UfindOpenMatch
    ---@field index number
    ---@field positions number[]?
    ---@field score number[]
    local res = {}

    local has_query = util.tbl_some(function(query_set)
        return not vim.tbl_isempty(query_set)
    end, query_sets)

    if not has_query then
        for i = 1, #lines do
            res[#res+1] = {index = i, positions = nil, score = 0}
        end
        return res
    end

    for i, line in ipairs(lines) do
        local fail = false
        local pos = {}
        local score = 0
        local matches = util.pack(string.match(line, scopes))
        local j = 1
        for m = 1, #matches, 2 do  -- for each capture
            local cap_pos, cap = matches[m], matches[m+1]
            local query_set = query_sets[j]
            if query_set and not vim.tbl_isempty(query_set) then  -- has query
                local mpos, mscore = match_capture(cap, query_set, match_fn)
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

return M
