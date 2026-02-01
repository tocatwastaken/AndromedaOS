---@diagnostic disable: undefined-field
local Logger = {}
Logger.__index = Logger
local logfile
function Logger:Init()
    local time = os.epoch("local") / 1000
    local time_table = os.date("*t", time)
    logfile = fs.open("/System/Logs/" .. time_table.hour .. "-" .. time_table.min .. "-" .. time_table.sec .. ".log", "w")
end
function Logger:Msg(str)
    local time = os.epoch("local") / 1000
    local time_table = os.date("*t", time)
    logfile.write("[" .. time_table.hour .. ":" .. time_table.min .. ":" .. time_table.sec .. "]: " .. str .. "\n")
end
function Logger:Deinit()
    logfile.close()
end
return Logger