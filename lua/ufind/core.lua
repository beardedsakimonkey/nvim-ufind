local view = require('ufind.view')
local util = require('ufind.util')

local api = vim.api

---@class Ufind
---@field cur_input number
---@field input_bufs number[]
---@field on_complete fun(string, any)
---@field orig_win number
---@field result_buf number
---@field input_win number
---@field result_win number
---@field vimresized_auid number
---@field match_ns number
---@field line_ns number
---@field virt_ns number
local Ufind = {
    get_selected_item = function() error('Not implemented') end,
}

function Ufind.new(opt)
    local o = {}
    setmetatable(o, {__index = Ufind})

    local num_groups = opt.num_groups or 1
    o.cur_input = 1
    o.input_bufs = {}

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
    o.result_buf = api.nvim_create_buf(false, true)
    o.input_win, o.result_win = view.create_wins(o.input_bufs[1], o.result_buf, opt.layout)
    o.vimresized_auid = view.handle_vimresized(o.input_win, o.result_win, opt.layout)

    o.match_ns = api.nvim_create_namespace('ufind/match')
    o.line_ns = api.nvim_create_namespace('ufind/line')
    o.virt_ns = api.nvim_create_namespace('ufind/virt')

    for i = 1, #o.input_bufs do
        o:setup_keymaps(o.input_bufs[i], opt.keymaps)
    end

    return o
end


function Ufind:switch_input_buf(is_forward)
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


function Ufind:set_cursor(line)
    api.nvim_win_set_cursor(self.result_win, {line, 0})
end


function Ufind:move_cursor(offset)
    local cursor = api.nvim_win_get_cursor(self.result_win)
    local old_row = cursor[1]
    local line_count = api.nvim_buf_line_count(self.result_buf)
    local new_row = util.clamp(old_row+offset, 1, line_count)
    self:set_cursor(new_row)
end


function Ufind:move_cursor_page(is_up, is_half)
    local win = api.nvim_win_get_config(self.result_win)
    local offset = (win.height * (is_up and -1 or 1)) / (is_half and 2 or 1)
    self:move_cursor(offset)
end


function Ufind:quit()
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


function Ufind:open_result(cmd)
    local item = self:get_selected_item()
    self:quit()  -- cleanup first in case `on_complete` opens another finder
    self.on_complete(cmd, item)
end


---@return string
function Ufind.get_query(buf)
    local buf_lines = api.nvim_buf_get_lines(buf, 0, 1, true)
    local query = buf_lines[1]
    local prompt = vim.fn.prompt_getprompt(buf)
    return query:sub(1 + #prompt)  -- trim prompt from the query
end


---@return string[]
function Ufind:get_queries()
    return vim.tbl_map(self.get_query, self.input_bufs)
end


function Ufind:setup_keymaps(buf, keymaps)
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
            util.keymap('i', v, function() self:move_cursor(-1) end, opts)
        elseif k == 'down' then
            util.keymap('i', v, function() self:move_cursor(1) end, opts)
        elseif k == 'page_up' then
            util.keymap('i', v, function() self:move_cursor_page(true, true) end, opts)
        elseif k == 'page_down' then
            util.keymap('i', v, function() self:move_cursor_page(false,  true) end, opts)
        elseif k == 'home' then
            util.keymap('i', v, function() self:set_cursor(1) end, opts)
        elseif k == 'end' then
            util.keymap('i', v, function() self:set_cursor(api.nvim_buf_line_count(self.result_buf)) end, opts)
        elseif k == 'prev_scope' then
            util.keymap('i', '<C-p>', function() self:switch_input_buf(false) end, opts)
        elseif k == 'next_scope' then
            util.keymap('i', '<C-n>', function() self:switch_input_buf(true) end, opts)
        else
            util.err(('Invalid keymap name %q'):format(k))
        end
    end
end


function Ufind:use_hl_matches(matches)
    api.nvim_buf_clear_namespace(self.result_buf, self.match_ns, 0, -1)
    for i, match in ipairs(matches) do
        for _, pos in ipairs(match.positions) do
            api.nvim_buf_add_highlight(self.result_buf, self.match_ns, 'UfindMatch', i-1, pos-1, pos)
        end
    end
end


function Ufind:use_virt_text(text)
    for _, buf in ipairs(self.input_bufs) do
        api.nvim_buf_clear_namespace(buf, self.virt_ns, 0, -1)
        api.nvim_buf_set_extmark(buf, self.virt_ns, 0, -1, {
            virt_text = {{text, 'UfindResultCount'}},
            virt_text_pos = 'right_align'
        })
    end
end

return {Ufind = Ufind}
