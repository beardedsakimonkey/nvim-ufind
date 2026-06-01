local api = vim.api

local M = {}

local function hl_exists(name)
    local ok1, hl1 = pcall(api.nvim_get_hl_by_name, name, true)
    local ok2, hl2 = pcall(api.nvim_get_hl_by_name, name, false)
    if not ok1 or not ok2 then
        return false
    end
    -- Hack: cleared highlight groups have changed shape across Nvim versions.
    local is_cleared = next(hl1) == nil and next(hl2) == nil
        or hl1[true] and hl2[true]
    if is_cleared then
        return false
    end
    return true
end

local function set_hl(name, val)
    if not hl_exists(name) then
        api.nvim_set_hl(0, name, val)
    end
end

local function setup_ansi()
    for _, s in ipairs{'bold', 'italic', 'underline', 'reverse'} do
        local name = 'ufind_' .. s
        if not hl_exists(name) then
            api.nvim_set_hl(0, name, {
                bold = s == 'bold',
                italic = s == 'italic',
                underline = s == 'underline',
                reverse = s == 'reverse',
            })
        end
    end
    for _, s in ipairs{'fg', 'bg'} do
        for i = 0, 7 do
            local name = 'ufind_' .. s .. i
            if not hl_exists(name) then
                local val = {}
                if s == 'fg' then
                    val.fg_indexed = i
                    val.ctermfg = i
                else
                    val.bg_indexed = i
                    val.ctermbg = i
                end
                api.nvim_set_hl(0, name, val)
            end
        end
    end
end

---Add ufind highlight groups if they don't already exist
function M.setup(ansi)
    set_hl('UfindMatch', {link = 'IncSearch'})
    set_hl('UfindPrompt', {link = 'Comment'})
    set_hl('UfindNormal', {link = 'Normal'})
    set_hl('UfindBorder', {link = 'Normal'})
    set_hl('UfindCursorLine', {link = 'CursorLine'})
    set_hl('UfindResultCount', {link = 'Comment'})
    set_hl('UfindMultiSelect', {link = 'Type'})
    if ansi then
        setup_ansi()
    end
end

return M
