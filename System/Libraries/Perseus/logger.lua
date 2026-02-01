---@diagnostic disable: undefined-field
---@class Logger
---@field public verbose boolean
local Logger = {}
Logger.__index = Logger
local logfile
local Verbose = false

function Logger:Init(verbose)
    verbose = verbose or false
    Verbose = verbose
    local time = os.epoch("local") / 1000
    local time_table = os.date("*t", time)
    logfile = fs.open("/System/Logs/" .. time_table.hour .. "-" .. time_table.min .. "-" .. time_table.sec .. ".log", "w")
end
function Logger:Msg(str, stealth)
    local stealth = stealth or false
    local time = os.epoch("local") / 1000
    local time_table = os.date("*t", time)
    logfile.write("[" .. time_table.hour .. ":" .. time_table.min .. ":" .. time_table.sec .. "]: " .. str .. "\n")
    if (Verbose) and not stealth then
        cepheus.term.print("[" .. time_table.hour .. ":" .. time_table.min .. ":" .. time_table.sec .. "]: " .. str)
    end
end
function Logger:Deinit()
    logfile.close()
end
return Logger