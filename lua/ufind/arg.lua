--[[
     Helper functions for preprocessing user-provided arguments.
--]]
local util = require('ufind.util')

local M = {}

function M.inject_empty_captures(pat)
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
    util.assert(n ~= 0, ('Expected at least one capture in pattern %q'):format(pat))
    return sub, n
end

---@return string[]
function M.split_cmd_aux(cmd)  -- exposed for testing
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
                si = nil
            end
        else
            if c == ' ' then
                if si ~= nil then
                    ret[#ret+1] = cmd:sub(si, i-1)
                    si = nil
                end
            elseif c == '"' or c == "'" then
                q = c
                sq = i+1
            else  -- non-whitespace/quote
                if si == nil then
                    si = i
                end
                if i == #cmd then
                    ret[#ret+1] = cmd:sub(si, i)
                end
            end
        end
    end
    return ret
end

---Naive command splitting. Doesn't handle escaped quotes.
---@param cmd string
---@return string,string[]?
function M.split_cmd(cmd)
    local t = M.split_cmd_aux(cmd)
    return table.remove(t, 1), t
end

return M
