local core = require('ufind.core')
local util = require('ufind.util')
local arg = require('ufind.arg')
local ansi = require('ufind.ansi')

local api = vim.api
local uv = vim.loop

local M = {}

---@class UfindConfig
local default_config = {
    -- Called when selecting an item to open.
    ---@type fun(cmd: 'edit'|'split'|'vsplit'|'tabedit', lines: string[])
    on_complete = function(cmd, lines)
        for i, line in ipairs(lines) do
            if i == #lines then  -- open the file
                vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(line))
            else  -- create a buffer
                local buf = vim.fn.bufnr(line, true)
                vim.bo[buf].buflisted = true
            end
        end
    end,
    -- Returns custom highlight ranges to highlight the result line.
    ---@alias UfindHighlightRange {col_start: number, col_end: number, hl_group: string}
    ---@type fun(line: string): UfindHighlightRange[]?
    get_highlights = nil,
    -- Lua pattern with capture groups that defines scopes that will be queried individually.
    pattern = '^(.*)$',
    -- Whether to parse ansi escape codes.
    ansi = false,
    -- Initial query to use when first opened.
    initial_query = '',
    ---@class UfindLayout
    layout = {
        ---@type 'none'|'single'|'double'|'rounded'|'solid'|string[]
        border = 'none',
        height = 0.8,
        width = 0.7,
        input_on_top = true,
    },
    ---@class UfindKeymaps
    keymaps = {
        quit = '<Esc>',
        open = '<CR>',
        open_split = '<C-s>',
        open_vsplit = '<C-v>',
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
        toggle_select = '<Tab>',
        toggle_select_all = '<C-a>',
    },
}

