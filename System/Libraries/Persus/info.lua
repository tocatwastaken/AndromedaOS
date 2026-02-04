local Info = {}
local Config = require '/System/Libraries/Persus/config'
function Info:FetchOSString()
    local prefix = "Andromeda_Persus"
    local version = "2026.2"
    local hostname = Config:FetchValueFromKey("Hostname")
    return prefix .. "_" .. version
end
return Info
