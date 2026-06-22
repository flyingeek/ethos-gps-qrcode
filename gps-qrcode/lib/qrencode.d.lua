---@meta

---@class QRJob
---@field str string
---@field ec_level? integer
---@field mode? integer
---@field version? integer
---@field arranged_data? string
---@field scratch? integer[][]
---@field matrix? integer[][]
---@field min_penalty? integer
---@field step? integer
local QRJob = {}

---@class QRRuns
---@field size integer
---@field cell_size integer
---@field rows integer[][]
local QRRuns = {}
