local args = ...
if (type(args) ~= "string") then
    print("Syntax error: Expected a string")
    return
end
local passwd = ""
local isconfirmation = false
print("Creating " .. args)
while true do
    term.write("Password: ")
    passwd = term.read("*")
    if not passwd == "" then
        isconfirmation = true
    else
        print("Cannot have blank password")
    end
    local x, y = term.getCursorPos()
    if (y ~= 1) then
        term.setCursorPos(1, y + 1)
    end
end