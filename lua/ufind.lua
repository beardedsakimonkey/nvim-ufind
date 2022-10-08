local api = vim.api
local PROMPT = "> "
local function get_win_layouts()
  local height = math.floor((vim.go.lines * 0.8))
  local width = math.floor((vim.go.columns * 0.7))
  local row = math.ceil(((vim.go.lines - height) / 2))
  local col = math.ceil(((vim.go.columns - width) / 2))
  local input_height = 1
  local input_win = {relative = "editor", row = row, col = col, width = width, height = 1}
  local result_win = {relative = "editor", row = (input_height + row), col = col, width = width, height = (height - input_height)}
  return input_win, result_win
end
local function create_wins(input_buf, result_buf)
  local input_win_layout, result_win_layout = get_win_layouts()
  local input_win = api.nvim_open_win(input_buf, true, vim.tbl_extend("force", {style = "minimal"}, input_win_layout))
  local result_win = api.nvim_open_win(result_buf, false, vim.tbl_extend("force", {style = "minimal", focusable = false}, result_win_layout))
  do end (vim.wo)[result_win]["cursorline"] = true
  vim.wo[result_win]["winhighlight"] = "CursorLine:PmenuSel"
  return input_win, result_win
end
local function handle_vimresized(input_win, result_win)
  local function relayout()
    local input_win_layout, result_win_layout = get_win_layouts()
    api.nvim_win_set_config(input_win, input_win_layout)
    api.nvim_win_set_config(result_win, result_win_layout)
    do end (vim.wo)[result_win]["cursorline"] = true
    return nil
  end
  local auid = api.nvim_create_autocmd("VimResized", {callback = relayout})
  return auid
end
local function create_bufs()
  local input_buf = api.nvim_create_buf(false, true)
  local result_buf = api.nvim_create_buf(false, true)
  do end (vim.bo)[input_buf]["buftype"] = "prompt"
  vim.fn.prompt_setprompt(input_buf, PROMPT)
  return input_buf, result_buf
