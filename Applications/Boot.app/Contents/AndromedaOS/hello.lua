local gpu;
xpcall(function ()
    gpu = peripheral.find("directgpu")
end, function (err)
    print("Failed to recognize an attached GPU.\nIs a GPU Attached? Do you have DirectGPU installed?")
    gpu = false
end)
if (type(gpu) == "boolean") then
    print("Couldn't find GPU, exiting...")
    return
end
local Info = require '/System/Libraries/Darwin/info'
local display = _G.Darwin.DriverLoader:GetLoadedDriverByName("GPU"):GetDisplay()

-- Get display info
local info = gpu.getDisplayInfo(display)
gpu.clear(display, 0, 100, 200)
print(string.format("Display: %dx%d pixels", info.pixelWidth, info.pixelHeight))
gpu.loadJPEGFullscreen(display, fs.open("/System/Resources/Boot.b64", "r").readAll())
-- Draw text
gpu.drawText(display, Info:FetchOSString(), 0, 0,
    0, 0, 0, "Hack", 8, "bold")
gpu.updateDisplay(display)