local api = vim.api

local M = {}

---@param cfg UfindLayout
local function get_win_layouts(cfg)
    local has_border = cfg.border ~= 'none'
    -- Size of the window
    local height = math.floor(vim.go.lines * cfg.height)
    local width = math.floor(vim.go.columns * cfg.width)
    -- Position of the window
    local row = math.ceil((vim.go.lines - height) / 2)
    local col = math.ceil((vim.go.columns - width) / 2)
    -- Window height, including borders
    local input_height = has_border and 3 or 1
    local result_height = height - input_height
    local input_win = {
        relative = 'editor',
        row = cfg.input_on_top and row or (row + result_height),
        col = col,
        width = width - (has_border and 2 or 0),
        height = 1,
        border = cfg.border,
    }
    local result_win = {
        relative = 'editor',
        row = cfg.input_on_top and (row + input_height) or row,
        col = col,
        width = width - (has_border and 2 or 0),
        height = result_height - (has_border and 2 or 0),
        border = cfg.border,
    }
    return input_win, result_win
end

---@param cfg UfindLayout
function M.create_wins(input_buf, result_buf, cfg)
    local input_win_layout, result_win_layout = get_win_layouts(cfg)
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
    vim.wo[result_win].scrolloff = 0
    vim.wo[result_win].winhighlight = 'NormalFloat:UfindNormal,FloatBorder:UfindBorder,CursorLine:UfindCursorLine'
    vim.wo[input_win].winhighlight  = 'NormalFloat:UfindNormal,FloatBorder:UfindBorder'
    return input_win, result_win
end

---@param cfg UfindLayout
function M.handle_vimresized(input_win, result_win, cfg, cb)
    local function relayout()
        local input_win_layout, result_win_layout = get_win_layouts(cfg)
        api.nvim_win_set_config(input_win, input_win_layout)
        -- Note: This disables 'cursorline' due to style = 'minimal' window config
        api.nvim_win_set_config(result_win, result_win_layout)
        vim.wo[result_win].cursorline = true
        cb()
    end
    return api.nvim_create_autocmd('VimResized', {callback = relayout})
end

function M.create_input_buf()
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'prompt'
    return buf
end

function M.create_result_buf()
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].undolevels = -1
    return buf
end

return M
