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


---@generic T : any
---@param fn fun(item: T): boolean
---@param tbl T[]
local function tbl_some(fn, tbl)
    for _, v in ipairs(tbl) do
        if fn(v) then
            return true
        end
    end
    return false
end


local function clamp(v, min, max)
    return math.min(math.max(v, min), max)
end


local function keymap(buf, mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, {nowait = true, silent = true, buffer = buf})
end


local function inject_empty_captures(pat)
    local n = 0  -- number of captures found
    local sub = string.gsub(pat, '%%?%b()', function(match)
        -- TODO: we shouldn't inject for [(]%)
        if vim.endswith(match, '()') or  -- (), %b()
            vim.startswith(match, '%(') then  -- %(
            return
        end
        n = n + 1
        return '()' .. match
    end)
    assert(n ~= 0, ('Expected at least one capture in pattern %q'):format(pat))
    return sub, n
end


local function pack(...)
    return {...}
end


---Alternative to `vim.schedule_wrap` that returns a throttled function, which,
---when called multiple times before finally invoked in the main loop, only
---calls the function once (with the arguments from the most recent call).
local function schedule_wrap_t(fn)
    local args
    return function(...)
        if args == nil then  -- nothing scheduled
            args = vim.F.pack_len(...)
            vim.schedule(function()
                local args2 = args
                args = nil  -- erase args first in case fn is recursive
                fn(vim.F.unpack_len(args2))
            end)
        else  -- the scheduled fn hasn't run yet
            args = vim.F.pack_len(...)
        end
    end
end

---@param ... string
local function err(...)
    local args = {...}
    vim.schedule(function ()
        vim.api.nvim_err_writeln('[ufind] ' .. table.concat(args, ' '))
    end)
end

return {
    find_min_subsequence = find_min_subsequence,
    tbl_some = tbl_some,
    clamp = clamp,
    keymap = keymap,
    inject_empty_captures = inject_empty_captures,
    pack = pack,
    schedule_wrap_t = schedule_wrap_t,
    err = err,
}
