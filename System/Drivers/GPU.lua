local gpu = peripheral.find("tm_gpu")


local Driver = {}
Driver.__index = Driver

function Driver:Load()
    _G.Darwin.Logger:Msg("Darwin::GPU: Initializing...")
    gpu.refreshSize()
    gpu.setSize(16)
    gpu.fill()
    gpu.sync()
    _G.Darwin.Logger:Msg("Darwin::GPU: Ready!")
end

function Driver:GetGPU()
    return gpu
end

function Driver:Unload()
    _G.Darwin.Logger:Msg("Darwin::GPU: Say goodnight, Gracie.")
    gpu.refreshSize()
    gpu.setSize(16)
    gpu.fill()
    gpu.sync()
    _G.Darwin.Logger:Msg("Darwin::GPU: Shut down driver.")
end

return Driver
