local Config = {}
Config.__index = Config
local json = require '/System/Libraries/Persus/json-min'
local cfg = fs.open("/System/Configuration.json", "r")
local cfgTable = json.decode(cfg.readAll()).PList
cfg.close()
cfg = nil;
function Config:FetchValueFromKey(key)
    ---@diagnostic disable-next-line: undefined-field
    if not (cfgTable[key]) then
        error("Persus::config: Attempted to fetch a key from SysConfig that doesn't exist!")
    end
    return cfgTable[key]
end

return Config
