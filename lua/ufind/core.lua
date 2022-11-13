local view = require('ufind.view')
local util = require('ufind.util')

local api = vim.api

---@class Uf
---@field cur_input number
---@field input_bufs number[]
---@field matches table
---@field on_complete fun(string, any)
---@field orig_win number
---@field result_buf number
---@field input_win number
---@field result_win number
---@field vimresized_auid number
---@field top number 1-indexed
---@field match_ns number
---@field line_ns number
---@field virt_ns number
local Uf = {
    get_selected_item = function() error('Not implemented') end,
    redraw_results = function() error('Not implemented') end,
}

function Uf.new(opt)
    local o = {}
    setmetatable(o, {__index = Uf})

    local num_groups = opt.num_groups or 1
    o.cur_input = 1
    o.input_bufs = {}
    o.matches = {}

    -- Create input buffers
    for _ = 1, num_groups do
        table.insert(o.input_bufs, view.create_input_buf())
    end

    -- Set prompts
    for i = 1, #o.input_bufs do
        local prompt = i .. '/' .. num_groups .. view.PROMPT
        vim.fn.prompt_setprompt(o.input_bufs[i], prompt)
        api.nvim_buf_add_highlight(o.input_bufs[i], -1, 'UfindPrompt', 0, 0, #prompt)
    end

    o.on_complete = opt.on_complete
    o.orig_win = api.nvim_get_current_win()
    o.result_buf = view.create_result_buf()
    o.input_win, o.result_win = view.create_wins(o.input_bufs[1], o.result_buf, opt.layout)
    o.vimresized_auid = view.handle_vimresized(o.input_win, o.result_win, opt.layout)

    -- Line number of the line at the top of the viewport (used for occluding
    -- lines in the results window)
    o.top = 1

    o.match_ns = api.nvim_create_namespace('ufind/match')
    o.line_ns = api.nvim_create_namespace('ufind/line')
    o.virt_ns = api.nvim_create_namespace('ufind/virt')

    for i = 1, #o.input_bufs do
        o:setup_keymaps(o.input_bufs[i], opt.keymaps)
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
    -- Clamp offset such that 1 <= cursor_abs+offset <= last
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
        -- Scroll viewport up
        --[[   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
               Scrolling up 2 lines when the cursor is at the top
               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

                         ------- 1 ------- --> cursor_abs(4) + offset(-2)
                                 ▲
             adj_cursor(-1) - 1  |  cursor_rel(1) + offset(-2) - 1
                                 ▼
                        +------- 3 -------+--> top(3)
                        |------- 1 -------|--> cursor_rel(1)
                        |                 |
                        |                 |
                        +-----------------+

             We subtract 1 from adj_cursor because cursor_rel is 1-indexed
             top = top(3) + adj_cursor(-1) - 1
             top = 1
        --]]
        self.top = self.top + adj_cursor - 1
        -- Set cursor at viewport top
        api.nvim_win_set_cursor(self.result_win, {1, 0})
        return true
    end
    -- Cursor is outside of bottom bound
    if adj_cursor > vp_height then
        -- Scroll viewport down
        self.top = self.top + adj_cursor - vp_height
        -- Set cursor at viewport bottom
        api.nvim_win_set_cursor(self.result_win, {vp_height, 0})
        return true
    end
    -- Cursor is within bounds
    api.nvim_win_set_cursor(self.result_win, {adj_cursor, 0})
    return false
end


---@param m 'up'|'down'|'page_up'|'page_down'|'home'|'end' Cursor motion
function Uf:move_cursor_and_redraw(m)
    local need_redraw
    if m == 'up' or m == 'down' then
        need_redraw = self:move_cursor(m == 'up' and -1 or 1)
    elseif m == 'page_up' or m == 'page_down' then
        local page = self:get_vp_height()
        need_redraw = self:move_cursor(m == 'page_up' and -page or page)
    elseif m == 'home' or m == 'end' then
        need_redraw = self:move_cursor(m == 'home' and -math.huge or math.huge)
    end
    if need_redraw then
        self:redraw_results()
    end
end


function Uf:quit()
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
    local item = self:get_selected_item()
    self:quit()  -- cleanup first in case `on_complete` opens another finder
    self.on_complete(cmd, item)
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
        elseif k == 'up' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'down' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'page_up' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'page_down' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'home' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'end' then
            util.keymap('i', v, function() self:move_cursor_and_redraw(k) end, opts)
        elseif k == 'prev_scope' then
            util.keymap('i', '<C-p>', function() self:switch_input_buf(false) end, opts)
        elseif k == 'next_scope' then
            util.keymap('i', '<C-n>', function() self:switch_input_buf(true) end, opts)
        else
            util.errf('Invalid keymap name %q', k)
        end
    end
end


function Uf:get_visible_matches()
    local visible_matches = {}
    local vp_height = self:get_vp_height()
    local to = math.min(self.top + vp_height, #self.matches)
    for i = self.top, to do
        table.insert(visible_matches, self.matches[i])
    end
    return visible_matches
end


function Uf:use_hl_matches()
    api.nvim_buf_clear_namespace(self.result_buf, self.match_ns, 0, -1)
    for i, match in ipairs(self:get_visible_matches()) do
        for _, pos in ipairs(match.positions) do
            api.nvim_buf_add_highlight(self.result_buf, self.match_ns, 'UfindMatch', i-1, pos-1, pos)
        end
    end
end


function Uf:use_virt_text(text)
    for _, buf in ipairs(self.input_bufs) do
        api.nvim_buf_clear_namespace(buf, self.virt_ns, 0, -1)
        api.nvim_buf_set_extmark(buf, self.virt_ns, 0, -1, {
            virt_text = {{text, 'UfindResultCount'}},
            virt_text_pos = 'right_align'
        })
    end
end


return {Uf = Uf}
