local gpu = cepheus.peripherals.find("tm_gpu")


local Driver = {}
Driver.__index = Driver

function Driver:Load()
    _G.Persus.Logger:Msg("Persus::GPU: Initializing...")
    gpu.refreshSize()
    gpu.setSize(16)
    gpu.fill()
    gpu.sync()
    _G.Persus.Logger:Msg("Persus::GPU: Ready!")
end

function Driver:GetGPU()
    return gpu
end

function Driver:Unload()
    _G.Persus.Logger:Msg("Persus::GPU: Say goodnight, Gracie.")
    gpu.refreshSize()
    gpu.setSize(16)
    gpu.fill()
    gpu.sync()
    _G.Persus.Logger:Msg("Persus::GPU: Shut down driver.")
end

return Driver
