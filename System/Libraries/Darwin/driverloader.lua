local DriverLoader = {
    Drivers = {}
}
local Logger = require '/System/Libraries/Darwin/logger'
DriverLoader.__index = DriverLoader
DriverLoader.Drivers = {}
function DriverLoader:Load()
    for index, value in ipairs(fs.list("/System/Drivers")) do
        _G.Darwin.Logger:Msg("Darwin::DriverLoader: Loading driver: " .. value)
        local driver = {
            Driver = require("/System/Drivers/" .. string.gsub(value, ".lua", "")),
            Name = string.gsub(value, ".lua", "")
        }
        table.insert(DriverLoader.Drivers, driver)
        DriverLoader:GetLoadedDriverByName(string.gsub(value, ".lua", "")):Load()
    end
end
function DriverLoader:GetLoadedDriverByName(name)
    for i,v in ipairs(DriverLoader.Drivers) do
        if v.Name == name then
            return v.Driver
        end
    end
    error("Darwin::DriverLoader: Failed to find driver: " .. name)
end
function DriverLoader:Unload()
    _G.Darwin.Logger:Msg("Darwin::DriverLoader: Say goodnight, Gracie.")
    for index, value in ipairs(DriverLoader.Drivers) do
        value.Driver:Unload()
        table.remove(DriverLoader.Drivers, index)
    end
    _G.Darwin.Logger:Msg("Darwin::DriverLoader: Unloaded all Drivers.")
end
return DriverLoader