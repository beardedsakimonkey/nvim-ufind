local core = require('ufind.core')
local util = require('ufind.util')

local api = vim.api
local uv = vim.loop

---@alias UfGetValue fun(item: any): string
---@alias UfGetHighlights fun(item: any, line: string): {1: string, 2: number, 3: number}?
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
    ---@type UfLayout
    layout = default_layout,
    keymaps = default_keymaps,
}


local function inject_empty_captures(pat)
    local n = 0  -- number of captures found
    local sub = string.gsub(pat, '%%?%b()', function(match)
        -- TODO: we shouldn't inject for [(]%)
        if vim.endswith(match, '()') or  -- (), %b()
            vim.startswith(match, '%(') then  -- %(
            return
        end
        n = n + 1
        return '()' .. match
    end)
    assert(n ~= 0, ('Expected at least one capture in pattern %q'):format(pat))
    return sub, n
end


---@param items any A sequential table of any type.
---@param config? UfOpenConfig
local function open(items, config)
    assert(type(items) == 'table')
    config = vim.tbl_deep_extend('keep', config or {}, open_defaults)
    local pattern, num_captures = inject_empty_captures(config.pattern)
    local uf = core.Uf.new({
        on_complete = config.on_complete,
        num_inputs = num_captures,
        layout = config.layout,
        keymaps = config.keymaps,
    })

    function uf:get_selected_item()
        local cursor = self:get_cursor()
        local matches = self:get_visible_matches()
        return items[matches[cursor].index]
    end

    local lines = vim.tbl_map(function(item)
        return config.get_value(item) -- TODO: warn on nil?
    end, items)

    local function use_hl_lines()
        if not config.get_highlights then
            return
        end
        api.nvim_buf_clear_namespace(uf.result_buf, uf.line_ns, 0, -1)
        for i, match in ipairs(uf:get_visible_matches()) do
            local hls = config.get_highlights(items[match.index], lines[match.index])
            for _, hl in ipairs(hls or {}) do
                api.nvim_buf_add_highlight(uf.result_buf, uf.line_ns, hl[1], i-1, hl[2], hl[3])
            end
        end
    end

    function uf:redraw_results()
        api.nvim_buf_set_lines(self.result_buf, 0, -1, true, vim.tbl_map(function(match)
            return lines[match.index]
        end, self:get_visible_matches()))
        use_hl_lines()
        self:use_hl_matches()
    end

    local function on_lines()
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local matches = require('ufind.fuzzy_filter').filter(uf:get_queries(), lines, pattern)
        uf.matches = matches  -- store matches for when we scroll
        uf:move_cursor(-math.huge)  -- move cursor to top
        uf:redraw_results()  -- always redraw

        uf:use_virt_text(#matches .. ' / ' .. #items)
    end

    for _, buf in ipairs(uf.input_bufs) do
        -- `on_lines` can be called in various contexts wherein textlock could prevent
        -- changing buffer contents and window layout. Use `schedule` to defer such
        -- operations to the main loop.
        -- NOTE: `on_lines` gets called immediately because of setting the prompt
        api.nvim_buf_attach(buf, false, {on_lines = vim.schedule_wrap(on_lines)})
    end

    vim.cmd('startinsert')
end


---@class UfOpenLiveConfig
local open_live_defaults = {
    ---@type UfGetHighlights
    get_highlights = nil,
    ---@type UfOnComplete
    on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
    ansi = false, -- whether to parse ansi escape codes
    ---@type UfLayout
    layout = default_layout,
    keymaps = default_keymaps,
}


---@param getcmd fun(query: string): string,string[]
---@param config? UfOpenLiveConfig
local function open_live(getcmd, config)
    assert(type(getcmd) == 'function')
    config = vim.tbl_deep_extend('keep', config or {}, open_live_defaults)
    require'ufind.ansi'.add_hls()

    local uf = core.Uf.new({
        on_complete = config.on_complete,
        layout = config.layout,
        keymaps = config.keymaps,
    })

    function uf:get_selected_item()
        local cursor = self:get_cursor()
        local lines = api.nvim_buf_get_lines(self.result_buf, cursor-1, cursor, false)
        return lines[1]
    end

    local prev_handle

    local function on_unload()
        if prev_handle and prev_handle:is_active() then
            prev_handle:kill(uv.constants.SIGTERM)
        end
    end
    api.nvim_create_autocmd('BufUnload', {
        callback = on_unload,
        buffer = uf.input_buf,
        once = true,  -- for some reason, BufUnload fires twice otherwise
    })

    function uf:redraw_results()
        if config.ansi then
            local lines = {}
            local all_hls = {}
            for i, line in ipairs(self:get_visible_matches()) do
                local line_noansi, hls = require('ufind.ansi').parse(line, i)
                lines[#lines+1] = line_noansi
                for _, hl in ipairs(hls) do -- flatten
                    all_hls[#all_hls+1] = hl
                end
            end
            api.nvim_buf_clear_namespace(self.result_buf, self.line_ns, 0, -1)
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, lines)
            -- Note: need to add highlights *after* buf_set_lines
            for _, hl in ipairs(all_hls) do
                api.nvim_buf_add_highlight(self.result_buf, self.line_ns, hl.hl_group, hl.line-1, hl.col_start-1, hl.col_end-1)
            end
        else
            api.nvim_buf_set_lines(self.result_buf, 0, -1, true, self:get_visible_matches())
        end
    end

    -- Note: hot path (called on every chunk of stdout)
    local render_results = util.schedule_wrap_t(function(results)
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        local lines = vim.split(table.concat(results), '\n', {trimempty = true})
        uf.matches = lines  -- store matches for when we scroll
        uf:redraw_results()
        uf:use_virt_text(tostring(#lines))
    end)

    local function on_lines()
        uf:move_cursor(-math.huge)  -- move cursor to top
        if prev_handle and prev_handle:is_active() then
            prev_handle:kill(uv.constants.SIGTERM)
            -- Don't close the handle; that'll happen in on_exit
        end
        local stdout, stderr = uv.new_pipe(), uv.new_pipe()
        local stdoutbuf, stderrbuf = {}, {}
        local query = uf.get_query(uf.input_bufs[1])
        local cmd, args = getcmd(query)

        local handle
        handle = uv.spawn(cmd, {
            stdio = {nil, stdout, stderr},
            args = args,
        }, function(exit_code, signal)  -- on exit
            if next(stderrbuf) ~= nil then
                util.err(table.concat(stderrbuf))
            end
            if exit_code ~= 0 and signal ~= uv.constants.SIGTERM then
                render_results({})
            end
            handle:close()
        end)
        prev_handle = handle
        stdout:read_start(function(err, chunk)  -- on stdout
            assert(not err, err)
            if chunk then
                stdoutbuf[#stdoutbuf+1] = chunk
                render_results(stdoutbuf)
            end
        end)
        stderr:read_start(function(err, chunk)  -- on stderr
            assert(not err, err)
            if chunk then
                stderrbuf[#stderrbuf+1] = chunk
            end
        end)
    end

    api.nvim_buf_attach(uf.input_bufs[1], false, {on_lines = on_lines})
    vim.cmd('startinsert')
end


return {
    open = open,
    open_live = open_live,
}
