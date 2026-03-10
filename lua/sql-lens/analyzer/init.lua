local M = {}

local extractor = require("sql-lens.analyzer.extractor")
local parser    = require("sql-lens.analyzer.parser")
local hints     = require("sql-lens.analyzer.hints")

M.extractor = extractor
M.parser    = parser
M.hints     = hints

return M
