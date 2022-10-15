local api = vim.api

local PROMPT = '> '

local function get_win_layouts()
  -- Size of the window
  local height = math.floor(vim.go.lines * 0.8)
  local width = math.floor(vim.go.columns * 0.7)
  -- Position of the window
  local row = math.ceil((vim.go.lines - height) / 2)
  local col = math.ceil((vim.go.columns - width) / 2)
  -- Height of the input window
  local input_height = 1
  local input_win = {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = 1,
  }
  local result_win = {
    relative = 'editor',
    row = (input_height + row),
    col = col,
    width = width,
    height = (height - input_height),
  }
  return input_win, result_win
end

local function create_wins(input_buf, result_buf)
  local input_win_layout, result_win_layout = get_win_layouts()
  local input_win = api.nvim_open_win(
    input_buf,
    true, -- enter
    vim.tbl_extend('force', {style = 'minimal'}, input_win_layout)
  )
  local result_win = api.nvim_open_win(
    result_buf,
    false, -- enter
    vim.tbl_extend('force', {style = 'minimal', focusable = false}, result_win_layout)
  )
  vim.wo[result_win].cursorline = true
  vim.wo[result_win].winhighlight = 'CursorLine:PmenuSel'
  return input_win, result_win
end

local function handle_vimresized(input_win, result_win)
  local function relayout()
    local input_win_layout, result_win_layout = get_win_layouts()
    api.nvim_win_set_config(input_win, input_win_layout)
    -- NOTE: This disables 'cursorline' due to style = 'minimal' window config
    api.nvim_win_set_config(result_win, result_win_layout)
    vim.wo[result_win].cursorline = true
  end
  return api.nvim_create_autocmd('VimResized', {callback = relayout})
end

local function create_bufs()
  local input_buf = api.nvim_create_buf(false, true)
  local result_buf = api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype = 'prompt'
  vim.fn.prompt_setprompt(input_buf, PROMPT)
  return input_buf, result_buf
end

local config_defaults = {
  get_value = function(item) return item end,
  get_highlights = nil,
  on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
}

