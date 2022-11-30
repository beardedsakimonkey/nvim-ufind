local M = {}

---@generic T : any
---@param fn fun(item: T): boolean
---@param tbl T[]
function M.tbl_some(fn, tbl)
    for _, v in ipairs(tbl) do
        if fn(v) then
            return true
        end
    end
    return false
end

---Wrapper around `vim.keymap.set` that handles a list of lhs's
function M.keymap(mode, lhs, rhs, opts)
    if type(lhs) == 'string' then
        vim.keymap.set(mode, lhs, rhs, opts)
    else
        for _, v in ipairs(lhs) do
            vim.keymap.set(mode, v, rhs, opts)
        end
    end
end

function M.pack(...)
    return {...}
end

---Alternative to `vim.schedule_wrap` that returns a throttled function, which,
---when called multiple times before finally invoked in the main loop, only
---calls the function once (with the arguments from the most recent call).
function M.schedule_wrap_t(fn)
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

---@param level number
local function notify(level, ...)
    vim.notify('[ufind] ' .. table.concat({...}, ' '), level)
end

function M.err(...) notify(vim.log.levels.ERROR, ...) end
function M.warn(...) notify(vim.log.levels.WARN, ...) end
function M.warnf(...) M.warn(string.format(...)) end
function M.errf(...) M.err(string.format(...)) end

---@param msg string
function M.assert(v, msg)
    if not v then
        error('[ufind] ' .. msg, 2)
    end
end

---@param cmd       string
---@param args      string[]
---@param on_stdout fun(stdoutbuf: string[])
---@param on_exit   fun(stdoutbuf: string[])?
---@return vim.loop.Process?
function M.spawn(cmd, args, on_stdout, on_exit)
    local uv = vim.loop
    local stdout, stderr = uv.new_pipe(), uv.new_pipe()
    local stdoutbuf, stderrbuf = {}, {}
    local handle, pid_or_err
    handle, pid_or_err = uv.spawn(cmd, {
        stdio = {nil, stdout, stderr},
        args = args,
    }, function()  -- on exit
        -- Note: don't check exit code because some commands exit non-zero when successfully
        -- returning nothing.
        if next(stderrbuf) ~= nil then
            vim.schedule(function()
                M.warnf('Command `%s %s` wrote to stderr:\n%s',
                cmd, table.concat(args, ' '), table.concat(stderrbuf))
            end)
        end
        if on_exit then
            on_exit(stdoutbuf)
        end
        handle:close()
    end)
    if not handle then -- invalid command, bad permissions, etc
        M.errf('Failed to spawn: %s (%s)', cmd, pid_or_err)
        return nil
    end

    stdout:read_start(function(e, chunk)  -- on stdout
        M.assert(not e, e)
        if chunk then
            stdoutbuf[#stdoutbuf+1] = chunk
            on_stdout(stdoutbuf)
        end
    end)
    stderr:read_start(function(e, chunk)  -- on stderr
        M.assert(not e, e)
        if chunk then
            stderrbuf[#stderrbuf+1] = chunk
        end
    end)
    return handle
end

return M
