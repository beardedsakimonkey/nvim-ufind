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
    ---@alias UfindHighlightRange {col_start: number, col_end: number, hl_group: string}
    ---@type fun(line: string): UfindHighlightRange[]?
    get_highlights = nil,
    -- Lua pattern with capture groups that defines scopes that will be queried individually.
    scopes = '^(.*)$',
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
    local scopes, num_captures = arg.inject_empty_captures(config.scopes)
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

    local done = false  -- job has exited

    local function redraw(is_cmd)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines_noansi = config.ansi and vim.tbl_map(ansi.strip, lines) or lines
        -- TODO: we don't need to refilter everything on every stdout
        local matches = require'ufind.query'.match(uf:get_queries(), lines_noansi, scopes)
        uf.matches = matches  -- store matches for when we scroll
        uf:move_cursor(-math.huge)  -- move cursor to top
        uf:set_virt_text(#matches .. ' / ' .. #lines .. (done and '' or '…'))
        -- Perf: if the viewport is already full with lines, and we're redrawing from stdout/exit of
        -- a command, avoid redrawing. (if the user has queried before the command completed, we
        -- still redraw via `on_lines`)
        local is_vp_full = api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()
        if not (is_vp_full and is_cmd) then
            uf:redraw_results()
        end
    end

    if type(source) == 'string' or type(source) == 'function' then
        local sched_redraw = util.schedule_wrap_t(redraw)
        local function on_stdout(stdoutbuf)
            lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
            sched_redraw(true)
        end
        local function on_exit()
            done = true
            sched_redraw(true)  -- redraw virt text without loading indicator
        end
        local cmd, args
        if type(source) == 'string' then
            cmd, args = arg.split_cmd(source)
        else
            cmd, args = source()
        end
        local kill_job = util.spawn(cmd, args or {}, on_stdout, on_exit)

        uf:on_bufunload(function()
            if kill_job then kill_job() end
        end)
    else
        done = true
    end

    -- `on_lines` can be called in various contexts wherein textlock could prevent changing buffer
    -- contents and window layout. Use `schedule` to defer such operations to the main loop.
    local opts = { on_lines = vim.schedule_wrap(function() redraw(false) end) }
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

    local done = false  -- current job has exited
    local has_drawn = false  -- current job has redrawn at least once

    local sched_redraw = util.schedule_wrap_t(function(stdoutbuf)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines = vim.split(table.concat(stdoutbuf), '\n', {trimempty = true})
        uf.matches = lines  -- store matches for when we scroll
        uf:set_virt_text(#lines .. (done and '' or '…'))
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
    -- Whenever on_lines fires, we kill the previous job. However, we may still receive on_exit for
    -- the stale job. We track the pid of the current job to ignore stale on_exit's.
    local cur_pid

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
        local pid
        local function on_exit(stdoutbuf)
            if pid ~= cur_pid then return end  -- ignore if a new job has started
            done = true
            sched_redraw(stdoutbuf)  -- redraw virt text without loading indicator
        end
        has_drawn = false
        done = false
        kill_job, pid = util.spawn(cmd, args or {}, on_stdout, on_exit)
        cur_pid = pid
    end

    uf:on_bufunload(function()
        if kill_job then kill_job() end
    end)

    api.nvim_buf_attach(uf.input_bufs[1], false, {on_lines = on_lines})
    vim.cmd('startinsert')
end

return M
