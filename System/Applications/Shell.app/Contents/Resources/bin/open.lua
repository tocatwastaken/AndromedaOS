local args = ...
if string.find(args, ".app") then
    if not (string.find(args, "/")) then
        shell.run("/System/Libraries/Darwin/runapp.lua", "/Applications/" .. args)
        return
    end
    shell.run("/System/Libraries/Darwin/runapp.lua", args)
end