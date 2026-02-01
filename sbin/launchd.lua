---@diagnostic disable: undefined-field

_G.Perseus = {}
local Info = require '/System/Libraries/Perseus/info'
local Config = require '/System/Libraries/Perseus/config'
_G.os.version = function()
    return Info:FetchOSString()
end
_G.Perseus.Logger = require '/System/Libraries/Perseus/logger'
if (string.find(Config:FetchValueFromKey("KernelArgs"), "-v")) then
    _G.Perseus.Logger:Init(true)
else
    _G.Perseus.Logger.Init(false)
end
_G.Perseus.Logger:Msg("\n" .. [[
+--------------------------------------------------------------+
|Hi there!                                                     |
|If you're reading this, something *probably* went wrong.      |
|Make an issue at https://github.com/tocatwastaken/AndromedaOS |
|Otherwise, if you know what you're doing, have fun!           |
+--------------------------------------------------------------+]], true)
_G.Perseus.Logger:Msg("Perseus::Boot: " .. Info:FetchOSString())
_G.Perseus.Logger:Msg("Perseus::Boot: Loading Drivers...")
_G.Perseus.DriverLoader = require '/System/Libraries/Perseus/driverloader'
local originShutdown = _G.os.shutdown
_G.os.shutdown = function()
    _G.Perseus.Logger:Msg("Perseus::Power: Shutting down...")
    _G.Perseus.DriverLoader:Unload()
    _G.Perseus.Logger:Deinit()
    originShutdown()
end
local originReboot = _G.os.reboot
_G.os.reboot = function()
    _G.Perseus.Logger:Msg("Perseus::Power: Rebooting...")
    _G.Perseus.DriverLoader:Unload()
    _G.Perseus.Logger:Deinit()
    originReboot()
end
xpcall(function()
    _G.Perseus.DriverLoader:Load()
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
local runapp = loadfile("/System/Libraries/Perseus/runapp.lua", "t", _G)
runapp("/System/Applications/Shell.app")