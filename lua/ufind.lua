local core = require('ufind.core')
local util = require('ufind.util')
local arg = require('ufind.arg')
local ansi = require('ufind.ansi')

local api = vim.api
local uv = vim.loop

---@alias UfGetValue fun(item: any): string
---@alias UfGetHighlights fun(line: string): any[]?
---@alias UfOnComplete fun(cmd: 'edit'|'split'|'vsplit'|'tabedit', item: any)

---@class UfKeymaps
local default_keymaps = {
    quit = '<Esc>',
    open = '<CR>',
    open_split = '<C-s>',
    open_vsplit = '<C-l>',
    open_tab = '<C-t>',
    up = {'<C-k>', '<Up>'},
    down = {'<C-j>', '<Down>'},
    page_up = {'<C-b>', '<PageUp>'},
    page_down = {'<C-f>', '<PageDown>'},
    home = '<Home>',
    ['end'] = '<End>',
    wheel_up = '<ScrollWheelUp>',
    wheel_down = '<ScrollWheelDown>',
    prev_scope = '<C-p>',
    next_scope = '<C-n>',
}

---@class UfLayout
local default_layout = {
    ---@type 'none'|'single'|'double'|'rounded'|'solid'|string[]
    border = 'none',
    height = 0.8,
    width = 0.7,
    input_on_top = true,
}

---@class UfOpenConfig
local open_defaults = {
    ---@type UfGetValue
    get_value = function(item) return item end,
    ---@type UfGetHighlights
    get_highlights = nil,
    ---@type UfOnComplete
    on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
    pattern = '^(.*)$',
    ansi = false,
    layout = default_layout,
    keymaps = default_keymaps,
}


