-- Modified version of `vim.gsplit` that also returns the start index of the match.
-- Also handles '$' `sep` without erroring.
local function gsplit(s, sep, plain)
    vim.validate({ s = { s, 's' }, sep = { sep, 's' }, plain = { plain, 'b', true } })

    local start = 1
    local done = false

    local function _pass(i, j)
        if i then
            assert(j + 1 > start, 'Infinite loop detected')
            if i > j then done = true end -- str:find('$')
            local start_save = start
            local seg = s:sub(start, i - 1)
            start = j + 1
            return seg, start_save
        else
            done = true
            return s:sub(start), start
        end
    end

    return function()
        if done or s == '' then
            return
        end
        if sep == '' then
            if start == #s then
                done = true
            end
            return _pass(start + 1, start)
        end
        return _pass(s:find(sep, start, plain))
    end
end

-- Find the minimum subsequence in `str` containing `chars` (in order) using a
-- sliding window algorithm.
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
                table.insert(new_min.positions, s)
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

local function tbl_some(fn, t)
    for _, v in ipairs(t) do
        if fn(v) then
            return true
        end
    end
    return false
end

return {
    gsplit = gsplit,
    find_min_subsequence = find_min_subsequence,
    tbl_some = tbl_some,
}
