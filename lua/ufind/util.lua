local uv = vim.loop

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
            vim.defer_fn(function()
                local args2 = args
                args = nil  -- erase args first in case fn is recursive
                fn(vim.F.unpack_len(args2))
            end, 10)
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

---@param str string
---@return number?
function M.find_last_newline(str)  -- exposed for testing
    for i = #str, 1, -1 do
        if str:sub(i, i) == '\n' then
            return i
        end
    end
    return nil
end

---@param cmd       string
---@param args      string[]
---@param on_stdout fun(chunk: string)
---@param on_exit   fun()?
---@return fun()?, number?
function M.spawn(cmd, args, on_stdout, on_exit)
    local stdout, stderr = uv.new_pipe(), uv.new_pipe()
    -- When receiving stdout, the chunk may start or end with a partial line. For convenience, we
    -- slice off and store the partial line so we can always call `on_stdout` with complete lines.
    local stdout_overflow = ''
    local stderrbuf = {}
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
            on_exit()
        end
        handle:close()
    end)
    if not handle then  -- invalid command, bad permissions, etc
        M.errf('Failed to spawn: %s (%s)', cmd, pid_or_err)
        return nil, nil
    end
    ---@diagnostic disable-next-line: undefined-field
    stdout:read_start(function(e, chunk)  -- on stdout
        M.assert(not e, e)
        if not chunk then return end
        local nl = M.find_last_newline(chunk)
        if not nl then  -- just add to the overflow
            stdout_overflow = stdout_overflow .. chunk
        else
            on_stdout(stdout_overflow .. chunk:sub(1, nl-1))
            stdout_overflow = chunk:sub(nl+1)
        end
    end)
    ---@diagnostic disable-next-line: undefined-field
    stderr:read_start(function(e, chunk)  -- on stderr
        M.assert(not e, e)
        if not chunk then return end
        stderrbuf[#stderrbuf+1] = chunk
    end)
    local function kill_job()
        if handle and handle:is_active() then
            ---@diagnostic disable-next-line: undefined-field
            handle:kill(uv.constants.SIGTERM)
            -- Don't close the handle; that'll happen in on_exit
        end
    end
    return kill_job, pid_or_err
end

---@param val number
---@param min number
---@param max number
---@return number
function M.clamp(val, min, max)
    return math.min(max, math.max(min, val))
end

return M
