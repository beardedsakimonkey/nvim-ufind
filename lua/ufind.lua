local api = vim.api
local PROMPT = "> "
local function TIME(func)
  local function _1_(...)
    local start = vim.loop.hrtime()
    func(...)
    local _end = vim.loop.hrtime()
    local diff_ms = (1000000 / (_end - start))
    return print("Time: ", diff_ms)
  end
  return _1_
end
local function get_win_layouts()
  local height = math.floor((vim.go.lines * 0.8))
  local width = math.floor((vim.go.columns * 0.7))
  local row = math.ceil(((vim.go.lines - height) / 2))
  local col = math.ceil(((vim.go.columns - width) / 2))
  local input_height = 1
  local input_win = {relative = "editor", row = row, col = col, width = width, height = 1}
  local results_win = {relative = "editor", row = (input_height + row), col = col, width = width, height = (height - input_height)}
  return input_win, results_win
end
local function create_wins(input_buf, results_buf)
  local input_win_layout, results_win_layout = get_win_layouts()
  local input_win = api.nvim_open_win(input_buf, true, vim.tbl_extend("force", {style = "minimal"}, input_win_layout))
  local results_win = api.nvim_open_win(results_buf, false, vim.tbl_extend("force", {style = "minimal", focusable = false}, results_win_layout))
  do end (vim.wo)[results_win]["cursorline"] = true
  vim.wo[results_win]["winhighlight"] = "CursorLine:PmenuSel"
  return input_win, results_win
end
local function handle_vimresized(input_win, results_win)
  local function relayout()
    local input_win_layout, results_win_layout = get_win_layouts()
    api.nvim_win_set_config(input_win, input_win_layout)
    return api.nvim_win_set_config(results_win, results_win_layout)
  end
  local auid = api.nvim_create_autocmd("VimResized", {callback = relayout})
  return auid
end
local function create_bufs()
  local input_buf = api.nvim_create_buf(false, true)
  local results_buf = api.nvim_create_buf(false, true)
  do end (vim.bo)[input_buf]["buftype"] = "prompt"
  vim.fn.prompt_setprompt(input_buf, PROMPT)
  return input_buf, results_buf
end
local function map(buf, mode, lhs, rhs)
  return vim.keymap.set(mode, lhs, rhs, {nowait = true, silent = true, buffer = buf})
