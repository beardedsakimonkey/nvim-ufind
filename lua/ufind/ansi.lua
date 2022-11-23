local api = vim.api

---@class UfHighlight
---@field line number
---@field col_start number
---@field col_end number
---@field hl_group string


---@param lines string[]
---@return string[], UfHighlight[]
local function parse(lines)
    ---@type UfHighlight[]
    local hls = {}
    local lines_noansi = {}

    for linenr, line in ipairs(lines) do
        local offset = 0
        ---@type number[]?
        local fg_start
        ---@type number[]?
        local bg_start
        ---@type number?
        local bold_start
        ---@type number?
        local italic_start
        ---@type number?
        local underline_start
        ---@type number?
        local reverse_start

        -- Note: CSI is typically represented with a 2-byte sequence (0x1b5b). To
        -- save space, it can also be represented with a 1-byte code (0x9b). But,
        -- since this can conflict with codepoints in other modern encodings, the
        -- 2-byte representation is typically used. So, we only scan for that one.
        -- Ref: https://en.wikipedia.org/wiki/ANSI_escape_code#Fe_Escape_sequences
        local line_noansi = line:gsub('()\27%[([0-9;]-)([\64-\126])', function(pos, params, final)
            if final == 'm' then  -- final byte indicates an SGR sequence
                pos = pos + offset  -- adjust pos for any previous substitutions
                for param in vim.gsplit(params, ';', true) do
                    local p = tonumber(param) or 0
                    if p == 1 then  -- bold
                        bold_start = pos
                    elseif p == 3 then  -- italic
                        italic_start = pos
                    elseif p == 4 then  -- underline
                        underline_start = pos
                    elseif p == 7 then  -- reverse
                        reverse_start = pos
                    end
                    if (p == 0 or p == 22) and bold_start then  -- end bold
                        hls[#hls+1] = {
                            line = linenr,
                            col_start = bold_start,
                            col_end = pos,
                            hl_group = 'ufind_bold',
                        }
                        bold_start = nil
                    end
                    if (p == 0 or p == 23) and italic_start then  -- end italic
                        hls[#hls+1] = {
                            line = linenr,
                            col_start = italic_start,
                            col_end = pos,
                            hl_group = 'ufind_italic',
                        }
                        italic_start = nil
                    end
                    if (p == 0 or p == 24) and underline_start then  -- end underline
                        hls[#hls+1] = {
                            line = linenr,
                            col_start = underline_start,
                            col_end = pos,
                            hl_group = 'ufind_underline',
                        }
                        underline_start = nil
                    end
                    if (p == 0 or p == 27) and reverse_start then  -- end reverse
                        hls[#hls+1] = {
                            line = linenr,
                            col_start = reverse_start,
                            col_end = pos,
                            hl_group = 'ufind_reverse',
                        }
                        reverse_start = nil
                    end

                    -- Note: fg/bg color can also be ended by setting a different fg/bg
                    -- color.
                    if p == 0 or p >= 30 and p <= 37 then
                        if fg_start then  -- end fg color
                            hls[#hls+1] = {
                                line = linenr,
                                col_start = fg_start[1],
                                col_end = pos,
                                hl_group = 'ufind_fg' .. fg_start[2],
                            }
                            fg_start = nil
                        end
                        if p ~= 0 then  -- start fg color
                            fg_start = {pos, p - 30}
                        end
                    end
                    if p == 0 or p >= 40 and p <= 47 then
                        if bg_start then  -- end bg color
                            hls[#hls+1] = {
                                line = linenr,
                                col_start = bg_start[1],
                                col_end = pos,
                                hl_group = 'ufind_bg' .. bg_start[2],
                            }
                            bg_start = nil
                        end
                        if p ~= 0 then  -- start bg color
                            bg_start = {pos, p - 40}
                        end
                    end
                end
            end
            offset = offset - 3 - #params
            return ''
        end)
        lines_noansi[#lines_noansi+1] = line_noansi
    end
    return lines_noansi, hls
end


---Strip ansi escape codes from each line
local function strip(lines)
    return vim.tbl_map(function(line)
        return line:gsub('\27%[[0-9;]-[\64-\126]', '')
    end, lines)
end


local function hl_exists(name)
    local ok = pcall(api.nvim_get_hl_by_name, name, true)
    return ok
end


---Add ufind_* highlight groups if they don't already exist
local function add_highlights()
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


-- print(parse([[[35mtest:[mYo]]))
-- print(parse([[[01;31m[Kex[m[K =]]))
-- print(parse([[[0m[35mufind.lua[0m:[0m[32m25[0m:--   require'ufind'.open({'~/[0m[1m[31mfoo[0m', '~/bar'})]]))

return {
    parse = parse,
    strip = strip,
    add_highlights = add_highlights,
}
