local currentdir = "/"
local Config = require '/System/Libraries/Darwin/config'
term.clear()
term.setCursorPos(1, 1)
print(os.version())
function truncate(str)
    function findLast(haystack, needle)
        local i = haystack:match(".*" .. needle .. "()")
        if i == nil then return nil else return i - 1 end
    end
    local index = findLast(str, "/")
    return string.sub(str, 1, index)
end

while true do
    term.write("[root@" .. Config:FetchValueFromKey("Hostname") .. " " .. fs.getName(shell.dir()) .. "]$ ")
    shell.setPath("/System/Applications/Shell.app/Contents/Resources/bin:" .. shell.path())
    shell.run(read())
    local x, y = term.getCursorPos()
    if (y ~= 1) then
        term.setCursorPos(1, y + 1)
    end
end
