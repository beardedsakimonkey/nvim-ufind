local view = require('ufind.view')
local util = require('ufind.util')

local api = vim.api

local Ufind = {
    get_selected_item = function() error('Not implemented') end,
}

function Ufind.new(on_complete, num_groups)
    local o = {}
    setmetatable(o, {__index = Ufind})

    num_groups = num_groups or 1
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
    end

    o.on_complete = on_complete
    o.orig_win = api.nvim_get_current_win()
    o.result_buf = api.nvim_create_buf(false, true)
    o.input_win, o.result_win = view.create_wins(o.input_bufs[1], o.result_buf)
    o.vimresized_auid = view.handle_vimresized(o.input_win, o.result_win)

    o.match_ns = api.nvim_create_namespace('ufind/match')
    o.line_ns = api.nvim_create_namespace('ufind/line')
    o.virt_ns = api.nvim_create_namespace('ufind/virt')

    for i = 1, #o.input_bufs do
        o:setup_keymaps(o.input_bufs[i])
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


function Ufind.get_query(buf)
    local buf_lines = api.nvim_buf_get_lines(buf, 0, 1, true)
    local query = buf_lines[1]
    local prompt = vim.fn.prompt_getprompt(buf)
    return query:sub(1 + #prompt)  -- trim prompt from the query
end


function Ufind:get_queries()
    return vim.tbl_map(self.get_query, self.input_bufs)
end


function Ufind:setup_keymaps(buf)
    util.keymap(buf, {'i', 'n'}, '<Esc>', function() self:quit() end)
    util.keymap(buf, 'i', '<CR>', function() self:open_result('edit') end)
    util.keymap(buf, 'i', '<C-l>', function() self:open_result('vsplit') end)
    util.keymap(buf, 'i', '<C-s>', function() self:open_result('split') end)
    util.keymap(buf, 'i', '<C-t>', function() self:open_result('tabedit') end)
    util.keymap(buf, 'i', '<C-j>', function() self:move_cursor(1) end)
    util.keymap(buf, 'i', '<C-k>', function() self:move_cursor(-1) end)
    util.keymap(buf, 'i', '<Down>', function() self:move_cursor(1) end)
    util.keymap(buf, 'i', '<Up>', function() self:move_cursor(-1) end)
    util.keymap(buf, 'i', '<C-f>', function() self:move_cursor_page(true,  true) end)
    util.keymap(buf, 'i', '<C-b>', function() self:move_cursor_page(false, true) end)
    util.keymap(buf, 'i', '<PageUp>', function() self:move_cursor_page(true,  false) end)
    util.keymap(buf, 'i', '<PageDown>', function() self:move_cursor_page(false, false) end)
    util.keymap(buf, 'i', '<Home>', function() self:set_cursor(1) end)
    util.keymap(buf, 'i', '<End>', function() self:set_cursor(api.nvim_buf_line_count(self.result_buf)) end)
    util.keymap(buf, 'i', '<C-n>', function() self:switch_input_buf(true) end)
    util.keymap(buf, 'i', '<C-p>', function() self:switch_input_buf(false) end)
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
            virt_text = {{text, 'Comment'}},
            virt_text_pos = 'right_align'
        })
    end
end

return {Ufind = Ufind}
