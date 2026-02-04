local Keyboard = cepheus.peripherals.find("tm_keyboard")


local Driver = {}
Driver.__index = Driver

function Driver:Load()
    _G.Persus.Logger:Msg("Persus::Keyboard: Initializing...")
    Keyboard.setFireNativeEvents(true)
    _G.Persus.Logger:Msg("Persus::Keyboard: Ready!")
end

function Driver:GetKeyboard()
    return Keyboard
end

function Driver:Unload()
    _G.Persus.Logger:Msg("Persus::Keyboard: Say goodnight, Gracie.")
    Keyboard.setFireNativeEvents(false)
    _G.Persus.Logger:Msg("Persus::Keyboard: Shut down driver.")
end

return Driver
