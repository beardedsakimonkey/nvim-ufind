local Uf = require('ufind.Uf')
local util = require('ufind.util')
local arg = require('ufind.arg')
local ansi = require('ufind.ansi')
local highlight = require('ufind.highlight')

local api = vim.api

local M = {}

---@class UfindConfig
M.default_config = {
    -- Called when selecting an item to open. `action` is the name of the table
    -- key corresponding to the key that was pressed. (eg. 'edit')
    ---@type fun(action: string, lines: string[])
    on_complete = function(action, lines)
        for i, line in ipairs(lines) do
            if i == #lines then  -- execute action
                vim.cmd(action .. ' ' .. vim.fn.fnameescape(line))
            else  -- create a buffer
                local buf = vim.fn.bufnr(line, true)
                vim.bo[buf].buflisted = true
            end
        end
    end,

    -- Returns custom highlight ranges to highlight the result line.
    ---@alias UfindHighlightRange {col_start: number, col_end: number, hl_group: string}
    ---@type boolean | (fun(line: string): UfindHighlightRange[])
    get_highlights = false,

    -- Function to override the default matcher with. If `query` is contained in `str`, it
    -- should return a list of positions and a score. Otherwise, it returns nil. The higher the
    -- score, the better the match.
    ---@type fun(str: string, query: string): (number[],number)|nil
    matcher = require('ufind.matcher.default'),

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
        -- The name of an action can be anything, but it should be handled in `on_complete`.
        actions = {
            edit = '<CR>',
            split = '<C-s>',
            vsplit = '<C-v>',
            tabedit = '<C-t>',
        },
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

function validate_config(config)
    for k, _ in pairs(config) do
        if M.default_config[k] == nil then
            util.warnf('Invalid config key `config.%s`', k)
        end
    end
    if config.layout then
        for k, _ in pairs(config.layout) do
            if M.default_config.layout[k] == nil then
                util.warnf('Invalid config key `config.layout.%s`', k)
            end
        end
    end
    if config.keymaps then
        for k, _ in pairs(config.keymaps) do
            if M.default_config.keymaps[k] == nil then
                util.warnf('Invalid config key `config.keymap.%s`', k)
            end
        end
    end
end

---@param source string[] | string | fun():string,string[]?
---@param config UfindConfig?
function M.open(source, config)
    vim.validate({
        source = {source, {'table', 'string', 'function'}},
        config = {config, 'table', true},
    })
    validate_config(config)
    config = vim.tbl_deep_extend('keep', config or {}, M.default_config)
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
        uf:move_cursor(-math.huge)  -- move cursor to top
        uf:set_virt_text(#uf.matches .. ' / ' .. #lines .. (done and '' or '…'))
        -- Perf: if the viewport is already full with lines, and we're redrawing from stdout/exit of
        -- a command, avoid redrawing. (if the user has queried before the command completed, we
        -- still redraw via `on_lines`)
        local is_vp_full = api.nvim_buf_line_count(uf.result_buf) == uf:get_vp_height()
        if not (is_vp_full and is_cmd) then
            uf:redraw_results()
        end
    end

    ---@diagnostic disable-next-line: redefined-local
    local function get_matches(lines)
        local lines_noansi = config.ansi and vim.tbl_map(ansi.strip, lines) or lines
        return require'ufind.query'.match(uf.queries, lines_noansi, scopes, config.matcher)
    end

    if type(source) == 'string' or type(source) == 'function' then
        local sched_redraw = util.schedule_wrap_t(redraw)
        local on_stdout = function(chunk)
            local init = #lines
            local new_lines = vim.split(chunk, '\n', {trimempty = true})
            for i = 1, #new_lines do
                lines[#lines+1] = new_lines[i]
            end
            local new_matches = get_matches(new_lines)
            for i = 1, #new_matches do
                new_matches[i].index = new_matches[i].index + init
                uf.matches[#uf.matches+1] = new_matches[i]
            end
            -- Re-sorting matches is too slow for such a hot path. We'll do it in on_exit instead.
            sched_redraw(true)
        end
        local function on_exit()
            done = true
            local has_query = util.tbl_some(function(query) return query ~= "" end, uf.queries)
            if has_query then
                table.sort(uf.matches, function(a, b) return a.score > b.score end)
            end
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

    for i, buf in ipairs(uf.input_bufs) do
        -- Note: `on_lines` gets called immediately because of setting the prompt
        api.nvim_buf_attach(buf, false, {
            on_lines = function()
                uf.queries[i] = uf.get_query(buf)  -- update stored queries
                uf.matches = get_matches(lines)  -- store matches for when we scroll
                -- TODO: should we cancel previous redraw?
                vim.schedule(function() redraw(false) end)
            end
        })
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
    validate_config(config)
    config = vim.tbl_deep_extend('keep', config or {}, M.default_config)
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

    local sched_redraw = util.schedule_wrap_t(function()
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        uf:set_virt_text(#uf.matches .. (done and '' or '…'))
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
        uf.matches = {}
        sched_redraw()  -- clear results in case of no stdout
        local pid
        local function on_stdout(chunk)
            if pid ~= cur_pid then return end  -- ignore if a new job has started
            local new_matches = vim.split(chunk, '\n', {trimempty = true})
            for i = 1, #new_matches do  -- store all matches for when we scroll
                table.insert(uf.matches, new_matches[i])
            end
            sched_redraw()
        end
        local function on_exit()
            if pid ~= cur_pid then return end  -- ignore if a new job has started
            done = true
            sched_redraw()  -- redraw virt text without loading indicator
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
