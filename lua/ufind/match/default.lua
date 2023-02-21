---Find the minimum subsequence in `str` containing `chars` (in order) using a
---sliding window algorithm.
---@param str   string
---@param chars string
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
local function default_match(str, query)
    str = str:lower()
    query = query:lower()
    local positions = find_min_subsequence(str, query)
    if positions == nil then
        return nil
    end
    local score = calc_score(positions, str)
    return positions, score
end

return default_match
