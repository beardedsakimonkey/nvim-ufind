-- Returns an iterator that iterates on a string twice: the substring to the
-- left of the pattern `delim` and the substring to the right. The iterator
-- returns two values: the start index of the match and the substring.
--
-- Example:
--   for i, m in splitonce('f.lua:12:foo bar', ':%d+:') do
--     print(i, m)
--   end
--
-- Prints:
--   1 f.lua
--   10 foo bar
local function splitonce(str, delim)
    local i = nil
    local done = false
    return function()
        if done then
            return nil
        elseif i == nil then -- first iteration
            local s, e = str:find(delim)
            i = e+1
            return 1, str:sub(1, s-1)
        else -- second iteration
            done = true
            return i, str:sub(i)
        end
    end
end

return {splitonce = splitonce}
