local view = require('ufind.view')
local util = require('ufind.util')
local api = vim.api

local config_defaults = {
  get_value = function(item) return item end,
  get_highlights = nil,
  on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
  get_iter = function(line) return ipairs({line}) end,
  num_groups = 1,
}

local Ufind = {
  get_selected_item = function()
    error('Not implemented')
  end,
}

function Ufind.new(config)
  config = vim.tbl_extend('force', {}, config_defaults, config or {})
  local o = {}
  setmetatable(o, {__index = Ufind})

  o.cur_input = 1
  o.input_bufs = {}

  -- Create input buffers
  for _ = 1, config.num_groups do
    table.insert(o.input_bufs, view.create_input_buf())
  end

  -- Set prompts
  for i = 1, #o.input_bufs do
    local prompt = i .. '/' .. config.num_groups .. view.PROMPT
    vim.fn.prompt_setprompt(o.input_bufs[i], prompt)
  end

  o.config = config
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
  self:quit() -- cleanup first in case `on_complete` opens another finder
  return self.config.on_complete(cmd, item)
end

function Ufind:get_queries()
  return vim.tbl_map(function(buf)
    local buf_lines = api.nvim_buf_get_lines(buf, 0, 1, true)
    local query = buf_lines[1]
    local prompt = vim.fn.prompt_getprompt(buf)
    return query:sub(1 + #prompt) -- trim prompt from the query
  end, self.input_bufs)
end

function Ufind:setup_keymaps(buf)
  util.keymap(buf, {'i', 'n'}, '<Esc>', function() self:quit() end) -- can use <C-c> to exit insert mode
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


-- The entrypoint for opening a finder window.
-- `items`: a sequential table of any type.
-- `config`: an optional table containing:
--   `get_value`: a function that converts an item to a string to be passed to the fuzzy filterer.
--   `get_highlights`: a function that returns highlight ranges to highlight the result line.
--   `on_complete`: a function that's called when selecting an item to open.
--   `get_iter`: a function that returns an iterator that breaks up lines into parts that are queried individually.
--   `num_groups`: number of query groups (required for now)
--
-- More formally:
--   type items = array<'item>
--   type config? = {
--     get_value?: 'item => string,
--     get_highlights?: ('item, string) => ?array<{hl_group, col_start, col_end}>,
--     on_complete?: ('edit' | 'split' | 'vsplit' | 'tabedit', 'item) => nil,
--     get_iter?: (string) => (() => number, string),
--     num_groups: number
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

  -- Mapping from match index (essentially the line number of the selected
  -- result) to item index (the index of the corresponding item in  `items`).
  -- This is needed by `open_result` to pass the selected item to `on_complete`.
  local match_to_item = {}

  local uf = Ufind.new(config)
  config = uf.config

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
    uf:set_cursor(1)
    local matches = require('ufind.fuzzy_filter').filter(uf:get_queries(), lines, config.get_iter)
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

return {open = open}
