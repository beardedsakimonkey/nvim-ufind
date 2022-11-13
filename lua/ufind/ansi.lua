local color_name = {
    [0] = 'Black',
    [1] = 'DarkRed',
    [2] = 'DarkGreen',
    [3] = 'DarkYellow',
    [4] = 'DarkBlue',
    [5] = 'DarkMagenta',
    [6] = 'DarkCyan',
    [7] = 'White',
}

---@class UfHighlights
---@field line number
---@field col_start number
---@field col_end number
---@field hl_group string
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field reverse? boolean
---@field fg? {1: number, 2: string}
---@field bg? {1: number, 2: string}

---@param line string
---@param linenr number
---@return UfHighlights, string
local function parse(line, linenr)
    local offset = 0
    ---@type UfHighlights
    local hls = {}
    ---@type {1: number, 2: string}?
    local fg
    ---@type {1: number, 2: string}?
    local bg
    ---@type number?
    local bold
    ---@type number?
    local italic
    ---@type number?
    local underline
    ---@type number?
    local reverse

    -- NOTE: CSI is typically represented with a 2-byte sequence (0x1b5b). To
    -- save space, it can also be represented with a 1-byte code (0x9b). But,
    -- since this can conflict with codepoints in other modern encodings, the
    -- 2-byte representation is typically used. So, we only scan for that one.
    -- Ref: https://en.wikipedia.org/wiki/ANSI_escape_code#Fe_Escape_sequences
    local line_noansi = line:gsub('()\27%[([0-9;]-)([\64-\126])', function(pos, params, final)
        if final == 'm' then  -- final byte indicates an SGR sequence
            pos = pos + offset  -- adjust pos for any previous substitutions
            for param in vim.gsplit(params, ';', true) do
                local param_num = tonumber(param) or 0
                if param_num == 1 then  -- bold
                    bold = pos
                elseif param_num == 3 then  -- italic
                    italic = pos
                elseif param_num == 4 then  -- underline
                    underline = pos
                elseif param_num == 7 then  -- reverse
                    reverse = pos
                end

                if param_num == 0 or param_num == 22 then  -- normal intensity
                    if bold then
                        table.insert(hls, {
                            line = linenr,
                            col_start = bold,
                            col_end = pos,
                            bold = true,
                            hl_group = 'ufind_bold',
                        })
                    end
                    bold = nil
                end

                if param_num == 0 or param_num == 23 then  -- not italic
                    if italic then
                        table.insert(hls, {
                            line = linenr,
                            col_start = italic,
                            col_end = pos,
                            italic = true,
                            hl_group = 'ufind_italic',
                        })
                    end
                    italic = nil
                end

                if param_num == 0 or param_num == 24 then  -- not underlined
                    if underline then
                        table.insert(hls, {
                            line = linenr,
                            col_start = underline,
                            col_end = pos,
                            underline = true,
                            hl_group = 'ufind_underline',
                        })
                    end
                    underline = nil
                end

                if param_num == 0 or param_num == 27 then  -- not reversed
                    if reverse then
                        table.insert(hls, {
                            line = linenr,
                            col_start = reverse,
                            col_end = pos,
                            reverse = true,
                            hl_group = 'ufind_reverse',
                        })
                    end
                    reverse = nil
                end

                if param_num == 0 or
                    param_num >= 30 and param_num <= 37 then  -- set foreground color
                    if fg then
                        table.insert(hls, {
                            line = linenr,
                            col_start = fg[1],
                            col_end = pos,
                            fg = fg[2],
                            hl_group = 'ufind_fg_' .. fg[2],
                        })
                    end
                    if param_num == 0 then
                        fg = nil
                    else
                        fg = {pos, color_name[param_num-30]}
                    end
                end

                if param_num == 0 or
                    param_num >= 40 and param_num <= 47 then  -- set background color
                    if bg then
                        table.insert(hls, {
                            line = linenr,
                            col_start = bg[1],
                            col_end = pos,
                            bg = bg[2],
                            hl_group = 'ufind_bg_' .. bg[2],
                        })
                    end
                    if param_num == 0 then
                        bg = nil
                    else
                        bg = {pos, color_name[param_num-40]}
                    end
                end
            end
        end
        offset = offset - 3 - #params
        return ''
    end)
    return hls, line_noansi
end

-- print(parse([[[35mtest:[mYo]]))
-- print(parse([[[01;31m[Kex[m[K =]]))
-- print(parse([[[0m[35mufind.lua[0m:[0m[32m25[0m:--   require'ufind'.open({'~/[0m[1m[31mfoo[0m', '~/bar'})]]))

return {parse = parse}
