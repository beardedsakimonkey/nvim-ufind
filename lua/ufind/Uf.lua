local win = require('ufind.win')
local util = require('ufind.util')
local ansi = require('ufind.ansi')

local api = vim.api

---@alias UfMatch string|UfOpenMatch

---@class Ufind
---@field cur_input            number
---@field input_bufs           number[]
---@field on_complete          fun(string, string)
---@field orig_win             number
---@field result_buf           number
---@field input_win            number
---@field result_win           number
---@field vimresized_auid      number
---@field winclosed_auid       number
---@field matches              UfMatch[]
---@field top                  number (1-indexed)
---@field selections           {[number]: true}
---@field results_ns           number
---@field virt_ns              number
---@field ansi                 boolean
---@field get_highlights       fun(string): UfHighlightRange[]
---@field get_line             fun(self, number): string
---@field get_line_from_match  fun(UfMatch): string
---@field gidx                 fun(self, number): number
---@field is_selected          fun(self, number, UfMatch): boolean
local Uf = {}

---@param config     UfindConfig
---@param num_inputs number?
function Uf.new(config, num_inputs)
    local o = {}
    setmetatable(o, {__index = Uf})

    num_inputs = num_inputs or 1
    o.cur_input = util.clamp(config.initial_scope, 1, num_inputs)
    o.input_bufs = {}
    o.ansi = config.ansi
    o.get_highlights = config.get_highlights

    -- Create input buffers
    for _ = 1, num_inputs do
        o.input_bufs[#o.input_bufs+1] = win.create_input_buf()
    end

    -- Set prompts
    for i = 1, #o.input_bufs do
        local prompt = i .. '/' .. num_inputs .. '> '
        vim.fn.prompt_setprompt(o.input_bufs[i], prompt)
        api.nvim_buf_add_highlight(o.input_bufs[i], -1, 'UfindPrompt', 0, 0, #prompt)
    end

    if config.initial_query ~= '' then
        api.nvim_feedkeys(config.initial_query, 'n', false)
    end

    -- For occlusion-culling results
    ---@type UfMatch[]
    o.matches = {}  -- stores current matches for when we scroll
    o.top = 1  -- line number of the line at the top of the viewport

    -- For multiselect
    ---@type {[number]: true}
    o.selections = {}

    o.on_complete = config.on_complete
    o.orig_win = api.nvim_get_current_win()
    o.result_buf = win.create_result_buf()
    o.input_win, o.result_win = win.create_wins(o.input_bufs[o.cur_input], o.result_buf, config.layout)
    o.vimresized_auid = win.handle_vimresized(o.input_win, o.result_win, config.layout)
    o.winclosed_auid = api.nvim_create_autocmd('WinClosed', {callback = function() o:quit() end})

    o.results_ns = api.nvim_create_namespace('ufind/results')  -- for all highlights in the results window
    o.virt_ns = api.nvim_create_namespace('ufind/virt')  -- for the result count

    for i = 1, #o.input_bufs do
        o:setup_keymaps(o.input_bufs[i], config.keymaps)
    end

    return o
end

function Uf:switch_input_buf(is_forward)
    local offset = is_forward and 1 or -1
    local i = self.cur_input + offset
    if i > #self.input_bufs then
        self.cur_input = 1
    elseif i < 1 then
        self.cur_input = #self.input_bufs
    else
        self.cur_input = i
    end
    api.nvim_win_set_buf(self.input_win, self.input_bufs[self.cur_input])
end

---@return number The cursor line number (1-indexed)
function Uf:get_cursor()
    local cursor = api.nvim_win_get_cursor(self.result_win)
    return cursor[1]
end

---@return number The "viewport" height of the results window
function Uf:get_vp_height()
    return api.nvim_win_get_height(self.result_win)
end

---@param offset number
---@return boolean need_redraw
function Uf:move_cursor(offset)
    local last = #self.matches
    -- Relative cursor number (1 <= cursor_rel <= vp_height)
    local cursor_rel = self:get_cursor()
    -- Absolute cursor number (1 <= cursor_abs <= last)
    local cursor_abs = self.top + cursor_rel - 1

    local offset_clamped = offset
    -- Clamp offset such that 1 <= cursor_abs + offset <= last
    if cursor_abs + offset < 1 then
        offset_clamped = -cursor_abs + 1
    elseif cursor_abs + offset > last then
        offset_clamped = last - cursor_abs
    end

    -- Relative cursor pos adjusted by offset
    local adj_cursor = cursor_rel + offset_clamped

    -- Viewport height
    local vp_height = self:get_vp_height()

    -- Cursor is outside of top bound
    if adj_cursor < 1 then
        --[[ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
             Ex: Scrolling up 2 lines when the cursor is at the top
             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

                         ------- 1 ------- --> cursor_abs(4) + offset(-2)
                                 ▲
             adj_cursor(-1) - 1  |  cursor_rel(1) + offset(-2) - 1
                                 ▼
                        +------- 3 -------+--> top(3)
                        |------- 1 -------|--> cursor_rel(1)
                        |                 |
                        |                 |
                        +-----------------+

             We subtract 1 from adj_cursor because cursor_rel is 1-indexed.
             top = top(3) + adj_cursor(-1) - 1
             top = 1
        --]]
        -- Move viewport up
        self.top = self.top + adj_cursor - 1
        -- Set cursor at viewport top
        api.nvim_win_set_cursor(self.result_win, {1, 0})
        return true
    end
    -- Cursor is outside of bottom bound
    if adj_cursor > vp_height then
        -- Move viewport down
        self.top = self.top + adj_cursor - vp_height
        -- Set cursor at viewport bottom
        api.nvim_win_set_cursor(self.result_win, {vp_height, 0})
        return true
    end
    -- Cursor is within bounds
    api.nvim_win_set_cursor(self.result_win, {adj_cursor, 0})
    return false
end

---@return number?
local function get_mousescroll()
    local opt = vim.opt.mousescroll:get()
    if opt[1] and vim.startswith(opt[1], 'ver:') then
        return tonumber(opt[1]:sub(5))
    end
    if opt[2] and vim.startswith(opt[2], 'ver:') then
        return tonumber(opt[2]:sub(5))
    end
    return nil
end

---@param m 'up'|'down'|'page_up'|'page_down'|'home'|'end'|'wheel_up'|'wheel_down' Cursor motion
function Uf:move_cursor_and_redraw(m)
    local need_redraw
    if m == 'up' or m == 'down' then
        need_redraw = self:move_cursor(m == 'up' and -1 or 1)
    elseif m == 'page_up' or m == 'page_down' then
        local page = self:get_vp_height()
        need_redraw = self:move_cursor(m == 'page_up' and -page or page)
    elseif m == 'home' or m == 'end' then
        need_redraw = self:move_cursor(m == 'home' and -math.huge or math.huge)
    elseif m == 'wheel_up' or m == 'wheel_down' then
        if not self.mousescroll then
            self.mousescroll = get_mousescroll() or 3
        end
        need_redraw = self:move_cursor(m == 'wheel_up' and -self.mousescroll or self.mousescroll)
    end
    if need_redraw then
        self:redraw_results()
    end
end

function Uf:quit()
    -- Important to delete the WinClosed autocmd *before* closing windows
    api.nvim_del_autocmd(self.winclosed_auid)
    api.nvim_del_autocmd(self.vimresized_auid)
    for _, buf in ipairs(self.input_bufs) do
        if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, {force = true}) end
    end
    if api.nvim_buf_is_valid(self.result_buf) then api.nvim_buf_delete(self.result_buf, {}) end
    if api.nvim_win_is_valid(self.orig_win)   then api.nvim_set_current_win(self.orig_win) end
    -- Seems unneeded, but not sure why (deleting the buffer closes the window)
    if api.nvim_win_is_valid(self.input_win)  then api.nvim_win_close(self.input_win, false) end
    if api.nvim_win_is_valid(self.result_win) then api.nvim_win_close(self.result_win, false) end
end

function Uf:open_result(cmd)
    local lines = {}
    if next(self.selections) ~= nil then
        for idx, _ in pairs(self.selections) do
            local line = self:get_line(idx)
            lines[#lines+1] = self.ansi and ansi.strip(line) or line
        end
    else
        local cursor = self:get_cursor()
        local line = api.nvim_buf_get_lines(self.result_buf, cursor-1, cursor, false)[1]
        lines[1] = line  -- ansi codes already stripped
    end
    if next(lines) ~= nil then
        self:quit()  -- cleanup first in case `on_complete` opens another finder
        self.on_complete(cmd, lines)
    end
end

---@return string
function Uf.get_query(buf)
    local buf_lines = api.nvim_buf_get_lines(buf, 0, 1, true)
    local query = buf_lines[1]
    local prompt = vim.fn.prompt_getprompt(buf)
    return query:sub(1 + #prompt)  -- trim prompt from the query
end

---@return string[]
function Uf:get_queries()
    return vim.tbl_map(self.get_query, self.input_bufs)
end

function Uf:setup_keymaps(buf, keymaps)
    local opts = {nowait = true, silent = true, buffer = buf}
    for k, v in pairs(keymaps) do
        if k == 'quit' then
            util.keymap({'i', 'n'}, v, function() self:quit() end, opts)
        elseif k == 'open' then
            util.keymap('i', v, function() self:open_result('edit') end, opts)
        elseif k == 'open_split' then
            util.keymap('i', v, function() self:open_result('split') end, opts)
        elseif k == 'open_vsplit' then
            util.keymap('i', v, function() self:open_result('vsplit') end, opts)
        elseif k == 'open_tab' then
            util.keymap('i', v, function() self:open_result('tabedit') end, opts)
        elseif k == 'up' or k == 'down' or k == 'page_up' or k == 'page_down'
            or k == 'home' or k == 'end' or k == 'wheel_up' or k == 'wheel_down' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'prev_scope' then
            util.keymap('i', v, function() self:switch_input_buf(false) end, opts)
        elseif k == 'next_scope' then
            util.keymap('i', v, function() self:switch_input_buf(true) end, opts)
        elseif k == 'toggle_select' then
            util.keymap('i', v, function() self:toggle_select() end, opts)
        elseif k == 'toggle_select_all' then
            util.keymap('i', v, function() self:toggle_select_all() end, opts)
        else
            util.errf('Invalid keymap name %q', k)
        end
    end
end

function Uf:toggle_select()
    local match_idx = self.top + self:get_cursor() - 1
    if self.matches[match_idx] == nil then  -- cursor is on an empty line
        return
    end
    local idx = self:gidx(match_idx)
    if self.selections[idx] then
        self.selections[idx] = nil
    else
        self.selections[idx] = true
    end
    self:move_cursor(1)
    self:redraw_results()
end

function Uf:toggle_select_all()
    if next(self.selections) then  -- select none
        self.selections = {}
    else  -- select all
        self.selections = {}
        for match_idx = 1, #self.matches do
            self.selections[self:gidx(match_idx)] = true
        end
    end
    self:redraw_results()
end

function Uf:get_visible_matches()
    local visible_matches = {}
    local vp_height = self:get_vp_height()
    local bot = math.min(self.top + vp_height - 1, #self.matches)
    for i = self.top, bot do
        visible_matches[#visible_matches+1] = self.matches[i]
    end
    return visible_matches
end

function Uf:redraw_results()
    api.nvim_buf_clear_namespace(self.result_buf, self.results_ns, 0, -1)
    local selected_linenrs = {}
    local visible_lines = {}
    for i, match in ipairs(self:get_visible_matches()) do
        if self:is_selected(i, match) then
            table.insert(selected_linenrs, i)
        end
        table.insert(visible_lines, self.get_line_from_match(match))
    end
    if self.ansi then
        local lines_noansi, hls = ansi.parse(visible_lines)
        api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines_noansi)
        -- Note: need to add highlights *after* buf_set_lines
        for _, hl in ipairs(hls) do
            api.nvim_buf_add_highlight(self.result_buf, self.results_ns, hl.hl_group,
                hl.linenr-1, hl.col_start-1, hl.col_end-1)
        end
    else
        api.nvim_buf_set_lines(self.result_buf, 0, -1, true, visible_lines)
    end
    self:hl_lines()
    self:hl_multiselect(selected_linenrs)
    self:hl_matches()
end

function Uf:hl_matches()
    for i, match in ipairs(self:get_visible_matches()) do
        if match.positions then
            for _, pos in ipairs(match.positions) do
                api.nvim_buf_add_highlight(self.result_buf, self.results_ns, 'UfindMatch', i-1, pos-1, pos)
            end
        end
    end
end

function Uf:set_virt_text(text)
    for _, buf in ipairs(self.input_bufs) do
        api.nvim_buf_clear_namespace(buf, self.virt_ns, 0, -1)
        api.nvim_buf_set_extmark(buf, self.virt_ns, 0, -1, {
            virt_text = {{text, 'UfindResultCount'}},
            virt_text_pos = 'right_align'
        })
    end
end

function Uf:hl_multiselect(selected_linenrs)
    for _, linenr in ipairs(selected_linenrs) do
        api.nvim_buf_add_highlight(self.result_buf, self.results_ns, 'UfindMultiSelect', linenr-1, 0, -1)
    end
end

function Uf:hl_lines()
    if not self.get_highlights then
        return
    end
    for i, match in ipairs(self:get_visible_matches()) do
        local hls = self.get_highlights(self.get_line_from_match(match))
        if not vim.tbl_islist(hls) and not self.warned_get_highlights then
            self.warned_get_highlights  = true
            util.warn('config.get_highlights() must return a list')
        end
        for _, hl in ipairs(hls or {}) do
            api.nvim_buf_add_highlight(self.result_buf, self.results_ns,
            hl.hl_group, i-1, hl.col_start, hl.col_end)
        end
    end
end

return Uf
