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
local config_defaults
local function _1_(_241)
  return _241
end
local function _2_(_241)
  return _241
end
local function _3_(cmd, item)
  return vim.cmd((cmd .. " " .. vim.fn.fnameescape(item)))
end
config_defaults = {["get-display"] = _1_, ["get-value"] = _2_, ["on-complete"] = _3_}
local function open(items, _3fconfig)
  assert(("table" == type(items)))
  local config = vim.tbl_extend("force", {}, config_defaults, (_3fconfig or {}))
  local orig_win = api.nvim_get_current_win()
  local input_buf, result_buf = create_bufs()
  local input_win, result_win = create_wins(input_buf, result_buf)
  local auid = handle_vimresized(input_win, result_win)
  local results
  local function _4_(_241)
    return {data = _241, score = 0, positions = {}}
  end
  results = vim.tbl_map(_4_, items)
  local function set_cursor(line)
    return api.nvim_win_set_cursor(result_win, {line, 0})
  end
  local function move_cursor(offset)
    local _local_5_ = api.nvim_win_get_cursor(result_win)
    local old_row = _local_5_[1]
    local _ = _local_5_[2]
    local lines = api.nvim_buf_line_count(result_buf)
    local new_row = math.max(math.min((old_row + offset), lines), 1)
    return set_cursor(new_row)
  end
  local function move_cursor_page(up_3f, half_3f)
    local _local_6_ = api.nvim_win_get_config(result_win)
    local height = _local_6_["height"]
    local offset
    local function _7_()
      if up_3f then
        return -1
      else
        return 1
      end
    end
    local function _8_()
      if half_3f then
        return 2
      else
        return 1
      end
    end
    offset = ((height * _7_()) / _8_())
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
    local _local_12_ = api.nvim_win_get_cursor(result_win)
    local row = _local_12_[1]
    local _ = _local_12_[2]
    cleanup()
    return config["on-complete"](cmd, results[row].data)
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
    local _local_13_ = api.nvim_buf_get_lines(input_buf, 0, 1, true)
    local query = _local_13_[1]
    return query:sub((1 + #PROMPT))
  end
  local function keymap(mode, lhs, rhs)
    return vim.keymap.set(mode, lhs, rhs, {nowait = true, silent = true, buffer = input_buf})
  end
  keymap({"i", "n"}, "<Esc>", cleanup)
  local function _14_()
    return open_result("edit")
  end
  keymap("i", "<CR>", _14_)
  local function _15_()
    return open_result("vsplit")
  end
  keymap("i", "<C-l>", _15_)
  local function _16_()
    return open_result("split")
  end
  keymap("i", "<C-s>", _16_)
  local function _17_()
    return open_result("tabedit")
  end
  keymap("i", "<C-t>", _17_)
  local function _18_()
    return move_cursor(1)
  end
  keymap("i", "<C-j>", _18_)
  local function _19_()
    return move_cursor(-1)
  end
  keymap("i", "<C-k>", _19_)
  local function _20_()
    return move_cursor(1)
  end
  keymap("i", "<Down>", _20_)
  local function _21_()
    return move_cursor(-1)
  end
  keymap("i", "<Up>", _21_)
  local function _22_()
    return move_cursor_page(true, true)
  end
  keymap("i", "<C-u>", _22_)
  local function _23_()
    return move_cursor_page(false, true)
  end
  keymap("i", "<C-d>", _23_)
  local function _24_()
    return move_cursor_page(true, false)
  end
  keymap("i", "<PageUp>", _24_)
  local function _25_()
    return move_cursor_page(false, false)
  end
  keymap("i", "<PageDown>", _25_)
  local function _26_()
    return set_cursor(1)
  end
  keymap("i", "<Home>", _26_)
  local function _27_()
    return set_cursor(api.nvim_buf_line_count(result_buf))
  end
  keymap("i", "<End>", _27_)
  local match_ns = api.nvim_create_namespace("ufind/match")
  local virt_ns = api.nvim_create_namespace("ufind/virt")
  local function on_lines()
    local fzy = require("ufind.fzy")
    set_cursor(1)
    local matches
    local function _28_(_241)
      return config["get-value"](_241)
    end
    matches = fzy.filter(get_query(), vim.tbl_map(_28_, items))
    local function _31_(_29_)
      local _arg_30_ = _29_
      local i = _arg_30_[1]
      local positions = _arg_30_[2]
      local score = _arg_30_[3]
      return {data = items[i], score = score, positions = positions}
    end
    results = vim.tbl_map(_31_, matches)
    local function _32_(_241, _242)
      return (_241.score > _242.score)
    end
    table.sort(results, _32_)
    local function _33_(_241)
      return config["get-display"](_241.data)
    end
    api.nvim_buf_set_lines(result_buf, 0, -1, true, vim.tbl_map(_33_, results))
    use_virt_text(virt_ns, (#results .. " / " .. #items))
    return use_hl_matches(match_ns, results)
  end
  local on_lines0 = vim.schedule_wrap(on_lines)
  assert(api.nvim_buf_attach(input_buf, false, {on_lines = on_lines0}))
  api.nvim_create_autocmd("BufLeave", {buffer = input_buf, callback = cleanup})
  return vim.cmd("startinsert")
end
return {open = open}
