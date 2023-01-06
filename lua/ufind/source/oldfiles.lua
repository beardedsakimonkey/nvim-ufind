---@return string[]
local function oldfiles_source()
    local fnames = vim.tbl_filter(function(fname)
        return fname
            and vim.fn.empty(vim.fn.glob(fname)) == 0  -- not wildignored
            and vim.fn.isdirectory(fname) == 0         -- not a directory
    end, vim.v.oldfiles)

    return fnames
end

return oldfiles_source