---@param items_or_cmd any[]|string|fun():string,string[]?
---@param config? UfOpenConfig
local function open(items_or_cmd, config)
    vim.validate({
        items_or_cmd = {items_or_cmd, {'table', 'string', 'function'}},
        config = {config, 'table', true},
    })
    config = vim.tbl_deep_extend('keep', config or {}, open_defaults)
    if config.ansi then
        ansi.add_highlights()
    end
    local pattern, num_captures = arg.inject_empty_captures(config.pattern)
    local uf = core.Uf.new({
        on_complete = config.on_complete,
        num_inputs = num_captures,
        layout = config.layout,
        keymaps = config.keymaps,
    })

    local lines
    local t = type(items_or_cmd)
    if t == 'table' then
        lines = vim.tbl_map(function(item)
            return config.get_value(item) -- TODO: warn on nil?
        end, items_or_cmd)
    else
        lines = {}
    end

    function uf:get_selected_item()
        local cursor = self:get_cursor()
        local matches = self:get_visible_matches()
        local match = matches[cursor]
        -- Ensure user didn't hit enter on a query with no results
        if match ~= nil then
            if type(items_or_cmd) == 'table' then
                return items_or_cmd[match.index]
            else
                return lines[match.index]
            end
        end
    end

    local function use_hl_lines()
        if not config.get_highlights then
            return
        end
        for i, match in ipairs(uf:get_visible_matches()) do
            -- TODO: pass in the item if any
            local hls = config.get_highlights(lines[match.index])
            for _, hl in ipairs(hls or {}) do
                api.nvim_buf_add_highlight(uf.result_buf, uf.results_ns, hl[1], i-1, hl[2], hl[3])
            end
        end
    end

    function uf:redraw_results()
        api.nvim_buf_clear_namespace(self.result_buf, self.results_ns, 0, -1)
        ---@diagnostic disable-next-line: redefined-local
        local lines = vim.tbl_map(function(match)
            return lines[match.index]
        end, self:get_visible_matches())
        if config.ansi then
            local lines_noansi, hls = ansi.parse(lines)
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines_noansi)
            -- Note: need to add highlights *after* buf_set_lines
            for _, hl in ipairs(hls) do
                api.nvim_buf_add_highlight(self.result_buf, self.results_ns, hl.hl_group,
                    hl.line-1, hl.col_start-1, hl.col_end-1)
            end
        else
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines)
            use_hl_lines()
        end
        self:use_hl_matches()
    end

    -- `on_lines` can be called in various contexts wherein textlock could prevent changing buffer
    -- contents and window layout. Use `schedule` to defer such operations to the main loop.
    local on_lines = vim.schedule_wrap(function(is_subs_chunk)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines_noansi = config.ansi and ansi.strip(lines) or lines  -- strip ansi for filtering
        local matches = require('ufind.fuzzy_filter').filter(uf:get_queries(), lines_noansi, pattern)
        uf.matches = matches  -- store matches for when we scroll
        uf:move_cursor(-math.huge)  -- move cursor to top
        uf:use_virt_text(#matches .. ' / ' .. #lines)
        -- Perf: if we're redrawing from a subsequent chunk of stdout (ie not the initial chunk) and
        -- the viewport is already full with lines, avoid redrawing.
        if not (is_subs_chunk and api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()) then
            uf:redraw_results()
        end
    end)

    if t == 'function' or t == 'string' then
        local function on_stdout(stdoutbuf)
            lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
            local is_subs_chunk = #stdoutbuf > 1
            on_lines(is_subs_chunk)
        end
        local cmd, args
        if t == 'string' then
            cmd, args = arg.split_cmd(items_or_cmd)
        else
            cmd, args = items_or_cmd()
        end
        util.spawn(cmd, args or {}, on_stdout)
    end

    for _, buf in ipairs(uf.input_bufs) do
        -- Note: `on_lines` gets called immediately because of setting the prompt
        api.nvim_buf_attach(buf, false, {on_lines = function() on_lines(false) end})
    end

    vim.cmd('startinsert')
end


---@class UfOpenLiveConfig
local open_live_defaults = {
    ---@type UfGetHighlights
    get_highlights = nil,
    ---@type UfOnComplete
    on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
    ansi = false,
    layout = default_layout,
    keymaps = default_keymaps,
}


---@param getcmd string|fun(query: string):string,string[]?
---@param config? UfOpenLiveConfig
local function open_live(getcmd, config)
    vim.validate({
        getcmd = {getcmd, {'string', 'function'}},
        config = {config, 'table', true},
    })
    config = vim.tbl_deep_extend('keep', config or {}, open_live_defaults)
    if config.ansi then
        ansi.add_highlights()
    end

    local uf = core.Uf.new({
        on_complete = config.on_complete,
        layout = config.layout,
        keymaps = config.keymaps,
    })

    function uf:get_selected_item()
        local cursor = self:get_cursor()
        -- Grab line off the buffer because `matches` contains escape codes
        local lines = api.nvim_buf_get_lines(self.result_buf, cursor-1, cursor, false)
        if lines[1] == '' then  -- user hit enter on a query with no results
            return nil
        end
        return lines[1]
    end

    local handle

    local function kill_prev()
        if handle and handle:is_active() then
            handle:kill(uv.constants.SIGTERM)
            -- Don't close the handle; that'll happen in on_exit
        end
    end

    api.nvim_create_autocmd('BufUnload', {
        callback = kill_prev,
        buffer = uf.input_buf,
        once = true,  -- for some reason, BufUnload fires twice otherwise
    })

    function uf:redraw_results()
        if config.ansi then
            api.nvim_buf_clear_namespace(self.result_buf, self.results_ns, 0, -1)
            local lines, hls = ansi.parse(self:get_visible_matches())
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines)
            -- Note: need to add highlights *after* buf_set_lines
            for _, hl in ipairs(hls) do
                api.nvim_buf_add_highlight(self.result_buf, self.results_ns, hl.hl_group,
                    hl.line-1, hl.col_start-1, hl.col_end-1)
            end
        else
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, self:get_visible_matches())
        end
    end

    -- Note: hot path (called on every chunk of stdout)
    local render_results = util.schedule_wrap_t(function(stdoutbuf)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
        uf.matches = lines  -- store matches for when we scroll
        -- Perf: if we're redrawing from a subsequent chunk of stdout (ie not the initial chunk) and
        -- the viewport is already full with lines, avoid redrawing.
        if not (#stdoutbuf > 1 and api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()) then
            uf:redraw_results()
        end
        uf:use_virt_text(tostring(#lines))
    end)

    local function on_lines()
        uf:move_cursor(-math.huge)  -- move cursor to top
        kill_prev()  -- kill previous job if active
        local query = uf.get_query(uf.input_bufs[1])
        local cmd, args
        if type(getcmd) == 'string' then
            cmd, args = arg.split_cmd(getcmd)
            args[#args+1] = query
        else
            cmd, args = getcmd(query)
        end
        render_results({}) -- clear results in case of no stdout
        local function on_stdout(stdoutbuf)
            render_results(stdoutbuf)
        end
        handle = util.spawn(cmd, args or {}, on_stdout)
    end

    api.nvim_buf_attach(uf.input_bufs[1], false, {on_lines = on_lines})
    vim.cmd('startinsert')
end


return {
    open = open,
    open_live = open_live,
}
