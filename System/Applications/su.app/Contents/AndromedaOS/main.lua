local args = {...}

local parsed = cepheus.parsing.parseArgs(args)
local positionalArgs = cepheus.parsing.getPositionalArgs(parsed)

local targetUsername = positionalArgs[1] or "root"

local currentUser = cepheus.users.getCurrentUser()
if not currentUser then
	cepheus.term.printError("su: Failed to get current user")
	return
end

if currentUser.username == targetUsername then
	cepheus.term.printError("su: Already logged in as " .. targetUsername)
	return
end

local targetUser = cepheus.users.getUserInfo(targetUsername)
if not targetUser then
	cepheus.term.printError("su: user '" .. targetUsername .. "' does not exist")
	return
end

term.write("Password: ")
local password = cepheus.term.read("*")

if not cepheus.users.verifyPassword(targetUsername, password) then
    cepheus.term.printError("su: Authentication failure")
    return
end

local success, err = pcall(function()
	cepheus.users.authenticate(targetUsername, password)
end)

if not success then
	cepheus.term.printError("su: Failed to switch user: " .. tostring(err))
	return
end

local newUser = cepheus.users.getCurrentUser()
if newUser and newUser.home then
	if _G.shell and _G.shell.setDir then
		_G.shell.setDir(newUser.home)
	end
end

cepheus.term.print("Switched to user: " .. targetUsername)
