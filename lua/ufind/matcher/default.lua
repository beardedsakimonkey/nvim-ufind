---@param positions number[]
---@param str string
local function calc_score(positions, str)
    table.sort(positions)  -- for calculating consecutive char bonus
    local tail_start = str:find('[^/]+/?$')
    local tail_streak = tail_start
    local score = 0
    local prev_pos = -1
    for _, pos in ipairs(positions) do
        local consec = pos == prev_pos + 1
        local tail = tail_start and pos >= tail_start or false
        local word_start = pos == 0 or (pos > 1 and str:sub(pos-1, pos-1) == '/')
        if consec     then score = score + 1 end  -- consecutive char
        if tail       then score = score + 1 end  -- path tail
        if word_start then score = score + 1 end  -- start of word
        if consec and prev_pos == tail_streak then   -- consecutive streak from tail start
            score = score + 1
            tail_streak = pos
        end
        prev_pos = pos
    end
    return score
end

-- Do a fuzzy, case-insensitive match of `str` using `query`. The matching
-- algorithm is slow but is guaranteed to find the best match. The scoring
-- algorithm assumes the `str` is a file path, favoring matches on the path
-- tail.
---@return (number[], number) | nil
local function default_matcher(str, query)
    str = str:lower()
    query = query:lower()
    local positions = require'ufind.helper.find_min_subsequence'(str, query)
    if positions == nil then
        return nil
    end
    local score = calc_score(positions, str)
    return positions, score
end

return default_matcher
