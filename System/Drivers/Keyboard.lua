local Keyboard = cepheus.peripherals.find("tm_keyboard")


local Driver = {}
Driver.__index = Driver

function Driver:Load()
    _G.Perseus.Logger:Msg("Perseus::Keyboard: Initializing...")
    Keyboard.setFireNativeEvents(true)
    _G.Perseus.Logger:Msg("Perseus::Keyboard: Ready!")
end

function Driver:GetKeyboard()
    return Keyboard
end

function Driver:Unload()
    _G.Perseus.Logger:Msg("Perseus::Keyboard: Say goodnight, Gracie.")
    Keyboard.setFireNativeEvents(false)
    _G.Perseus.Logger:Msg("Perseus::Keyboard: Shut down driver.")
end

return Driver
