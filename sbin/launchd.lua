---@diagnostic disable: undefined-field

_G.Persus = {}
local Info = require("/System/Libraries/Persus/info")
_G.Config = require("/System/Libraries/Persus/config")
_G.os.version = function()
	return Info:FetchOSString()
end
_G.Persus.Logger = require("/System/Libraries/Persus/logger")
if string.find(Config:FetchValueFromKey("KernelArgs"), "-v") then
	_G.Persus.Logger:Init(true)
else
	_G.Persus.Logger.Init(false)
end
_G.Persus.Logger:Msg("\n" .. [[
+--------------------------------------------------------------+
|Hi there!                                                     |
|If you're reading this, something *probably* went wrong.      |
|Make an issue at https://github.com/tocatwastaken/AndromedaOS |
|Otherwise, if you know what you're doing, have fun!           |
+--------------------------------------------------------------+]], true)
_G.Persus.Logger:Msg("Persus::Boot: " .. Info:FetchOSString())
_G.Persus.Logger:Msg("Persus::Boot: Loading Drivers...")
_G.Persus.DriverLoader = require("/System/Libraries/Persus/driverloader")
local originShutdown = _G.os.shutdown
_G.os.shutdown = function()
	_G.Persus.Logger:Msg("Persus::Power: Shutting down...")
	_G.Persus.DriverLoader:Unload()
	_G.Persus.Logger:Deinit()
	originShutdown()
end
local originReboot = _G.os.reboot
_G.os.reboot = function()
	_G.Persus.Logger:Msg("Persus::Power: Rebooting...")
	_G.Persus.DriverLoader:Unload()
	_G.Persus.Logger:Deinit()
	originReboot()
end
xpcall(function()
	_G.Persus.DriverLoader:Load()
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

loadfile("/sbin/logon.lua", nil, _G)()