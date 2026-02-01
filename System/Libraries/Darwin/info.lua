local Info = {}
local Config = require '/System/Libraries/Darwin/config'
function Info:FetchOSString()
    local prefix = "Andromeda_Darwin"
    local version = "2026.2"
    local hostname = Config:FetchValueFromKey("Hostname")
    return prefix .. "_" .. version
end
return Info