end
local function open(source, display, cb)
  local orig_win = api.nvim_get_current_win()
  local input_buf, result_buf = create_bufs()
  local input_win, result_win = create_wins(input_buf, result_buf)
  local auid = handle_vimresized(input_win, result_win)
  local source0
  if ("function" == type(source)) then
    source0 = source()
  else
    source0 = source
  end
  assert(("table" == type(source0)))
  local results
  local function _2_(_241)
    return {data = _241, score = 0, positions = {}}
  end
  results = vim.tbl_map(_2_, source0)
  local function set_cursor(line)
    return api.nvim_win_set_cursor(result_win, {line, 0})
  end
  local function move_cursor(offset)
    local _local_3_ = api.nvim_win_get_cursor(result_win)
    local old_row = _local_3_[1]
    local _ = _local_3_[2]
    local lines = api.nvim_buf_line_count(result_buf)
    local new_row = math.max(math.min((old_row + offset), lines), 1)
    return set_cursor(new_row)
  end
  local function move_cursor_page(up_3f, half_3f)
    local _local_4_ = api.nvim_win_get_config(result_win)
    local height = _local_4_["height"]
    local offset
    local function _5_()
      if up_3f then
        return -1
      else
        return 1
      end
    end
    local function _6_()
      if half_3f then
        return 2
      else
        return 1
      end
    end
    offset = ((height * _5_()) / _6_())
    return move_cursor(offset)
  end
  local function cleanup()
    api.nvim_del_autocmd(auid)
    if api.nvim_buf_is_valid(input_buf) then
      api.nvim_buf_delete(input_buf, {})
    else
    end
    if api.nvim_buf_is_valid(result_buf) then
      api.nvim_buf_delete(result_buf, {})
    else
    end
    if api.nvim_win_is_valid(orig_win) then
      return api.nvim_set_current_win(orig_win)
    else
      return nil
    end
  end
  local function open_result(cmd)
    local _local_10_ = api.nvim_win_get_cursor(result_win)
    local row = _local_10_[1]
    local _ = _local_10_[2]
    cleanup()
    return cb(cmd, results[row].data)
  end
  local function use_hl_matches(ns, results0)
    api.nvim_buf_clear_namespace(result_buf, ns, 0, -1)
    for i, result in ipairs(results0) do
      for _, pos in ipairs(result.positions) do
        api.nvim_buf_add_highlight(result_buf, ns, "UfindMatch", (i - 1), (pos - 1), pos)
      end
    end
    return nil
  end
  local function use_virt_text(ns, text)
    api.nvim_buf_clear_namespace(input_buf, ns, 0, -1)
    return api.nvim_buf_set_extmark(input_buf, ns, 0, -1, {virt_text = {{text, "Comment"}}, virt_text_pos = "right_align"})
  end
  local function get_query()
    local _local_11_ = api.nvim_buf_get_lines(input_buf, 0, 1, true)
    local query = _local_11_[1]
    return query:sub((1 + #PROMPT))
  end
  local match_ns = api.nvim_create_namespace("ufind/match")
  local virt_ns = api.nvim_create_namespace("ufind/virt")
  local function on_lines()
    local fzy = require("ufind.fzy")
    set_cursor(1)
    local matches
    local function _12_(_241)
      return display(_241)
    end
    matches = fzy.filter(get_query(), vim.tbl_map(_12_, source0))
    local function _15_(_13_)
      local _arg_14_ = _13_
      local i = _arg_14_[1]
      local positions = _arg_14_[2]
      local score = _arg_14_[3]
      return {data = (source0)[i], score = score, positions = positions}
    end
    results = vim.tbl_map(_15_, matches)
    local function _16_(_241, _242)
      return (_241.score > _242.score)
    end
    table.sort(results, _16_)
    local function _17_(_241)
      return display(_241.data)
    end
    api.nvim_buf_set_lines(result_buf, 0, -1, true, vim.tbl_map(_17_, results))
    use_virt_text(virt_ns, (#results .. " / " .. #source0))
    return use_hl_matches(match_ns, results)
  end
  local function keymap(mode, lhs, rhs)
    return vim.keymap.set(mode, lhs, rhs, {nowait = true, silent = true, buffer = input_buf})
  end
  keymap({"i", "n"}, "<Esc>", cleanup)
  local function _18_()
    return open_result("edit")
  end
  keymap("i", "<CR>", _18_)
  local function _19_()
    return open_result("vsplit")
  end
  keymap("i", "<C-l>", _19_)
  local function _20_()
    return open_result("split")
  end
  keymap("i", "<C-s>", _20_)
  local function _21_()
    return open_result("tabedit")
  end
  keymap("i", "<C-t>", _21_)
  local function _22_()
    return move_cursor(1)
  end
  keymap("i", "<C-j>", _22_)
  local function _23_()
    return move_cursor(-1)
  end
  keymap("i", "<C-k>", _23_)
  local function _24_()
    return move_cursor(1)
  end
  keymap("i", "<Down>", _24_)
  local function _25_()
    return move_cursor(-1)
  end
  keymap("i", "<Up>", _25_)
  local function _26_()
    return move_cursor_page(true, true)
  end
  keymap("i", "<C-u>", _26_)
  local function _27_()
    return move_cursor_page(false, true)
  end
  keymap("i", "<C-d>", _27_)
  local function _28_()
    return move_cursor_page(true, false)
  end
  keymap("i", "<PageUp>", _28_)
  local function _29_()
    return move_cursor_page(false, false)
  end
  keymap("i", "<PageDown>", _29_)
  local function _30_()
    return set_cursor(1)
  end
  keymap("i", "<Home>", _30_)
  local function _31_()
    return set_cursor(api.nvim_buf_line_count(result_buf))
  end
  keymap("i", "<End>", _31_)
  local on_lines0 = vim.schedule_wrap(on_lines)
  assert(api.nvim_buf_attach(input_buf, false, {on_lines = on_lines0}))
  api.nvim_create_autocmd("BufLeave", {buffer = input_buf, callback = cleanup})
  return vim.cmd("startinsert")
end
return {open = open}