---@param source string[] | string | fun():string,string[]?
---@param config UfindConfig?
function M.open(source, config)
    vim.validate({
        source = {source, {'table', 'string', 'function'}},
        config = {config, 'table', true},
    })
    config = vim.tbl_deep_extend('keep', config or {}, default_config)
    if config.ansi then
        ansi.add_highlights()
    end
    local pattern, num_captures = arg.inject_empty_captures(config.pattern)
    local uf = core.Uf.new(config, num_captures)

    -- Note: lines may contain ansi codes
    local lines = type(source) == 'table' and source or {}

    function uf:get_selected_lines()
        local idxs = {}
        if next(self.selections) ~= nil then
            for idx, _ in pairs(self.selections) do
                idxs[#idxs+1] = idx
            end
        else
            local cursor = self:get_cursor()
            local matches = self:get_visible_matches()
            idxs[#idxs+1] = matches[cursor].index
        end
        return vim.tbl_map(function(i)
            return config.ansi and ansi.strip(lines[i]) or lines[i]
        end, idxs)
    end

    -- TODO: we could avoid redundancy by only storing match indexes in `self.matches`. Then, in
    -- `use_hl_matches()`, we'd have to recompute positions.
    function uf:toggle_select()
        local idx = self.top + self:get_cursor() - 1
        local match = self.matches[idx]
        if match == nil then  -- cursor is on an empty line
            return
        end
        if self.selections[match.index] then
            self.selections[match.index] = nil
        else
            self.selections[match.index] = true
        end
        print(self.selections)
        uf:move_cursor(1)
        self:redraw_results()
    end

    function uf:toggle_select_all()
        if next(self.selections) then -- select none
            self.selections = {}
        else -- select all
            self.selections = {}
            for i = 1, #self.matches do
                self.selections[self.matches[i].index] = true
            end
        end
        self:redraw_results()
    end

    local function use_hl_lines()
        if not config.get_highlights then
            return
        end
        for i, match in ipairs(uf:get_visible_matches()) do
            local hls = config.get_highlights(lines[match.index])
            for _, hl in ipairs(hls or {}) do
                api.nvim_buf_add_highlight(uf.result_buf, uf.results_ns,
                    hl.hl_group, i-1, hl.col_start, hl.col_end)
            end
        end
    end

    function uf:redraw_results()
        api.nvim_buf_clear_namespace(self.result_buf, self.results_ns, 0, -1)
        local selected_linenrs = {}
        local visible_lines = {}
        for i, match in ipairs(self:get_visible_matches()) do
            if self.selections[match.index] then
                table.insert(selected_linenrs, i)
            end
            table.insert(visible_lines, lines[match.index])
        end
        if config.ansi then
            local lines_noansi, hls = ansi.parse(visible_lines)
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines_noansi)
            -- Note: need to add highlights *after* buf_set_lines
            for _, hl in ipairs(hls) do
                api.nvim_buf_add_highlight(self.result_buf, self.results_ns, hl.hl_group,
                    hl.line-1, hl.col_start-1, hl.col_end-1)
            end
        else
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, visible_lines)
        end
        use_hl_lines()
        self:use_hl_multiselect(selected_linenrs)
        self:use_hl_matches()
    end

    local is_loading = false

    local function on_lines(is_subs_chunk)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        -- Strip ansi for filtering
        local lines_noansi = config.ansi and vim.tbl_map(ansi.strip, lines) or lines
        local matches = require('ufind.fuzzy_filter').filter(uf:get_queries(), lines_noansi, pattern)
        uf.matches = matches  -- store matches for when we scroll
        uf:move_cursor(-math.huge)  -- move cursor to top
        uf:use_virt_text(#matches .. ' / ' .. #lines .. (is_loading and '…' or ''))
        -- Perf: if we're redrawing from a subsequent chunk of stdout (ie not the initial chunk) and
        -- the viewport is already full with lines, avoid redrawing.
        if not (is_subs_chunk and api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()) then
            uf:redraw_results()
        end
    end

    if type(source) ~= 'table' then
        local on_lines_throttled = util.schedule_wrap_t(on_lines)
        local function on_stdout(stdoutbuf)
            lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
            local is_subs_chunk = #stdoutbuf > 1
            on_lines_throttled(is_subs_chunk)
        end
        local cmd, args
        if type(source) == 'string' then
            cmd, args = arg.split_cmd(source)
        else
            cmd, args = source()
        end
        is_loading = true
        local function on_exit()
            is_loading = false
            on_lines_throttled(true)  -- re-render virt text without loading indicator
        end
        local handle = util.spawn(cmd, args or {}, on_stdout, on_exit)

        api.nvim_create_autocmd('BufUnload', {
            callback = function()
                if handle and handle:is_active() then
                    handle:kill(uv.constants.SIGTERM)
                end
            end,
            buffer = uf.input_buf,
            once = true,  -- for some reason, BufUnload fires twice otherwise
        })
    end

    -- `on_lines` can be called in various contexts wherein textlock could prevent changing buffer
    -- contents and window layout. Use `schedule` to defer such operations to the main loop.
    local opts = { on_lines = vim.schedule_wrap(function() on_lines(false) end) }
    for _, buf in ipairs(uf.input_bufs) do
        -- Note: `on_lines` gets called immediately because of setting the prompt
        api.nvim_buf_attach(buf, false, opts)
    end

    vim.cmd('startinsert')
end

---@param source string | fun(query: string):string,string[]?
---@param config UfindConfig?
function M.open_live(source, config)
    vim.validate({
        source = {source, {'string', 'function'}},
        config = {config, 'table', true},
    })
    config = vim.tbl_deep_extend('keep', config or {}, default_config)
    if config.ansi then
        ansi.add_highlights()
    end

    local uf = core.Uf.new(config)

    function uf:get_selected_lines()
        local lines = {}
        if next(self.selections) ~= nil then
            for idx, _ in pairs(self.selections) do
                lines[#lines+1] = self.matches[idx]
            end
        else
            local cursor = self:get_cursor()
            local matches = self:get_visible_matches()
            lines[#lines+1] = matches[cursor]
        end
        if config.ansi then
            return vim.tbl_map(function(line)
                return ansi.strip(line)
            end, lines)
        else
            return lines
        end
    end

    function uf:toggle_select()
        local idx = self.top + self:get_cursor() - 1
        if self.matches[idx] == nil then  -- cursor is on an empty line
            return
        end
        if self.selections[idx] then
            self.selections[idx] = nil
        else
            self.selections[idx] = true
        end
        uf:move_cursor(1)
        self:redraw_results()
    end

    function uf:toggle_select_all()
        if next(self.selections) then -- select none
            self.selections = {}
        else -- select all
            self.selections = {}
            for i = 1, #self.matches do
                self.selections[i] = true
            end
        end
        self:redraw_results()
    end

    local function use_hl_lines()
        if not config.get_highlights then
            return
        end
        for i, match in ipairs(uf:get_visible_matches()) do
            local hls = config.get_highlights(match)
            for _, hl in ipairs(hls or {}) do
                print(hl)
                api.nvim_buf_add_highlight(uf.result_buf, uf.results_ns,
                    hl.hl_group, i-1, hl.col_start, hl.col_end)
            end
        end
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
        api.nvim_buf_clear_namespace(self.result_buf, self.results_ns, 0, -1)
        local selected_linenrs = {}
        local visible_lines = {}
        for i, line in ipairs(self:get_visible_matches()) do
            if self.selections[self.top + i - 1] then
                table.insert(selected_linenrs, i)
            end
            table.insert(visible_lines, line)
        end
        if config.ansi then
            local lines_noansi, hls = ansi.parse(visible_lines)
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines_noansi)
            -- Note: need to add highlights *after* buf_set_lines
            for _, hl in ipairs(hls) do
                api.nvim_buf_add_highlight(self.result_buf, self.results_ns, hl.hl_group,
                    hl.line-1, hl.col_start-1, hl.col_end-1)
            end
        else
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, visible_lines)
        end
        use_hl_lines()
        self:use_hl_multiselect(selected_linenrs)
    end

    local is_loading = true

    local redraw = util.schedule_wrap_t(function(stdoutbuf)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
        uf.matches = lines  -- store matches for when we scroll
        uf:use_virt_text(tostring(#lines) .. (is_loading and '…' or ''))
        -- Perf: if we're redrawing from a subsequent chunk of stdout (ie not the initial chunk) and
        -- the viewport is already full with lines, avoid redrawing.
        if not (#stdoutbuf > 1 and api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()) then
            uf:redraw_results()
        end
    end)

    local function on_lines()
        uf:move_cursor(-math.huge)  -- move cursor to top
        kill_prev()  -- kill previous job if active
        uf.selections = {}  -- reset multiselections
        local query = uf.get_query(uf.input_bufs[1])
        local cmd, args
        if type(source) == 'string' then
            cmd, args = arg.split_cmd(source)
            args[#args+1] = query
        else
            cmd, args = source(query)
        end
        redraw({})  -- clear results in case of no stdout
        local function on_stdout(stdoutbuf)
            redraw(stdoutbuf)
        end
        local function on_exit(stdoutbuf)
            is_loading = false
            redraw(stdoutbuf)  -- re-render virt text without loading indicator
        end
        is_loading = true
        handle = util.spawn(cmd, args or {}, on_stdout, on_exit)
    end

    api.nvim_buf_attach(uf.input_bufs[1], false, {on_lines = on_lines})
    vim.cmd('startinsert')
end

return M
