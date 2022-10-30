local api = vim.api

local PROMPT = '> '

local function clamp(v, min, max)
  return math.min(math.max(v, min), max)
end

local function keymap(buf, mode, lhs, rhs)
  vim.keymap.set(mode, lhs, rhs, {nowait = true, silent = true, buffer = buf})
end

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

local function create_input_buf()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'prompt'
  vim.fn.prompt_setprompt(buf, PROMPT)
  return buf
end

local config_defaults = {
  get_value = function(item) return item end,
  get_highlights = nil,
  on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
  get_iter = function(line) return ipairs({line}) end,
}

-- The entrypoint for opening a finder window.
-- `items`: a sequential table of any type.
-- `config`: an optional table containing:
--   `get_value`: a function that converts an item to a string to be passed to the fuzzy filterer.
--   `get_highlights`: a function that returns highlight ranges to highlight the result line.
--   `on_complete`: a function that's called when selecting an item to open.
--   `get_iter`: a function that returns an iterator that breaks up lines into parts that are queried individually.
--
-- More formally:
--   type items = array<'item>
--   type config? = {
--     get_value?: 'item => string,
--     get_highlights?: ('item, string) => ?array<{hl_group, col_start, col_end}>,
--     on_complete?: ('edit' | 'split' | 'vsplit' | 'tabedit', 'item) => nil,
--     get_iter?: (string) => (() => number, string),
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
  config = vim.tbl_extend('force', {}, config_defaults, config or {})
  local orig_win = api.nvim_get_current_win()
  local input_buf = create_input_buf()
  local result_buf = api.nvim_create_buf(false, true)
  local input_win, result_win = create_wins(input_buf, result_buf)
  local vimresized_auid = handle_vimresized(input_win, result_win)

  -- Mapping from match index (essentially the line number of the selected
  -- result) to item index (the index of the corresponding item in  `items`).
  -- This is needed by `open_result` to pass the selected item to `on_complete`.
  local match_to_item = {}

  -- State for multiple input_bufs when using `get_iter`.
  local cur_input = 1
  local input_bufs = {input_buf}

  local function switch_input_buf(is_forward)
    local offset = is_forward and 1 or -1
    local i = cur_input + offset
    if i > #input_bufs then
      cur_input = 1
    elseif i < 1 then
      cur_input = #input_bufs
    else
      cur_input = i
    end
    api.nvim_win_set_buf(input_win, input_bufs[cur_input])
  end

  local function set_cursor(line)
    api.nvim_win_set_cursor(result_win, {line, 0})
  end

  local function move_cursor(offset)
    local cursor = api.nvim_win_get_cursor(result_win)
    local old_row = cursor[1]
    local line_count = api.nvim_buf_line_count(result_buf)
    local new_row = clamp(old_row+offset, 1, line_count)
    set_cursor(new_row)
  end

  local function move_cursor_page(is_up, is_half)
    local win = api.nvim_win_get_config(result_win)
    local offset = (win.height * (is_up and -1 or 1)) / (is_half and 2 or 1)
    move_cursor(offset)
  end

  local function quit()
    api.nvim_del_autocmd(vimresized_auid)
    for _, buf in ipairs(input_bufs) do
      if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, {force = true}) end
    end
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
    quit() -- cleanup first in case `on_complete` opens another finder
    return config.on_complete(cmd, item)
  end

  local match_ns = api.nvim_create_namespace('ufind/match')
  local line_ns = api.nvim_create_namespace('ufind/line')
  local virt_ns = api.nvim_create_namespace('ufind/virt')

  local lines = vim.tbl_map(function(item)
    -- TODO: warn on nil?
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
    for _, buf in ipairs(input_bufs) do
      api.nvim_buf_clear_namespace(buf, virt_ns, 0, -1)
      api.nvim_buf_set_extmark(buf, virt_ns, 0, -1, {
        virt_text = {{text, 'Comment'}},
        virt_text_pos = 'right_align'
      })
    end
  end

  local function get_queries()
    return vim.tbl_map(function(buf)
      local buf_lines = api.nvim_buf_get_lines(buf, 0, 1, true)
      local query = buf_lines[1]
      local prompt = vim.fn.prompt_getprompt(buf)
      return query:sub(1 + #prompt) -- trim prompt from the query
    end, input_bufs)
  end

  local function render(matches)
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

  local function on_lines()
    -- Reset cursor to top
    set_cursor(1)
    -- Run the fuzzy filter
    local matches = require('ufind.fuzzy_filter').filter(get_queries(), lines, config.get_iter)
    render(matches)
  end

  local matches, num_groups = require('ufind.fuzzy_filter').filter(get_queries(), lines, config.get_iter)

  -- Create extra input buffers
  for _ = 2, num_groups do
    local buf = create_input_buf()
    table.insert(input_bufs, buf)
  end

  -- Set prompts
  for i = 1, #input_bufs do
    local prompt = i .. '/' .. num_groups .. PROMPT
    vim.fn.prompt_setprompt(input_bufs[i], prompt)
  end

  -- Set keymaps and subscribe to on_lines
  for i = 1, #input_bufs do
    local buf = input_bufs[i]
    keymap(buf, {'i', 'n'}, '<Esc>', quit) -- can use <C-c> to exit insert mode
    keymap(buf, 'i', '<CR>', function() open_result('edit') end)
    keymap(buf, 'i', '<C-l>', function() open_result('vsplit') end)
    keymap(buf, 'i', '<C-s>', function() open_result('split') end)
    keymap(buf, 'i', '<C-t>', function() open_result('tabedit') end)
    keymap(buf, 'i', '<C-j>', function() move_cursor(1) end)
    keymap(buf, 'i', '<C-k>', function() move_cursor(-1) end)
    keymap(buf, 'i', '<Down>', function() move_cursor(1) end)
    keymap(buf, 'i', '<Up>', function() move_cursor(-1) end)
    keymap(buf, 'i', '<C-f>', function() move_cursor_page(true,  true) end)
    keymap(buf, 'i', '<C-b>', function() move_cursor_page(false, true) end)
    keymap(buf, 'i', '<PageUp>', function() move_cursor_page(true,  false) end)
    keymap(buf, 'i', '<PageDown>', function() move_cursor_page(false, false) end)
    keymap(buf, 'i', '<Home>', function() set_cursor(1) end)
    keymap(buf, 'i', '<End>', function() set_cursor(api.nvim_buf_line_count(result_buf)) end)
    keymap(buf, 'i', '<C-n>', function() switch_input_buf(true) end)
    keymap(buf, 'i', '<C-p>', function() switch_input_buf(false) end)

    -- `on_lines` can be called in various contexts wherein textlock could prevent
    -- changing buffer contents and window layout. Use `schedule` to defer such
    -- operations to the main loop.
    -- NOTE: `on_lines` gets called immediately because of setting the prompt
    api.nvim_buf_attach(input_bufs[i], false, {on_lines = vim.schedule_wrap(on_lines)})
  end

  render(matches)
  vim.cmd('startinsert')
end

return {open = open}
