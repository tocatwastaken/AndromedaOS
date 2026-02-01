local status, gpu = xpcall(function()
    return peripheral.find("directgpu")
end, function(err)
    error("Darwin::GPU: Failed to find DirectGPU! Is one attached? Is the mod installed?")
    return 0
end)
if GPU == 0 then
    return
end
local display = nil
local Driver = {}
function Driver:Load()
    display = gpu.autoDetectAndCreateDisplay()
    local info = gpu.getDisplayInfo(display)
    _G.Darwin.Logger:Msg(string.format("Darwin::GPU: Got an attached display with resolution: %dx%d pixels", info.pixelWidth, info.pixelHeight))

end
function Driver:GetDisplay()
    if display == nil then
        error("Darwin::GPU: Attempted to fetch display without it existing!")
    end
    return display
end
function Driver:Unload()
    gpu.clearAllDisplays()
    _G.Darwin.Logger:Msg("Darwin::GPU: Say goodnight, Gracie.")
end

return Driver