-- The entrypoint for opening a finder window.
-- `items`: a sequential table of any type.
-- `config`: an optional table containing:
--   `get_value`: a function that converts an item to a string to be passed to the fuzzy filterer.
--   `get_highlights`: a function that returns highlight ranges to highlight the result line.
--   `on_complete`: a function that's called when selecting an item to open.
--
-- More formally:
--   type items = array<'item>
--   type config? = {
--     get_value?: 'item => string,
--     get_highlights?: ('item, string) => ?array<{hl_group, col_start, col_end}>,
--     on_complete?: ('edit' | 'split' | 'vsplit' | 'tabedit', 'item) => nil,
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
  local config = vim.tbl_extend('force', {}, config_defaults, config or {})
  local orig_win = api.nvim_get_current_win()
  local input_buf, result_buf = create_bufs()
  local input_win, result_win = create_wins(input_buf, result_buf)
  local vimresized_auid = handle_vimresized(input_win, result_win)

  -- Mapping from match index (essentially the line number of the selected
  -- result) to item index (the index of the corresponding item in  `items`).
  -- This is needed by `open_result` to pass the selected item to `on_complete`.
  local match_to_item = {}

  local function set_cursor(line)
    api.nvim_win_set_cursor(result_win, {line, 0})
  end

  local function move_cursor(offset)
    local cursor = api.nvim_win_get_cursor(result_win)
    local old_row = cursor[1]
    local line_count = api.nvim_buf_line_count(result_buf)
    local new_row = math.max(math.min(old_row + offset, line_count), 1)
    set_cursor(new_row)
  end

  local function move_cursor_page(is_up, is_half)
    local win = api.nvim_win_get_config(result_win)
    local offset = (win.height * (is_up and -1 or 1)) / (is_half and 2 or 1)
    move_cursor(offset)
  end

  local function quit()
    api.nvim_del_autocmd(vimresized_auid)
    if api.nvim_buf_is_valid(input_buf)  then api.nvim_buf_delete(input_buf, {}) end
    if api.nvim_buf_is_valid(result_buf) then api.nvim_buf_delete(result_buf, {}) end
    if api.nvim_win_is_valid(orig_win)   then api.nvim_set_current_win(orig_win) end
    -- Seems unneeded, but not sure why (deleting the buffer closes the window)
    if api.nvim_win_is_valid(input_win)  then api.nvim_win_close(input_win, false) end
    if api.nvim_win_is_valid(result_win) then api.nvim_win_close(result_win, false) end
  end

  local function open_result(cmd)
    local cursor = api.nvim_win_get_cursor(result_win)
    local row = cursor[1]
    local item_idx = match_to_item[row]
    local item = items[item_idx]
    quit()
    return config.on_complete(cmd, item)
  end

  local function keymap(mode, lhs, rhs)
    return vim.keymap.set(mode, lhs, rhs, {nowait = true, silent = true, buffer = input_buf})
  end

  keymap({'i', 'n'}, '<Esc>', quit) -- can use <C-c> to exit insert mode
  keymap('i', '<CR>', function() open_result('edit') end)
  keymap('i', '<C-l>', function() open_result('vsplit') end)
  keymap('i', '<C-s>', function() open_result('split') end)
  keymap('i', '<C-t>', function() open_result('tabedit') end)
  keymap('i', '<C-j>', function() move_cursor(1) end)
  keymap('i', '<C-k>', function() move_cursor(-1) end)
  keymap('i', '<Down>', function() move_cursor(1) end)
  keymap('i', '<Up>', function() move_cursor(-1) end)
  keymap('i', '<C-u>', function() move_cursor_page(true,  true) end)
  keymap('i', '<C-d>', function() move_cursor_page(false, true) end)
  keymap('i', '<PageUp>', function() move_cursor_page(true,  false) end)
  keymap('i', '<PageDown>', function() move_cursor_page(false, false) end)
  keymap('i', '<Home>', function() set_cursor(1) end)
  keymap('i', '<End>', function() set_cursor(api.nvim_buf_line_count(result_buf)) end)

  local match_ns = api.nvim_create_namespace('ufind/match')
  local line_ns = api.nvim_create_namespace('ufind/line')
  local virt_ns = api.nvim_create_namespace('ufind/virt')

  local lines = vim.tbl_map(function(item)
    return config.get_value(item)
  end, items)

  local function use_hl_matches(matches)
    api.nvim_buf_clear_namespace(result_buf, match_ns, 0, -1)
    for i, match in ipairs(matches) do
      for _, pos in ipairs(match.positions) do
        api.nvim_buf_add_highlight(result_buf, match_ns, 'UfindMatch', i-1, pos-1, pos)
      end
    end
  end

  local function use_hl_lines(matches)
    if not config.get_highlights then return end
    api.nvim_buf_clear_namespace(result_buf, line_ns, 0, -1)
    for i, match in ipairs(matches) do
      local hls = config.get_highlights(items[match.index], lines[match.index])
      for _, hl in ipairs(hls or {}) do
        api.nvim_buf_add_highlight(result_buf, line_ns, hl[1], i-1, hl[2], hl[3])
      end
    end
  end

  local function use_virt_text(text)
    api.nvim_buf_clear_namespace(input_buf, virt_ns, 0, -1)
    api.nvim_buf_set_extmark(input_buf, virt_ns, 0, -1, {virt_text = {{text, 'Comment'}}, virt_text_pos = 'right_align'})
  end

  local function get_query()
    local buf_lines = api.nvim_buf_get_lines(input_buf, 0, 1, true)
    local query = buf_lines[1]
    -- Trim prompt from the query
    return query:sub(1 + #PROMPT)
  end

  local function on_lines()
    -- Reset cursor to top
    set_cursor(1)
    -- Run the fuzzy filter
    local matches = require('ufind.fuzzy_filter').filter({get_query()}, lines)
    -- Sort matches
    table.sort(matches, function(a, b) return a.score > b.score end)
    -- Render matches
    api.nvim_buf_set_lines(result_buf, 0, -1, true, vim.tbl_map(function(match)
      return lines[match.index]
    end, matches))
    -- Render result count virtual text
    use_virt_text(#matches .. ' / ' .. #items)
    -- Highlight results
    use_hl_lines(matches)
    use_hl_matches(matches)
    -- Update match index to item index mapping
    local new_match_to_item = {}
    for i, match in ipairs(matches) do
      new_match_to_item[i] = match.index
    end
    match_to_item = new_match_to_item
  end

  -- `on_lines` can be called in various contexts wherein textlock could prevent
  -- changing buffer contents and window layout. Use `schedule` to defer such
  -- operations to the main loop.
  -- NOTE: `on_lines` gets called immediately because of setting the prompt
  api.nvim_buf_attach(input_buf, false, {on_lines = vim.schedule_wrap(on_lines)})
  vim.cmd('startinsert')
end

return {open = open}
