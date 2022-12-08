local Uf = require('ufind.Uf')
local util = require('ufind.util')
local arg = require('ufind.arg')
local ansi = require('ufind.ansi')
local highlight = require('ufind.highlight')

local api = vim.api

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
    ---@alias UfHighlightRange {col_start: number, col_end: number, hl_group: string}
    ---@type fun(line: string): UfHighlightRange[]?
    get_highlights = nil,
    -- Lua pattern with capture groups that defines scopes that will be queried individually.
    pattern = '^(.*)$',
    -- Whether to parse ansi escape codes.
    ansi = false,
    -- Initial query to use when first opened.
    initial_query = '',
    -- Initial scope to use when first opened.
    initial_scope = 1,
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
    highlight.setup(config.ansi)
    local pattern, num_captures = arg.inject_empty_captures(config.pattern)
    local uf = Uf.new(config, num_captures)

    -- Note: lines may contain ansi codes
    local lines = type(source) == 'table' and source or {}

    function uf:get_line(i)
        return lines[i]
    end

    function uf.get_line_from_match(match)
        return lines[match.index]
    end

    -- match index to global index (the index to `lines`)
    function uf:gidx(match_idx)
        return self.matches[match_idx].index
    end

    ---@diagnostic disable-next-line: unused-local
    function uf:is_selected(i, match)
        return self.selections[match.index] or false
    end

    local is_loading = false

    local function on_lines(is_subs_chunk)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        -- Strip ansi for filtering
        local lines_noansi = config.ansi and vim.tbl_map(ansi.strip, lines) or lines
        -- TODO: we don't need to refilter everything on every stdout
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

    if type(source) == 'string' or type(source) == 'function' then
        local on_lines_t = util.schedule_wrap_t(on_lines)
        local function on_stdout(stdoutbuf)
            lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
            local is_subs_chunk = #stdoutbuf > 1
            on_lines_t(is_subs_chunk)
        end
        is_loading = true
        local function on_exit()
            is_loading = false
            on_lines_t(true)  -- re-render virt text without loading indicator
        end
        local cmd, args
        if type(source) == 'string' then
            cmd, args = arg.split_cmd(source)
        else
            cmd, args = source()
        end
        local kill_job = util.spawn(cmd, args or {}, on_stdout, on_exit)

        api.nvim_create_autocmd('BufUnload', {
            callback = function()
                if kill_job then kill_job() end
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
    highlight.setup(config.ansi)
    local uf = Uf.new(config)

    function uf:get_line(i)
        return self.matches[i]
    end

    function uf.get_line_from_match(match)
        return match
    end

    function uf:gidx(idx)
        return idx
    end

    ---@diagnostic disable-next-line: unused-local
    function uf:is_selected(i, match)
        return self.selections[self.top + i - 1] or false
    end

    local exited = false  -- current job has exited
    local has_drawn = false  -- current job has redrawn at least once

    local sched_redraw = util.schedule_wrap_t(function(stdoutbuf)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
        uf.matches = lines  -- store matches for when we scroll
        uf:use_virt_text(tostring(#lines) .. (exited and '' or '…'))
        -- Perf: if the viewport is already full with lines, and we've already redrawn at least once
        -- since the last spawn, avoid redrawing.
        -- Note that we can't check `#stdoutbuf > 1` do determine if we've already redrawn because
        -- this function is scheduled, so the first redraw might not be for the first stdout chunk.
        local is_vp_full = api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()
        if not (is_vp_full and has_drawn) then
            uf:redraw_results()
            has_drawn = true
        end
    end)

    local kill_job

    local function on_lines()
        uf:move_cursor(-math.huge)  -- move cursor to top
        if kill_job then kill_job() end  -- kill previous job if active
        uf.selections = {}  -- reset multiselections
        local query = uf.get_query(uf.input_bufs[1])
        local cmd, args
        if type(source) == 'string' then
            cmd, args = arg.split_cmd(source)
            args[#args+1] = query
        else
            cmd, args = source(query)
        end
        sched_redraw({})  -- clear results in case of no stdout
        local function on_stdout(stdoutbuf)
            sched_redraw(stdoutbuf)
        end
        local function on_exit(stdoutbuf)
            exited = true
            sched_redraw(stdoutbuf)  -- re-render virt text without loading indicator
        end
        exited = false
        has_drawn = false
        kill_job = util.spawn(cmd, args or {}, on_stdout, on_exit)
    end

    api.nvim_create_autocmd('BufUnload', {
        callback = function()
            if kill_job then kill_job() end
        end,
        buffer = uf.input_buf,
        once = true,  -- for some reason, BufUnload fires twice otherwise
    })

    api.nvim_buf_attach(uf.input_bufs[1], false, {on_lines = on_lines})
    vim.cmd('startinsert')
end

return M
