local M = {}

---@class UfindHighlight
---@field linenr number
---@field col_start number
---@field col_end number
---@field hl_group string

---@param lines string[]
---@return string[], UfindHighlight[]
function M.parse(lines)
    ---@type UfindHighlight[]
    local hls = {}
    local lines_noansi = {}

    for linenr, line in ipairs(lines) do
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

        ---@param pos number
        ---@param p number
        local function handle_sgr_param(pos, p)
            if p == 1 then  -- bold
                bold_start = pos
            elseif p == 3 then  -- italic
                italic_start = pos
            elseif p == 4 then  -- underline
                underline_start = pos
            elseif p == 7 then  -- reverse
                reverse_start = pos
            else
                if (p == 0 or p == 22) and bold_start then  -- end bold
                    hls[#hls+1] = {
                        linenr = linenr,
                        col_start = bold_start,
                        col_end = pos,
                        hl_group = 'ufind_bold',
                    }
                    bold_start = nil
                end
                if (p == 0 or p == 23) and italic_start then  -- end italic
                    hls[#hls+1] = {
                        linenr = linenr,
                        col_start = italic_start,
                        col_end = pos,
                        hl_group = 'ufind_italic',
                    }
                    italic_start = nil
                end
                if (p == 0 or p == 24) and underline_start then  -- end underline
                    hls[#hls+1] = {
                        linenr = linenr,
                        col_start = underline_start,
                        col_end = pos,
                        hl_group = 'ufind_underline',
                    }
                    underline_start = nil
                end
                if (p == 0 or p == 27) and reverse_start then  -- end reverse
                    hls[#hls+1] = {
                        linenr = linenr,
                        col_start = reverse_start,
                        col_end = pos,
                        hl_group = 'ufind_reverse',
                    }
                    reverse_start = nil
                end
                -- Note: fg/bg color can also be ended by setting a different fg/bg color.
                if p == 0 or p >= 30 and p <= 37 then
                    if fg_start then  -- end fg color
                        hls[#hls+1] = {
                            linenr = linenr,
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
                            linenr = linenr,
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

        local offset = 0

        -- Note: CSI is typically represented with a 2-byte sequence (0x1b5b). To save space, it can
        -- also be represented with a 1-byte code (0x9b). But, since this can conflict with
        -- codepoints in other modern encodings, the 2-byte representation is typically used. So,
        -- we only scan for that one.
        -- Ref: https://en.wikipedia.org/wiki/ANSI_escape_code#Fe_Escape_sequences

        local line_noansi = line:gsub('()\27%[([0-9;:]-)([\64-\126])', function(pos, params, final)
            if final == 'm' then  -- final byte indicates an SGR sequence
                pos = pos + offset  -- adjust pos for any previous substitutions
                for param in vim.gsplit(params, '[;:]', false) do
                    handle_sgr_param(pos, tonumber(param) or 0)
                end
            end
            offset = offset - 3 - #params
            return ''
        end)
        lines_noansi[#lines_noansi+1] = line_noansi
    end
    return lines_noansi, hls
end

---Strip ansi escape codes
---@param line string
function M.strip(line)
    return (line:gsub('\27%[[0-9;:]-[\64-\126]', ''))
end

return M
