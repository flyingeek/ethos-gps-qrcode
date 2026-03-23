---@diagnostic disable-next-line: undefined-global
local __ = L.translate

local ANSI_BLACK = "\27[1;30m"
local ANSI_RED = "\27[1;31m"
local ANSI_GREEN = "\27[1;32m"
local ANSI_YELLOW = "\27[1;33m"
local ANSI_CYAN = "\27[0;36m"
local function log(text, ansiColor)
    if not ansiColor then ansiColor = ANSI_CYAN end -- black is unreadable on ethos.studio1247.com
    local ANSI_RESET = "\27[0m"
    print(ansiColor.."[cv]"..tostring(text)..ANSI_RESET)
end


return {
    log=log,
    ANSI_RED=ANSI_RED,
    ANSI_GREEN=ANSI_GREEN,
    ANSI_YELLOW=ANSI_YELLOW,
}
