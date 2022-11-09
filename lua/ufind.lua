local core = require('ufind.core')
local util = require('ufind.util')

local api = vim.api
local uv = vim.loop

-- The entrypoint for opening a finder window.
-- `items`: a sequential table of any type.
-- `config`: an optional table containing:
--   `get_value`: a function that converts an item to a string to be passed to the fuzzy filterer.
--   `get_highlights`: a function that returns highlight ranges to highlight the result line.
--   `on_complete`: a function that's called when selecting an item to open.
--   `pattern`: a regex with capture groups where each group will be queried individually
--
-- More formally:
--   type items = array<'item>
--   type config? = {
--     get_value?: 'item => string,
--     get_highlights?: ('item, string) => ?array<{hl_group, col_start, col_end}>,
--     on_complete?: ('edit' | 'split' | 'vsplit' | 'tabedit', 'item) => nil,
--     pattern?: string,
--     layout?: {
--       border? = 'none',
--       height? = 0.8,
--       width? = 0.7,
--     },
--   }
--
-- Example:
--   require'ufind'.open({'~/foo', '~/bar'})
--
--   -- using a custom data structure
--   require'ufind'.open({{path='/home/blah/foo', label='foo'}},
--                       { get_value = function(item)
--                           return item.label
--                         end,
--                         on_complete = function(cmd, item)
--                           vim.cmd(cmd .. item.path)
--                         end })
local function open(items, config)
    assert(type(items) == 'table')
    config = vim.tbl_deep_extend('keep', config or {}, {
        get_value = function(item) return item end,
        get_highlights = nil,
        on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
        pattern = '^(.*)$',
        layout = {
            border = 'none',
            height = 0.8,
            width = 0.7,
        },
    })
    local pattern, num_groups = util.inject_empty_captures(config.pattern)
    local uf = core.Ufind.new({
        on_complete = config.on_complete,
        num_groups = num_groups,
        layout = config.layout,
    })

    -- Mapping from match index (essentially the line number of the selected
    -- result) to item index (the index of the corresponding item in  `items`).
    -- This is needed by `open_result` to pass the selected item to `on_complete`.
    local match_to_item = {}

    function uf:get_selected_item()
        local cursor = api.nvim_win_get_cursor(self.result_win)
        local row = cursor[1]
        local item_idx = match_to_item[row]
        local item = items[item_idx]
        return item
    end

    local lines = vim.tbl_map(function(item)
        return config.get_value(item) -- TODO: warn on nil?
    end, items)

    local function use_hl_lines(matches)
        if not config.get_highlights then return end
        api.nvim_buf_clear_namespace(uf.result_buf, uf.line_ns, 0, -1)
        for i, match in ipairs(matches) do
            local hls = config.get_highlights(items[match.index], lines[match.index])
            for _, hl in ipairs(hls or {}) do
                api.nvim_buf_add_highlight(uf.result_buf, uf.line_ns, hl[1], i-1, hl[2], hl[3])
            end
        end
    end

    local function on_lines()
        if not api.nvim_buf_is_valid(uf.result_buf) then  -- window has been closed
            return
        end
        uf:set_cursor(1)
        local matches = require('ufind.fuzzy_filter').filter(uf:get_queries(), lines, pattern)
        api.nvim_buf_set_lines(uf.result_buf, 0, -1, true, vim.tbl_map(function(match)
            return lines[match.index]
        end, matches))
        use_hl_lines(matches)
        uf:use_hl_matches(matches)
        uf:use_virt_text(#matches .. ' / ' .. #items)

        local new_match_to_item = {}
        for i, match in ipairs(matches) do
            new_match_to_item[i] = match.index
        end
        match_to_item = new_match_to_item
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


local render_results = util.throttle(function(results, result_buf, input_buf, virt_ns, line_ns, ansi)
    vim.schedule(function()
        if not api.nvim_buf_is_valid(result_buf) then  -- window has been closed
            return
        end
        local lines = vim.split(table.concat(results), '\n', {trimempty = true})
        if ansi then
            local lines_noansi = {}
            local all_hls = {}
            for i, line in ipairs(lines) do
                local hls, line_noansi = require('ufind.ansi').parse(line, i)
                table.insert(lines_noansi, line_noansi)
                for _, hl in ipairs(hls) do
                    table.insert(all_hls, hl)
                end
            end
            api.nvim_buf_set_lines(result_buf, 0, -1, true, lines_noansi)
            api.nvim_buf_clear_namespace(result_buf, line_ns, 0, -1)
            for _, hl in ipairs(all_hls) do
                local exists = pcall(api.nvim_get_hl_by_name, hl.hl_group, true)
                if not exists then
                    api.nvim_set_hl(0, hl.hl_group, {
                        fg = hl.fg,
                        bg = hl.bg,
                        ctermfg = hl.fg,
                        ctermbg = hl.bg,
                        bold = hl.bold,
                        italic = hl.italic,
                        underline = hl.underline,
                        reverse = hl.reverse,
                    })
                end
                api.nvim_buf_add_highlight(result_buf, line_ns, hl.hl_group, hl.line-1, hl.col_start-1, hl.col_end-1)
            end
        else
            api.nvim_buf_set_lines(result_buf, 0, -1, true, lines)
        end
        -- Set virttext
        api.nvim_buf_clear_namespace(input_buf, virt_ns, 0, -1)
        api.nvim_buf_set_extmark(input_buf, virt_ns, 0, -1, {
            virt_text = {{tostring(#lines), 'Comment'}},
            virt_text_pos = 'right_align'
        })
    end)
end)


--   type getcmd = (string) => string, array<string>
--   type config? = {
--     get_highlights?: (string) => ?array<{hl_group, col_start, col_end}>,
--     on_complete?: ('edit' | 'split' | 'vsplit' | 'tabedit', string) => nil,
--     ansi?: boolean,
--     layout?: {
--       border? = 'none',
--       height? = 0.8,
--       width? = 0.7,
--     },
--   }
local function open_live(getcmd, config)
    assert(type(getcmd) == 'function')
    config = vim.tbl_deep_extend('keep', config or {}, {
        get_highlights = nil,
        on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
        ansi = false,
        layout = {
            border = 'none',
            height = 0.8,
            width = 0.7,
        },
    })
    local uf = core.Ufind.new({on_complete = config.on_complete, layout = config.layout})

    function uf:get_selected_item()
        local cursor = api.nvim_win_get_cursor(self.result_win)
        local row = cursor[1]
        local lines = api.nvim_buf_get_lines(self.result_buf, row-1, row, false)
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

    local function on_lines()
        uf:set_cursor(1)
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
                render_results({}, uf.result_buf, uf.input_bufs[1], uf.virt_ns, uf.line_ns, config.ansi)
            end
            handle:close()
        end)
        prev_handle = handle
        stdout:read_start(function(err, chunk)  -- on stdout
            assert(not err, err)
            if chunk then
                table.insert(stdoutbuf, chunk)
                render_results(stdoutbuf, uf.result_buf, uf.input_bufs[1], uf.virt_ns, uf.line_ns, config.ansi)
            end
        end)
        stderr:read_start(function(err, chunk)  -- on stderr
            assert(not err, err)
            if chunk then
                table.insert(stderrbuf, chunk)
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
