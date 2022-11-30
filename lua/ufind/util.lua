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
    vim.notify('[ufind] ' .. table.concat({...}, ' '), vim.log.levels.ERROR)
end


---@param ... string
local function warn(...)
    vim.notify('[ufind] ' .. table.concat({...}, ' '), vim.log.levels.WARN)
end


---@param msg string
---@param ... string
local function warnf(msg, ...)
    warn(string.format(msg, ...))
end


---@param msg string
---@param ... string
local function errf(msg, ...)
    err(string.format(msg, ...))
end


---@param v   any
---@param msg string
local function assert(v, msg)
    if not v then
        error('[ufind] ' .. msg, 2)
    end
end


---@param cmd string
---@param args string[]
---@param on_stdout fun(stdoutbuf: string[])
---@return vim.loop.Process?
local function spawn(cmd, args, on_stdout)
    local uv = vim.loop
    local stdout, stderr = uv.new_pipe(), uv.new_pipe()
    local stdoutbuf, stderrbuf = {}, {}
    local handle, pid_or_err
    handle, pid_or_err = uv.spawn(cmd, {
        stdio = {nil, stdout, stderr},
        args = args,
    }, function(exit_code)  -- on exit
        if exit_code > 0 then
            vim.schedule(function()
                warnf('Command exited non-zero: `%s %s`\n%s',
                    cmd, table.concat(args, ' '), table.concat(stderrbuf))
            end)
        end
        handle:close()
    end)
    if not handle then -- invalid command, bad permissions, etc
        errf('Failed to spawn: %s (%s)', cmd, pid_or_err)
        return nil
    end

    stdout:read_start(function(e, chunk)  -- on stdout
        assert(not e, e)
        if chunk then
            stdoutbuf[#stdoutbuf+1] = chunk
            on_stdout(stdoutbuf)
        end
    end)
    stderr:read_start(function(e, chunk)  -- on stderr
        assert(not e, e)
        if chunk then
            stderrbuf[#stderrbuf+1] = chunk
        end
    end)
    return handle
end


return {
    tbl_some = tbl_some,
    keymap = keymap,
    pack = pack,
    schedule_wrap_t = schedule_wrap_t,
    err = err,
    errf = errf,
    warn = warn,
    warnf = warnf,
    assert = assert,
    spawn = spawn,
}
