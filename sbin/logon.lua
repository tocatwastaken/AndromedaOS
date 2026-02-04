local function getEntry(programPath)
	local infoPath = fs.combine(programPath, "Contents/Info.json")
	if not fs.exists(infoPath) then
		error("Invalid .app bundle: missing Contents/Info.json")
	end
	local infoFile = fs.open(infoPath, "r")
	local infoContent = infoFile.readAll()
	infoFile.close()
	local info = cepheus.json.decode(infoContent)
	if not info or not info.PList or not info.PList.Entry then
		error("Invalid Info.json: missing PList.Entry")
	end
	local entryPoint = fs.combine(programPath, "Contents/" .. info.PList.Entry)
	if not fs.exists(entryPoint) then
		error("Entry point not found: " .. entryPoint)
	end
	return entryPoint
end

while true do
	term.setBackgroundColor(cepheus.colors.black)
	term.clear()
	term.setCursorPos(1, 1)

	term.setTextColor(cepheus.colors.cyan)
	cepheus.term.print("AndromedaOS")
	term.setTextColor(cepheus.colors.gray)
	cepheus.term.print("")

	term.setTextColor(cepheus.colors.white)
	term.write("login: ")
	term.setTextColor(cepheus.colors.lightBlue)
	local username = cepheus.term.read()

	if not username or username == "" then
		goto continue
	end

	local userInfo = cepheus.users.getUserInfo(username)
	if not userInfo then
		term.setTextColor(cepheus.colors.red)
		cepheus.term.print("login: user not found")
		term.setTextColor(cepheus.colors.white)
		cepheus.term.print("")
		sleep(0.8)
		goto continue
	end

	term.setTextColor(cepheus.colors.white)
	term.write("password: ")
	term.setTextColor(cepheus.colors.lightBlue)
	local password = cepheus.term.read("*")

	if cepheus.users.authenticate(username, password) then
		term.setTextColor(cepheus.colors.white)
		cepheus.term.print("")

		local shellPath = userInfo.shell or "System/Applications/Shell.app"
		local pid = cepheus.sched.spawnAsUser(getEntry(shellPath), userInfo.uid, userInfo.gid or 0)

		if pid then
			cepheus.sched.wait(pid)

			term.setBackgroundColor(cepheus.colors.black)
			sleep(0.5)
			term.clear()
			term.setCursorPos(1, 1)
			term.setTextColor(cepheus.colors.gray)
			cepheus.term.print("logout: " .. username)
			cepheus.term.print("")
			sleep(0.5)
		else
			term.setTextColor(cepheus.colors.red)
			cepheus.term.print("login: failed to start shell")
			sleep(1.5)
			return
		end
	else
		term.setTextColor(cepheus.colors.red)
		cepheus.term.print("login: incorrect password")
		term.setTextColor(cepheus.colors.white)
		cepheus.term.print("")
		sleep(0.8)
	end

	::continue::
end