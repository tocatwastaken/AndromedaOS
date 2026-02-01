--[[
    For reference for developers, apps should be structured like this:
        Your.app/
            Contents/
                AndromedaOS/
                    <Any lua files you need, including your entrypoint>
                Frameworks/
                    <Any libraries you need>
                Resources/
                    <Your resources>
                Info.json
    Otherwise, you should die!
]]

local path = ...;
if (type(path) ~= "string") then
    _G.Perseus.Logger:Msg("Fatal: Invalid path! Expected string, got " .. type(path))
    return
end
local JSON = require '/System/Libraries/Perseus/json-min'
--TODO: At this point, we know the app EXISTS, but we dont know if critical stuff does... maybe fix that later?
if not fs.exists(path) then
    _G.Perseus.Logger:Msg("Fatal: App doesn't exist!")
    _G.Perseus.Logger:Msg("Couldn't find: " .. path)
    return
end
local infofile = fs.open(path .. "/Contents/Info.json", "r")
local info = JSON.decode(infofile.readAll())
infofile.close()
local entry = info["PList"]["Entry"]
dofile(path .. "/Contents/"..entry)