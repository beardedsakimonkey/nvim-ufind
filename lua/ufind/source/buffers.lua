---@return string[]
local function buffers_source()
    local origin_buf = vim.api.nvim_win_get_buf(0)

    local bufs = vim.tbl_filter(function(buf)
        local name = vim.fn.bufname(buf)
        return name ~= ''                           -- buffer is named
            and buf ~= origin_buf                   -- not the current buffer
            and vim.fn.buflisted(buf) == 1          -- buffer is listed
            and vim.fn.bufexists(buf) == 1          -- buffer exists
    end, vim.api.nvim_list_bufs())

    -- Sort by last used
    table.sort(bufs, function(a, b)
        return vim.fn.getbufinfo(a)[1].lastused > vim.fn.getbufinfo(b)[1].lastused
    end)

    -- Get buffer names
    local bufnames = vim.tbl_map(function(buf)
        return vim.fn.bufname(buf)
    end, bufs)

    return bufnames
end

return buffers_source
