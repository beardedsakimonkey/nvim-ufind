local api = vim.api

local M = {}

local function hl_exists(name)
    local ok = pcall(api.nvim_get_hl_by_name, name, true)
    return ok
end

---Add ufind_* highlight groups if they don't already exist
function M.setup()
    -- Note: when termguicolors is set, it seems we can't use the terminal's preset 16 colors, so we
    -- use these color shorthands as an approximation.
    local color = {
        [0] = 'Black',
        [1] = 'DarkRed',
        [2] = 'DarkGreen',
        [3] = 'DarkYellow',
        [4] = 'DarkBlue',
        [5] = 'DarkMagenta',
        [6] = 'DarkCyan',
        [7] = 'White',
    }
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
                if s == 'fg' then
                    api.nvim_set_hl(0, name, {
                        fg = color[i],
                        ctermfg = i,
                    })
                else
                    api.nvim_set_hl(0, name, {
                        bg = color[i],
                        ctermbg = i,
                    })
                end
            end
        end
    end
end

return M
