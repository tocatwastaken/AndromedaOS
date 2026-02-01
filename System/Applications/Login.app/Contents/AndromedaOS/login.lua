local Config = require '/System/Libraries/Darwin/config'
local sha256 = require '/System/Libraries/Darwin/sha256'
term.clear()
term.setCursorPos(1, 1)
local running = true
while running do
    term.write(Config:FetchValueFromKey("Hostname") .. " login:")
    local x, y = term.getCursorPos()
    if (y ~= 1) then
        term.setCursorPos(1, y + 1)
    end
end
