-- Helper functions for preprocessing user-provided arguments

local function inject_empty_captures(pat)
    local n = 0  -- number of captures found
    local sub = pat:gsub('%%?%b()', function(match)
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


---@private
---@return string[]
local function split_cmd_aux(cmd)
    if #cmd <= 2 then  -- can't be split
        return {cmd}
    end
    local si = nil  -- start index
    local sq = nil  -- start quote
    local q = nil  -- quote type
    local ret = {}
    for i = 1, #cmd do
        local c = cmd:sub(i, i)
        if sq ~= nil then
            if c == q then
                ret[#ret+1] = cmd:sub(sq, i-1)
                sq = nil
                q = nil
            end
        else
            if c == ' ' then
                if si ~= nil then
                    ret[#ret+1] = cmd:sub(si, i-1)
                    si = nil
                end
            else  -- non-whitespace
                if i == #cmd then
                    ret[#ret+1] = cmd:sub(si, i)
                elseif si == nil then
                    si = i
                end
                if c == '"' or c == "'" then
                    q = c
                    sq = i+1
                end
            end
        end
    end
    return ret
end


---Naive command splitting. Doesn't handle escaped quotes.
---@param cmd string
---@return string,string[]?
local function split_cmd(cmd)
    local t = split_cmd_aux(cmd)
    return table.remove(t, 1), t
end

return {
    inject_empty_captures = inject_empty_captures,
    split_cmd = split_cmd,
    _split_cmd_aux = split_cmd_aux,  -- for testing
}
