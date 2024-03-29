local M = {}

---@param source string[] | string | fun():string,string[]?
---@param config UfindConfig?
function M.open(source, config)
    require'ufind.main'.open(source, config)
end

---@param source string | fun(query: string):string,string[]?
---@param config UfindConfig?
function M.open_live(source, config)
    require'ufind.main'.open_live(source, config)
end

M.default_config = setmetatable({}, {
    __index = function(tbl, key)
        return require'ufind.main'.default_config[key]
    end,
})

return M
