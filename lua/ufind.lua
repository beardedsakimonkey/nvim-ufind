local core = require('ufind.core')
local util = require('ufind.util')

local api = vim.api

local config_defaults = {
  get_value = function(item) return item end,
  get_highlights = nil,
  on_complete = function(cmd, item) vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(item)) end,
  pattern = '^(.*)$',
}

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
--     pattern?: string
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
  local pattern, num_groups = util.inject_empty_captures(config.pattern)
  local uf = core.Ufind.new(config, num_groups)

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

return {open = open}
