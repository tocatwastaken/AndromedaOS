local args = ...
if string.find(args, ".app") then
    if not (string.find(args, "/")) then
        if (fs.exists("/Applications/" .. args)) then
            shell.run("/System/Libraries/Darwin/runapp.lua", "/Applications/" .. args)
        end
        if (fs.exists("/System/Applications/" .. args)) then
            shell.run("/System/Libraries/Darwin/runapp.lua", "/System/Applications/" .. args)
        end
        return
    end
    shell.run("/System/Libraries/Darwin/runapp.lua", args)
end