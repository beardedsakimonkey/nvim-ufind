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

return find_min_subsequence
