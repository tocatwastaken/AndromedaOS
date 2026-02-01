---@diagnostic disable: undefined-field
term.clear();
term.setCursorPos(1, 1)
_G.Darwin = {}
local Info = require '/System/Libraries/Darwin/info'
_G.os.version = function()
    return Info:FetchOSString()
end
_G.Darwin.Logger = require '/System/Libraries/Darwin/logger'
_G.Darwin.Logger:Init()
_G.Darwin.Logger:Msg("\n" .. [[
+--------------------------------------------------------------+
|Hi there!                                                     |
|If you're reading this, something *probably* went wrong.      |
|Contact tocatwastaken on Discord for support with AndromedaOS.|
|Otherwise, if you know what you're doing, have fun!           |
+--------------------------------------------------------------+]])
_G.Darwin.Logger:Msg("Darwin::Boot: " .. Info:FetchOSString())
_G.Darwin.Logger:Msg("Darwin::Boot: Loading Drivers...")
_G.Darwin.DriverLoader = require '/System/Libraries/Darwin/driverloader'
local originShutdown = _G.os.shutdown
_G.os.shutdown = function()
    _G.Darwin.Logger:Msg("Darwin::Power: Shutting down...")
    _G.Darwin.DriverLoader:Unload()
    _G.Darwin.Logger:Deinit()
    originShutdown()
end
local originReboot = _G.os.reboot
_G.os.reboot = function()
    _G.Darwin.Logger:Msg("Darwin::Power: Rebooting...")
    _G.Darwin.DriverLoader:Unload()
    _G.Darwin.Logger:Deinit()
    originReboot()
end
xpcall(function()
    _G.Darwin.DriverLoader:Load()
end, function(error)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.red)
    print("KERNEL PANIC!")
    print(error)
    print("Press enter...")
    while true do
        local ev, p1 = os.pullEventRaw()
        if ev == "key" then
            if p1 == keys.enter or p1 == keys.numPadEnter then
                break
            end
        end
    end
    os.reboot()
end)
shell.run("/System/Applications/Shell.app/Contents/AndromedaOS/hello.lua")