end
local function open(source, display, cb)
  local orig_win = api.nvim_get_current_win()
  local input_buf, results_buf = create_bufs()
  local input_win, results_win = create_wins(input_buf, results_buf)
  local auid = handle_vimresized(input_win, results_win)
  local source_items
  if ("function" == type(source)) then
    source_items = source()
  else
    source_items = source
  end
  assert(("table" == type(source_items)))
  local results
  local function _3_(_241)
    return {data = _241, score = 0, positions = {}}
  end
  results = vim.tbl_map(_3_, source_items)
  local function set_cursor(line)
    return api.nvim_win_set_cursor(results_win, {line, 0})
  end
  local function move_cursor(offset)
    local _local_4_ = api.nvim_win_get_cursor(results_win)
    local old_row = _local_4_[1]
    local _ = _local_4_[2]
    local lines = api.nvim_buf_line_count(results_buf)
    local new_row = math.max(math.min((old_row + offset), lines), 1)
    return set_cursor(new_row)
  end
  local function move_cursor_page(up_3f, half_3f)
    local _local_5_ = api.nvim_win_get_config(results_win)
    local height = _local_5_["height"]
    local offset
    local function _6_()
      if up_3f then
        return -1
      else
        return 1
      end
    end
    local function _7_()
      if half_3f then
        return 2
      else
        return 1
      end
    end
    offset = ((height * _6_()) / _7_())
    return move_cursor(offset)
  end
  local function cleanup()
    api.nvim_del_autocmd(auid)
    if api.nvim_buf_is_valid(input_buf) then
      api.nvim_buf_delete(input_buf, {})
    else
    end
    if api.nvim_buf_is_valid(results_buf) then
      api.nvim_buf_delete(results_buf, {})
    else
    end
    if api.nvim_win_is_valid(orig_win) then
      return api.nvim_set_current_win(orig_win)
    else
      return nil
    end
  end
  local function open_result(cmd)
    local _local_11_ = api.nvim_win_get_cursor(results_win)
    local row = _local_11_[1]
    local _ = _local_11_[2]
    cleanup()
    return cb(cmd, results[row].data)
  end
  local function use_virt_text(ns, buf, text)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    return api.nvim_buf_set_extmark(buf, ns, 0, -1, {virt_text = {{text, "Comment"}}, virt_text_pos = "right_align"})
  end
  local match_ns = api.nvim_create_namespace("ufind/match")
  local virt_ns = api.nvim_create_namespace("ufind/virt")
  local function on_lines(_, buf)
    local fzy = require("ufind.fzy")
    api.nvim_buf_clear_namespace(results_buf, match_ns, 0, -1)
    set_cursor(1)
    local _local_12_ = api.nvim_buf_get_lines(buf, 0, 1, true)
    local query = _local_12_[1]
    local query0 = query:sub((1 + #PROMPT))
    results = {}
    local matches
    local function _13_(_241)
      return display(_241)
    end
    matches = fzy.filter(query0, vim.tbl_map(_13_, source_items))
    for _0, _14_ in ipairs(matches) do
      local _each_15_ = _14_
      local i = _each_15_[1]
      local positions = _each_15_[2]
      local score = _each_15_[3]
      table.insert(results, {data = source_items[i], score = score, positions = positions})
    end
    local function _16_(_241, _242)
      return (_241.score > _242.score)
    end
    table.sort(results, _16_)
    local virt_text = (#results .. " / " .. #source_items)
    use_virt_text(virt_ns, input_buf, virt_text)
    local function _17_(_241)
      return display(_241.data)
    end
    api.nvim_buf_set_lines(results_buf, 0, -1, true, vim.tbl_map(_17_, results))
    for i, result in ipairs(results) do
      for _0, pos in ipairs(result.positions) do
        api.nvim_buf_add_highlight(results_buf, match_ns, "UfindMatch", (i - 1), (pos - 1), pos)
      end
    end
    return nil
  end
  map(input_buf, "i", "<Esc>", cleanup)
  local function _18_()
    return open_result("edit")
  end
  map(input_buf, "i", "<CR>", _18_)
  local function _19_()
    return open_result("vsplit")
  end
  map(input_buf, "i", "<C-l>", _19_)
  local function _20_()
    return open_result("split")
  end
  map(input_buf, "i", "<C-s>", _20_)
  local function _21_()
    return open_result("tabedit")
  end
  map(input_buf, "i", "<C-t>", _21_)
  local function _22_()
    return move_cursor(1)
  end
  map(input_buf, "i", "<C-j>", _22_)
  local function _23_()
    return move_cursor(-1)
  end
  map(input_buf, "i", "<C-k>", _23_)
  local function _24_()
    return move_cursor(1)
  end
  map(input_buf, "i", "<Down>", _24_)
  local function _25_()
    return move_cursor(-1)
  end
  map(input_buf, "i", "<Up>", _25_)
  local function _26_()
    return move_cursor_page(true, true)
  end
  map(input_buf, "i", "<C-u>", _26_)
  local function _27_()
    return move_cursor_page(false, true)
  end
  map(input_buf, "i", "<C-d>", _27_)
  local function _28_()
    return move_cursor_page(true, false)
  end
  map(input_buf, "i", "<PageUp>", _28_)
  local function _29_()
    return move_cursor_page(false, false)
  end
  map(input_buf, "i", "<PageDown>", _29_)
  local function _30_()
    return set_cursor(1)
  end
  map(input_buf, "i", "<Home>", _30_)
  local function _31_()
    return set_cursor(api.nvim_buf_line_count(results_buf))
  end
  map(input_buf, "i", "<End>", _31_)
  local on_lines0 = vim.schedule_wrap(TIME(on_lines))
  assert(api.nvim_buf_attach(input_buf, false, {on_lines = on_lines0}))
  api.nvim_create_autocmd("BufLeave", {buffer = input_buf, callback = cleanup})
  return vim.cmd("startinsert")
end
return {open = open}
