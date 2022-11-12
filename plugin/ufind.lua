local function set_hl(hlgroup, val)
    local exists = pcall(vim.api.nvim_get_hl_by_name, hlgroup, true)
    if not exists then
        vim.api.nvim_set_hl(0, hlgroup, val)
    end
end

if not vim.g.loaded_ufind then
    vim.g.loaded_ufind = 1
    set_hl('UfindMatch', {link = 'IncSearch'})
    set_hl('UfindPrompt', {link = 'Comment'})
    set_hl('UfindNormal', {link = 'Normal'})
    set_hl('UfindBorder', {link = 'Normal'})
    set_hl('UfindCursorLine', {link = 'CursorLine'})
    set_hl('UfindResultCount', {link = 'Comment'})
end
