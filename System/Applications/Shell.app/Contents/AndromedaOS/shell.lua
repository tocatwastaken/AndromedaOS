local currentdir = "/"
local Config = require '/System/Libraries/Darwin/config'
if not (string.find(Config:FetchValueFromKey("KernelArgs"), "-v")) then
    term.clear()
    term.setCursorPos(1, 1)
end
local running = true
print(os.version())
function truncate(str)
    function findLast(haystack, needle)
        local i = haystack:match(".*" .. needle .. "()")
        if i == nil then return nil else return i - 1 end
    end

    local index = findLast(str, "/")
    return string.sub(str, 1, index)
end
function prettyname(str)
    if str == "root" then
        return "/"
    end
    if str == "home" then
        return "~"
    end
end

while running do
    term.write("[root@" .. Config:FetchValueFromKey("Hostname") .. " " .. prettyname(fs.getName(shell.dir())) .. "]$ ")
    shell.setPath("/System/Applications/Shell.app/Contents/Resources/bin:" .. shell.path())
    local input = read()
    if input == "exit" then
        running = false
    else
        shell.run(input)
    end
    local x, y = term.getCursorPos()
    if (y ~= 1) then
        term.setCursorPos(1, y + 1)
    end
end
