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
        true,  -- enter
        vim.tbl_extend('force', {style = 'minimal'}, input_win_layout)
    )
    local result_win = api.nvim_open_win(
        result_buf,
        false,  -- enter
        vim.tbl_extend('force', {style = 'minimal', focusable = false}, result_win_layout)
    )
    vim.wo[result_win].cursorline = true
    -- vim.wo[result_win].winhighlight = 'CursorLine:PmenuSel'
    vim.wo[result_win].winhighlight = 'NormalFloat:Normal'
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

return {
    PROMPT = PROMPT,
    get_win_layouts = get_win_layouts,
    create_wins = create_wins,
    handle_vimresized = handle_vimresized,
    create_input_buf = create_input_buf,
}