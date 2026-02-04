local args = { ... }

local parsed = cepheus.parsing.parseArgs(args)
local positionalArgs = cepheus.parsing.getPositionalArgs(parsed)

local currentUser = cepheus.users.getCurrentUser()
if not currentUser then
	cepheus.term.printError("passwd: Failed to get current user")
	return
end

local targetUsername = positionalArgs[1]
local isChangingOwnPassword = false

if not targetUsername then
	targetUsername = currentUser.username
	isChangingOwnPassword = true
else
	if currentUser.username ~= "root" and not cepheus.users.hasCap(cepheus.users.CAPS.USER_ADMIN) then
		cepheus.term.printError("passwd: Only root can change other users' passwords")
		return
	end

	local targetUser = cepheus.users.getUserInfo(targetUsername)
	if not targetUser then
		cepheus.term.printError("passwd: user '" .. targetUsername .. "' does not exist")
		return
	end
end

local currentPassword
if isChangingOwnPassword then
	term.write("Current password: ")
	currentPassword = cepheus.term.read("*")

	if not cepheus.users.verifyPassword(targetUsername, currentPassword) then
		cepheus.term.printError("passwd: Authentication failure")
		return
	end
end

term.write("New password: ")
local newPassword = cepheus.term.read("*")

if not newPassword or newPassword == "" then
	cepheus.term.printError("passwd: Password cannot be empty")
	return
end

term.write("Retype new password: ")
local confirmPassword = cepheus.term.read("*")

if newPassword ~= confirmPassword then
	cepheus.term.printError("passwd: Passwords do not match")
	return
end

local success, err = pcall(function()
	cepheus.users.changePassword(targetUsername, currentPassword, newPassword)
end)

if not success then
	cepheus.term.printError("passwd: Failed to change password: " .. tostring(err))
	return
end

cepheus.term.print("Password changed successfully for " .. targetUsername)
