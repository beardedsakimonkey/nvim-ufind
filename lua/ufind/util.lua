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


---Wrapper around `vim.keymap.set` that handles a list of lhs's
local function keymap(mode, lhs, rhs, opts)
    if type(lhs) == 'string' then
        vim.keymap.set(mode, lhs, rhs, opts)
    else
        for _, v in ipairs(lhs) do
            vim.keymap.set(mode, v, rhs, opts)
        end
    end
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


local function errf(str, ...)
    err(string.format(str, ...))
end

return {
    tbl_some = tbl_some,
    clamp = clamp,
    keymap = keymap,
    inject_empty_captures = inject_empty_captures,
    pack = pack,
    schedule_wrap_t = schedule_wrap_t,
    err = err,
    errf = errf,
}
