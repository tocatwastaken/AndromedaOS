local cepheus = _G.cepheus or require("cepheus")

local Shell = {}
Shell.aliases = {}
Shell.path = "/Programs:/System/Programs:/System/Applications"
Shell.currentDir = "/"
Shell.completionFunctions = {}
Shell.history = {}
Shell.maxHistory = 100

local function getHostname()
	if _G.Config and type(_G.Config.FetchValueFromKey) == "function" then
		return _G.Config:FetchValueFromKey("Hostname") or "localhost"
	end
	return "localhost"
end

local function getUsername()
	local user = cepheus.users.getCurrentUser()
	if user then
		return user.username
	end
	return "unknown"
end

local function getDisplayPath()
	local user = cepheus.users.getCurrentUser()
	if user and user.home then
		if Shell.currentDir == user.home then
			return "~"
		elseif Shell.currentDir:sub(1, #user.home + 1) == user.home .. "/" then
			return "~/" .. Shell.currentDir:sub(#user.home + 2)
		end
	end

	if Shell.currentDir == "/" then
		return "/"
	end

	return fs.getName(Shell.currentDir)
end

local function resolveProgram(program)
	if fs.exists(program) then
		return program
	end

	if fs.exists(program .. ".lua") then
		return program .. ".lua"
	end

	if fs.exists(program .. ".app") then
		return program .. ".app"
	end

	local relativePath = fs.combine(Shell.currentDir, program)
	if fs.exists(relativePath) then
		return relativePath
	end

	if fs.exists(relativePath .. ".lua") then
		return relativePath .. ".lua"
	end

	if fs.exists(relativePath .. ".app") then
		return relativePath .. ".app"
	end

	if Shell.aliases[program] then
		program = Shell.aliases[program]
	end

	for pathDir in Shell.path:gmatch("[^:]+") do
		local fullPath = fs.combine(pathDir, program)
		if fs.exists(fullPath) then
			return fullPath
		end

		if fs.exists(fullPath .. ".lua") then
			return fullPath .. ".lua"
		end

		if fs.exists(fullPath .. ".app") then
			return fullPath .. ".app"
		end
	end

	local appPath = fs.combine("/System/Applications", program .. ".app")
	if fs.exists(appPath) then
		return appPath
	end

	return nil
end

local function parseCommandLine(commandLine)
	local args = {}
	local current = ""
	local inQuotes = false
	local quoteChar = nil
	local i = 1

	while i <= #commandLine do
		local char = commandLine:sub(i, i)

		if inQuotes then
			if char == quoteChar then
				inQuotes = false
				quoteChar = nil
			else
				current = current .. char
			end
		elseif char == '"' or char == "'" then
			inQuotes = true
			quoteChar = char
		elseif char == " " or char == "\t" then
			if #current > 0 then
				table.insert(args, current)
				current = ""
			end
		else
			current = current .. char
		end

		i = i + 1
	end

	if #current > 0 then
		table.insert(args, current)
	end

	return args
end

local function resolvePath(path)
	if path:sub(1, 1) == "/" then
		return path
	end
	return fs.combine(Shell.currentDir, path)
end

local builtins = {}

function builtins.cd(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local paths = cepheus.parsing.getPositionalArgs(parsed)
	local target = paths[1] or "/"

	if target == ".." then
		Shell.currentDir = fs.getDir(Shell.currentDir)
		if Shell.currentDir == "" then
			Shell.currentDir = "/"
		end
	elseif target == "." then
	elseif target == "/" then
		Shell.currentDir = "/"
	elseif target == "~" then
		local user = cepheus.users.getCurrentUser()
		if user and user.home then
			Shell.currentDir = user.home
		else
			Shell.currentDir = "/"
		end
	elseif target:sub(1, 1) == "/" then
		if fs.exists(target) and fs.isDir(target) then
			Shell.currentDir = target
		else
			cepheus.term.printError("cd: " .. target .. ": No such directory")
		end
	else
		local newDir = fs.combine(Shell.currentDir, target)
		if fs.exists(newDir) and fs.isDir(newDir) then
			Shell.currentDir = newDir
		else
			cepheus.term.printError("cd: " .. target .. ": No such directory")
		end
	end
end

function builtins.pwd(rawArgs)
	cepheus.term.print(Shell.currentDir)
end

function builtins.ls(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local paths = cepheus.parsing.getPositionalArgs(parsed)
	local longFormat = cepheus.parsing.hasFlag(parsed, "l", { "long" })
	local showAll = cepheus.parsing.hasFlag(parsed, "a", { "all" })

	local target = paths[1] or Shell.currentDir
	if paths[1] then
		target = resolvePath(target)
	end

	if not fs.exists(target) then
		cepheus.term.printError("ls: " .. target .. ": No such file or directory")
		return
	end

	if not fs.isDir(target) then
		if longFormat then
			local stat = cepheus.perms.stat(target)
			if stat then
				local ownerName = "unknown"
				local ownerInfo = cepheus.users.getUserInfo(stat.uid)
				if ownerInfo then
					ownerName = ownerInfo.username or "unknown"
				end

				local perms = cepheus.perms.formatPerms(stat.perms)
				local typeChar = stat.isDir and "d" or "-"

				cepheus.term.print(
					string.format(
						"%s%s %-8s %4d %8d %s",
						typeChar,
						perms,
						ownerName:sub(1, 8),
						stat.gid,
						stat.size,
						fs.getName(target)
					)
				)
			end
		else
			cepheus.term.print(fs.getName(target))
		end
		return
	end

	local items = fs.list(target)

	if not showAll then
		local filtered = {}
		for _, item in ipairs(items) do
			if not item:match("^%.") then
				table.insert(filtered, item)
			end
		end
		items = filtered
	end

	table.sort(items)

	if #items == 0 then
		return
	end

	if longFormat then
		for _, item in ipairs(items) do
			local fullPath = fs.combine(target, item)
			local stat = cepheus.perms.stat(fullPath)

			if stat then
				local ownerName = "unknown"
				local ownerInfo = cepheus.users.getUserInfo(stat.uid)
				if ownerInfo then
					ownerName = ownerInfo.username or "unknown"
				end

				local perms = cepheus.perms.formatPerms(stat.perms)
				local typeChar = stat.isDir and "d" or "-"

				local flags = ""
				if stat.hasSetuid then
					flags = flags .. "s"
				end
				if stat.hasSetgid then
					flags = flags .. "g"
				end
				if stat.hasSticky then
					flags = flags .. "t"
				end

				local displayName = item
				if stat.isDir then
					if term.isColor() then
						term.setTextColor(cepheus.colors.cyan)
					end
					displayName = item .. "/"
				end

				cepheus.term.print(
					string.format(
						"%s%s%-2s %-8s %4d %8d %s",
						typeChar,
						perms,
						flags,
						ownerName:sub(1, 8),
						stat.gid,
						stat.size,
						displayName
					)
				)

				if term.isColor() then
					term.setTextColor(cepheus.colors.white)
				end
			end
		end
	else
		local w, h = term.getSize()
		local maxWidth = 0

		for _, item in ipairs(items) do
			if #item > maxWidth then
				maxWidth = #item
			end
		end

		local cols = math.floor(w / (maxWidth + 2))
		if cols < 1 then
			cols = 1
		end

		local col = 0
		for _, item in ipairs(items) do
			local fullPath = fs.combine(target, item)
			local color = term.getTextColor()

			if fs.isDir(fullPath) then
				if term.isColor() then
					term.setTextColor(cepheus.colors.cyan)
				end
				term.write(item .. "/")
			else
				term.write(item)
			end

			term.setTextColor(color)

			col = col + 1
			if col >= cols then
				cepheus.term.print("")
				col = 0
			else
				term.write(string.rep(" ", maxWidth + 2 - #item - (fs.isDir(fullPath) and 1 or 0)))
			end
		end

		if col > 0 then
			cepheus.term.print("")
		end
	end
end

function builtins.mkdir(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args == 0 then
		cepheus.term.printError("Usage: mkdir <directory>")
		return
	end

	local path = resolvePath(args[1])

	if fs.exists(path) then
		cepheus.term.printError("mkdir: " .. args[1] .. ": File exists")
		return
	end

	local parent = fs.getDir(path)
	if not cepheus.perms.checkAccess(parent, cepheus.perms.PERMS.WRITE) then
		cepheus.term.printError("mkdir: Permission denied")
		return
	end

	fs.makeDir(path)

	local user = cepheus.users.getCurrentUser()
	if user then
		cepheus.perms.chown(path, user.uid, user.gid)
		cepheus.perms.chmod(path, 0x1ED)
	end
end

function builtins.rm(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)
	local recursive = cepheus.parsing.hasFlag(parsed, "r", { "recursive" })
	local force = cepheus.parsing.hasFlag(parsed, "f", { "force" })

	if #args == 0 then
		cepheus.term.printError("Usage: rm [-rf] <file>")
		return
	end

	for _, file in ipairs(args) do
		local path = resolvePath(file)

		if not fs.exists(path) then
			if not force then
				cepheus.term.printError("rm: " .. file .. ": No such file or directory")
			end
		else
			if not cepheus.perms.checkAccess(path, cepheus.perms.PERMS.WRITE) then
				cepheus.term.printError("rm: " .. file .. ": Permission denied")
			elseif fs.isDir(path) and not recursive then
				cepheus.term.printError("rm: " .. file .. ": Is a directory (use -r for recursive)")
			else
				fs.delete(path)
			end
		end
	end
end

function builtins.cp(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: cp <source> <destination>")
		return
	end

	local src = resolvePath(args[1])
	local dst = resolvePath(args[2])

	if not fs.exists(src) then
		cepheus.term.printError("cp: " .. args[1] .. ": No such file or directory")
		return
	end

	if not cepheus.perms.checkAccess(src, cepheus.perms.PERMS.READ) then
		cepheus.term.printError("cp: " .. args[1] .. ": Permission denied")
		return
	end

	local dstDir = fs.isDir(dst) and dst or fs.getDir(dst)
	if not cepheus.perms.checkAccess(dstDir, cepheus.perms.PERMS.WRITE) then
		cepheus.term.printError("cp: " .. args[2] .. ": Permission denied")
		return
	end

	fs.copy(src, dst)

	local srcStat = cepheus.perms.stat(src)
	if srcStat then
		local user = cepheus.users.getCurrentUser()
		if user then
			cepheus.perms.init(dst, user.uid, user.gid, srcStat.perms)
		end
	end
end

function builtins.mv(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: mv <source> <destination>")
		return
	end

	local src = resolvePath(args[1])
	local dst = resolvePath(args[2])

	if not fs.exists(src) then
		cepheus.term.printError("mv: " .. args[1] .. ": No such file or directory")
		return
	end

	if not cepheus.perms.checkAccess(fs.getDir(src), cepheus.perms.PERMS.WRITE) then
		cepheus.term.printError("mv: " .. args[1] .. ": Permission denied")
		return
	end

	local dstDir = fs.isDir(dst) and dst or fs.getDir(dst)
	if not cepheus.perms.checkAccess(dstDir, cepheus.perms.PERMS.WRITE) then
		cepheus.term.printError("mv: " .. args[2] .. ": Permission denied")
		return
	end

	fs.move(src, dst)
end

function builtins.chmod(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: chmod <mode> <file>")
		cepheus.term.print("Example: chmod 755 file.txt")
		return
	end

	local mode = tonumber(args[1])
	if not mode then
		cepheus.term.printError("chmod: invalid mode: " .. args[1])
		return
	end

	for i = 2, #args do
		local path = resolvePath(args[i])

		if not fs.exists(path) then
			cepheus.term.printError("chmod: " .. args[i] .. ": No such file or directory")
		else
			local success, err = pcall(cepheus.perms.chmod, path, mode)
			if not success then
				cepheus.term.printError("chmod: " .. tostring(err))
			end
		end
	end
end

function builtins.chown(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: chown <user:group> <file>")
		return
	end

	local ownerStr = args[1]
	local username, groupStr = ownerStr:match("^([^:]+):?(.*)$")

	if not username then
		cepheus.term.printError("chown: invalid owner specification")
		return
	end

	local userInfo = cepheus.users.getUserInfo(username)
	if not userInfo then
		cepheus.term.printError("chown: invalid user: " .. username)
		return
	end

	local uid = userInfo.uid
	local gid = groupStr ~= "" and tonumber(groupStr) or userInfo.gid

	for i = 2, #args do
		local path = resolvePath(args[i])

		if not fs.exists(path) then
			cepheus.term.printError("chown: " .. args[i] .. ": No such file or directory")
		else
			local success, err = pcall(cepheus.perms.chown, path, uid, gid)
			if not success then
				cepheus.term.printError("chown: " .. tostring(err))
			end
		end
	end
end

function builtins.stat(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args == 0 then
		cepheus.term.printError("Usage: stat <file>")
		return
	end

	local path = resolvePath(args[1])

	if not fs.exists(path) then
		cepheus.term.printError("stat: " .. args[1] .. ": No such file or directory")
		return
	end

	local stat = cepheus.perms.stat(path)
	if not stat then
		cepheus.term.printError("stat: Could not retrieve file information")
		return
	end

	local ownerName = "unknown"
	local userInfo = cepheus.users.getUserInfo(stat.uid)
	if userInfo then
		ownerName = userInfo.username or "unknown"
	end

	cepheus.term.print(string.format("File: %s", args[1]))
	cepheus.term.print(string.format("Size: %d bytes", stat.size))
	cepheus.term.print(string.format("Type: %s", stat.isDir and "directory" or "file"))
	cepheus.term.print(string.format("Permissions: %s (%03d)", cepheus.perms.formatPerms(stat.perms), stat.perms))
	cepheus.term.print(string.format("Owner: %s (UID: %d)", ownerName, stat.uid))
	cepheus.term.print(string.format("Group: %d", stat.gid))

	if stat.hasSetuid or stat.hasSetgid or stat.hasSticky then
		local flags = {}
		if stat.hasSetuid then
			table.insert(flags, "setuid")
		end
		if stat.hasSetgid then
			table.insert(flags, "setgid")
		end
		if stat.hasSticky then
			table.insert(flags, "sticky")
		end
		cepheus.term.print(string.format("Special flags: %s", table.concat(flags, ", ")))
	end
end

function builtins.setflags(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: setflags <file> <flag> [on|off]")
		cepheus.term.print("Flags: setuid, setgid, sticky")
		return
	end

	local path = resolvePath(args[1])
	local flag = args[2]
	local value = args[3] ~= "off"

	if not fs.exists(path) then
		cepheus.term.printError("setflags: " .. args[1] .. ": No such file or directory")
		return
	end

	if flag ~= "setuid" and flag ~= "setgid" and flag ~= "sticky" then
		cepheus.term.printError("setflags: invalid flag: " .. flag)
		return
	end

	local success, err = pcall(cepheus.perms.setFlags, path, flag, value)
	if not success then
		cepheus.term.printError("setflags: " .. tostring(err))
	else
		cepheus.term.print(string.format("Set %s %s on %s", flag, value and "on" or "off", args[1]))
	end
end

function builtins.ps(rawArgs)
	local tasks = cepheus.sched.list_tasks()

	cepheus.term.print(string.format("%-6s %-10s %-8s %-8s %-10s", "PID", "STATE", "PRIORITY", "OWNER", "CPU"))

	for _, task in ipairs(tasks) do
		cepheus.term.print(
			string.format("%-6d %-10s %-8d %-8d %-10.2f", task.pid, task.state, task.priority, task.owner, task.cpu)
		)
	end
end

function builtins.kill(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs, { valueArgs = { s = true, signal = true } })
	local args = cepheus.parsing.getPositionalArgs(parsed)
	local signal = tonumber(cepheus.parsing.getArg(parsed, "s", nil, { "signal" }))

	if #args == 0 then
		cepheus.term.printError("Usage: kill [-s <signal>] <pid>")
		return
	end

	local pid = tonumber(args[1])
	if not pid then
		cepheus.term.printError("kill: invalid PID")
		return
	end

	local success, err = pcall(cepheus.sched.kill, pid, signal)
	if not success then
		cepheus.term.printError("kill: " .. tostring(err))
	else
		cepheus.term.print("Killed task " .. pid)
	end
end

function builtins.whoami(rawArgs)
	local user = cepheus.users.getCurrentUser()
	if user then
		cepheus.term.print(user.username)
	else
		cepheus.term.print("unknown")
	end
end

function builtins.id(rawArgs)
	local user = cepheus.users.getCurrentUser()
	if not user then
		cepheus.term.printError("Not logged in")
		return
	end

	cepheus.term.print(string.format("uid=%d(%s) gid=%d", user.uid, user.username, user.gid))

	local caps = cepheus.users.getUserCapabilities(user.username)
	if #caps > 0 then
		cepheus.term.print("capabilities: " .. table.concat(caps, ", "))
	end
end

function builtins.su(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	local targetUser = args[1] or "root"

	local userInfo = cepheus.users.getUserInfo(targetUser)
	if not userInfo then
		cepheus.term.printError("su: user '" .. targetUser .. "' does not exist")
		return
	end

	term.write("Password: ")
	local password = cepheus.term.read("*")
	cepheus.term.print("")

	if not cepheus.users.authenticate(targetUser, password) then
		cepheus.term.printError("su: Authentication failed")
		return
	end

	local currentPid = cepheus.sched.current_pid()
	if currentPid > 0 and cepheus.sched._tasks[currentPid] then
		local task = cepheus.sched._tasks[currentPid]
		task.euid = userInfo.uid
		task.egid = userInfo.gid or 0
		task.owner = userInfo.uid
		task.gid = userInfo.gid or 0

		if userInfo.home and fs.exists(userInfo.home) then
			Shell.currentDir = userInfo.home
		end

		cepheus.term.print("Switched to user: " .. targetUser)
	else
		cepheus.term.printError("su: Cannot switch user (not in task context)")
	end
end

function builtins.useradd(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs, { valueArgs = { p = true, password = true } })
	local args = cepheus.parsing.getPositionalArgs(parsed)
	local password = cepheus.parsing.getArg(parsed, "p", nil, { "password" })

	if #args == 0 then
		cepheus.term.printError("Usage: useradd [-p <password>] <username>")
		return
	end

	local username = args[1]

	if not password then
		term.write("Password: ")
		password = cepheus.term.read("*")
	end

	local success, err = pcall(function()
		return cepheus.users.createUser(username, password)
	end)

	if not success then
		cepheus.term.printError("useradd: " .. tostring(err))
	else
		cepheus.term.print("User " .. username .. " created")
	end
end

function builtins.userdel(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args == 0 then
		cepheus.term.printError("Usage: userdel <username>")
		return
	end

	local username = args[1]

	local success, err = pcall(function()
		return cepheus.users.deleteUser(username)
	end)
end

function builtins.users(rawArgs)
	cepheus.term.print(string.format("%-15s %-6s %-6s", "USERNAME", "UID", "GID"))

	local usernames = cepheus.users.listUsers()

	local userList = {}
	for _, username in ipairs(usernames) do
		local userInfo = cepheus.users.getUserInfo(username)
		if userInfo then
			table.insert(userList, userInfo)
		end
	end

	table.sort(userList, function(a, b)
		return a.uid < b.uid
	end)

	for _, userInfo in ipairs(userList) do
		cepheus.term.print(string.format("%-15s %-6d %-6d", userInfo.username, userInfo.uid, userInfo.gid))
	end
end

function builtins.grant(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: grant <username> <capability>")
		cepheus.term.print("Available capabilities:")
		for _, cap in pairs(cepheus.users.CAPS) do
			cepheus.term.print("  " .. cap)
		end
		return
	end

	local username = args[1]
	local capability = args[2]

	local success, err = pcall(function()
		return cepheus.users.grantCap(username, capability)
	end)

	if not success then
		cepheus.term.printError("grant: " .. tostring(err))
	else
		cepheus.term.print("Granted " .. capability .. " to " .. username)
	end
end

function builtins.revoke(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args < 2 then
		cepheus.term.printError("Usage: revoke <username> <capability>")
		return
	end

	local username = args[1]
	local capability = args[2]

	local success, err = pcall(function()
		return cepheus.users.revokeCap(username, capability)
	end)

	if not success then
		cepheus.term.printError("revoke: " .. tostring(err))
	else
		cepheus.term.print("Revoked " .. capability .. " from " .. username)
	end
end

function builtins.clear(rawArgs)
	term.clear()
	term.setCursorPos(1, 1)
end

function builtins.echo(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)
	cepheus.term.print(table.concat(args, " "))
end

function builtins.uptime(rawArgs)
	local uptime = os.clock()
	local hours = math.floor(uptime / 3600)
	local minutes = math.floor((uptime % 3600) / 60)
	local seconds = math.floor(uptime % 60)

	cepheus.term.print(string.format("up %dh %dm %ds", hours, minutes, seconds))
end

function builtins.uname(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local showAll = cepheus.parsing.hasFlag(parsed, "a", { "all" })

	if showAll then
		local info = {}
		table.insert(info, os.version and os.version() or "AndromedaOS")
		table.insert(info, getHostname())
		table.insert(info, "ComputerCraft")
		cepheus.term.print(table.concat(info, " "))
	else
		if os.version then
			cepheus.term.print(os.version())
		else
			cepheus.term.print("AndromedaOS")
		end
	end
end

function builtins.exit(rawArgs)
	cepheus.term.print("Goodbye!")
	os.shutdown()
end

function builtins.reboot(rawArgs)
	os.reboot()
end

function builtins.alias(rawArgs)
	local parsed = cepheus.parsing.parseArgs(rawArgs)
	local args = cepheus.parsing.getPositionalArgs(parsed)

	if #args == 0 then
		for name, value in pairs(Shell.aliases) do
			cepheus.term.print(name .. "=" .. value)
		end
	elseif #args == 1 then
		if Shell.aliases[args[1]] then
			cepheus.term.print(args[1] .. "=" .. Shell.aliases[args[1]])
		else
			cepheus.term.printError("alias: " .. args[1] .. ": not found")
		end
	else
		local name = args[1]
		local value = table.concat(args, " ", 2)
		Shell.aliases[name] = value
	end
end

function builtins.help(rawArgs)
	local helpText = {
		"Available built-in commands:",
		"",
		"Navigation:",
		"  cd [dir]         - Change directory",
		"  pwd              - Print working directory",
		"  ls [-la] [dir]   - List directory contents",
		"",
		"File Operations:",
		"  mkdir <dir>      - Create directory",
		"  rm [-rf] <file>  - Remove file/directory",
		"  cp <src> <dst>   - Copy file",
		"  mv <src> <dst>   - Move/rename file",
		"",
		"File Permissions:",
		"  chmod <mode> <f> - Change permissions (e.g., chmod 755 file)",
		"  chown <u:g> <f>  - Change owner[:group]",
		"  stat <file>      - Show file info",
		"  setflag <f> <fl> - Set setuid/setgid/sticky",
		"",
		"Process Management:",
		"  ps               - List all processes",
		"  kill [-s] <pid>  - Kill a process",
		"",
		"User Management:",
		"  whoami           - Print current user",
		"  id               - Print user ID and capabilities",
		"  su [user]        - Switch user (default: root)",
		"  useradd [-p] <u> - Create user",
		"  userdel <user>   - Delete user",
		"  users            - List all users",
		"  grant <u> <c>    - Grant capability (root only)",
		"  revoke <u> <c>   - Revoke capability (root only)",
		"",
		"System:",
		"  clear            - Clear the screen",
		"  echo <text>      - Print text",
		"  uptime           - Show system uptime",
		"  uname [-a]       - Show OS version",
		"  free             - Show memory info",
		"  alias [n] [cmd]  - Set or list aliases",
		"  exit             - Shutdown the system",
		"  reboot           - Reboot the system",
		"  help             - Show this help",
	}

	cepheus.term.pager(helpText, "Shell Help")
end

local function completeFunction(text)
	if not text or text == "" or text:match("^%s+$") then
		return {}
	end

	local completions = {}
	local args = parseCommandLine(text)

	if #args == 0 or (#args == 1 and not text:match("%s$")) then
		local partial = args[1] or ""

		if partial == "" or partial:match("^%s+$") then
			return {}
		end

		for cmd in pairs(builtins) do
			if cmd:sub(1, #partial) == partial then
				table.insert(completions, cmd:sub(#partial + 1))
			end
		end

		for pathDir in Shell.path:gmatch("[^:]+") do
			if fs.exists(pathDir) and fs.isDir(pathDir) then
				for _, file in ipairs(fs.list(pathDir)) do
					local fullPath = fs.combine(pathDir, file)
					if not fs.isDir(fullPath) then
						local name = file:gsub("%.lua$", "")
						if name:sub(1, #partial) == partial then
							table.insert(completions, name:sub(#partial + 1))
						end
					end
				end
			end
		end

		for alias in pairs(Shell.aliases) do
			if alias:sub(1, #partial) == partial then
				table.insert(completions, alias:sub(#partial + 1))
			end
		end
	else
		local partial = args[#args] or ""
		local searchDir = Shell.currentDir

		if partial:match("/") then
			local dir = fs.getDir(partial)
			if dir:sub(1, 1) == "/" then
				searchDir = dir
			else
				searchDir = fs.combine(Shell.currentDir, dir)
			end
			partial = fs.getName(partial)
		end

		if fs.exists(searchDir) and fs.isDir(searchDir) then
			for _, file in ipairs(fs.list(searchDir)) do
				if file:sub(1, #partial) == partial then
					local suffix = file:sub(#partial + 1)
					local fullPath = fs.combine(searchDir, file)
					if fs.isDir(fullPath) then
						suffix = suffix .. "/"
					end
					table.insert(completions, suffix)
				end
			end
		end
	end

	return completions
end

local function executeCommand(commandLine)
	commandLine = commandLine:match("^%s*(.-)%s*$")

	if commandLine == "" then
		return
	end

	if #Shell.history == 0 or Shell.history[#Shell.history] ~= commandLine then
		table.insert(Shell.history, commandLine)
		if #Shell.history > Shell.maxHistory then
			table.remove(Shell.history, 1)
		end
	end

	local args = parseCommandLine(commandLine)
	if #args == 0 then
		return
	end

	local command = args[1]
	table.remove(args, 1)

	if builtins[command] then
		builtins[command](args)
		return
	end

	local programPath = resolveProgram(command)

	if not programPath then
		cepheus.term.printError(command .. ": command not found")
		return
	end

	local effectiveUid = cepheus.users.getEffectiveUid(programPath)

	local oldDir = Shell.currentDir
	local oldShell = _G.shell

	_G.shell = {
		dir = function()
			return Shell.currentDir
		end,
		setDir = function(dir)
			Shell.currentDir = dir
		end,
		path = function()
			return Shell.path
		end,
		setPath = function(path)
			Shell.path = path
		end,
		resolve = resolveProgram,
		resolveProgram = resolveProgram,
		aliases = Shell.aliases,
		getRunningProgram = function()
			return programPath
		end,
	}

	local entryPoint = programPath
	if programPath:match("%.app$") then
		local infoPath = fs.combine(programPath, "Contents/Info.json")
		if not fs.exists(infoPath) then
			cepheus.term.printError(command .. ": invalid .app bundle (missing Contents/Info.json)")
			_G.shell = oldShell
			return
		end

		local infoFile = fs.open(infoPath, "r")
		if not infoFile then
			cepheus.term.printError(command .. ": cannot read Info.json")
			_G.shell = oldShell
			return
		end
		local infoContent = infoFile.readAll()
		infoFile.close()

		local info = cepheus.json.decode(infoContent)
		if not info or not info.PList or not info.PList.Entry then
			cepheus.term.printError(command .. ": invalid Info.json (missing PList.Entry)")
			_G.shell = oldShell
			return
		end

		entryPoint = fs.combine(programPath, "Contents/" .. info.PList.Entry)
		if not fs.exists(entryPoint) then
			cepheus.term.printError(command .. ": entry point not found: " .. entryPoint)
			_G.shell = oldShell
			return
		end
	end

	local success, err = pcall(function()
		local pid = cepheus.sched.spawnF(entryPoint, table.unpack(args))
		if pid then
			cepheus.sched.wait(pid)
		else
			cepheus.term.printError("Could not create process")
		end
	end)

	_G.shell = oldShell

	if not success then
		cepheus.term.printError(err)
	end
end

local function shellLoop()
	term.clear()
	term.setCursorPos(1, 1)

	cepheus.term.print("AndromedaOS Shell")
	cepheus.term.print("Type 'help' for available commands")
	cepheus.term.print("")

	while true do
		local username = getUsername()
		local prompt = username == "root" and "#" or "%"
		local displayPath = getDisplayPath()

		if term.isColor() then
			term.setTextColor(cepheus.colors.cyan)
		end
		term.write(username .. "@" .. getHostname())

		if term.isColor() then
			term.setTextColor(cepheus.colors.white)
		end
		term.write(" ")

		if term.isColor() then
			term.setTextColor(cepheus.colors.yellow)
		end
		term.write(displayPath)

		if term.isColor() then
			term.setTextColor(cepheus.colors.white)
		end
		term.write(" ")

		if term.isColor() then
			if username == "root" then
				term.setTextColor(cepheus.colors.red)
			else
				term.setTextColor(cepheus.colors.white)
			end
		end
		term.write(prompt .. " ")

		if term.isColor() then
			term.setTextColor(cepheus.colors.white)
		end

		local command = cepheus.term.read(nil, Shell.history, completeFunction)

		executeCommand(command)
	end
end

shellLoop()
