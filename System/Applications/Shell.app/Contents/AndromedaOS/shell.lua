local cepheus = _G.cepheus or require("cepheus")

local Shell = {}
Shell.aliases = {}
Shell.functions = {}
Shell.path = "/Programs:/System/Programs:/System/Applications"
Shell.currentDir = "/"
Shell.completionFunctions = {}
Shell.history = {}
Shell.maxHistory = 1000
Shell.variables = {}
Shell.exitStatus = 0
Shell.jobs = {}
Shell.nextJobId = 1
Shell.foregroundJob = nil
Shell.lastBackgroundPid = nil

Shell.variables.HOME = "/"
Shell.variables.PATH = Shell.path
Shell.variables.USER = "unknown"
Shell.variables.SHELL = "/System/Programs/shell.lua"
Shell.variables.PWD = "/"
Shell.variables.OLDPWD = "/"
Shell.variables.HOSTNAME = "localhost"
Shell.variables.EDITOR = "edit"
Shell.variables.PAGER = "less"

local PipeBuffer = {}
PipeBuffer.__index = PipeBuffer

function PipeBuffer.new()
	local self = setmetatable({}, PipeBuffer)
	self.data = {}
	self.position = 1
	self.closed = false
	return self
end

function PipeBuffer:write(text)
	if self.closed then
		error("Attempt to write to closed pipe")
	end
	table.insert(self.data, tostring(text))
end

function PipeBuffer:writeLine(text)
	self:write(tostring(text) .. "\n")
end

function PipeBuffer:readLine()
	if self.position > #self.data then
		return nil
	end

	local content = table.concat(self.data, "")
	local lines = {}
	for line in content:gmatch("[^\n]*\n?") do
		if line ~= "" then
			table.insert(lines, line:gsub("\n$", ""))
		end
	end

	if self.position <= #lines then
		local line = lines[self.position]
		self.position = self.position + 1
		return line
	end

	return nil
end

function PipeBuffer:readAll()
	return table.concat(self.data, "")
end

function PipeBuffer:close()
	self.closed = true
end

local FileStream = {}
FileStream.__index = FileStream

function FileStream.new(handle)
	local self = setmetatable({}, FileStream)
	self.handle = handle
	return self
end

function FileStream:write(text)
	self.handle.write(tostring(text))
end

function FileStream:writeLine(text)
	self.handle.write(tostring(text) .. "\n")
end

function FileStream:readLine()
	return self.handle.readLine()
end

function FileStream:readAll()
	return self.handle.readAll()
end

function FileStream:close()
	self.handle.close()
end

local function getHostname()
	if _G.Config and type(_G.Config.FetchValueFromKey) == "function" then
		return _G.Config:FetchValueFromKey("Hostname") or "localhost"
	end
	return Shell.variables.HOSTNAME or "localhost"
end

local function getUsername()
	local user = cepheus.users.getCurrentUser()
	if user then
		Shell.variables.USER = user.username
		return user.username
	end
	return "unknown"
end

local function getDisplayPath()
	local user = cepheus.users.getCurrentUser()
	if user and user.home then
		Shell.variables.HOME = user.home
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

local function expandVariables(str)
	str = str:gsub("%$%{([^}]+)%}", function(varname)
		return Shell.variables[varname] or ""
	end)

	str = str:gsub("%$([A-Za-z_][A-Za-z0-9_]*)", function(varname)
		if varname == "?" then
			return tostring(Shell.exitStatus)
		elseif varname == "$" then
			return tostring(cepheus.sched.getPid())
		elseif varname == "!" then
			return tostring(Shell.lastBackgroundPid or "")
		end
		return Shell.variables[varname] or ""
	end)

	if str:sub(1, 1) == "~" then
		if str == "~" or str:sub(2, 2) == "/" then
			local home = Shell.variables.HOME or "/"
			str = home .. str:sub(2)
		end
	end

	return str
end

local function expandGlob(pattern)
	pattern = expandVariables(pattern)

	if not pattern:match("[*?%[]") then
		return { pattern }
	end

	local dir = fs.getDir(pattern)
	if dir == "" then
		dir = Shell.currentDir
	else
		dir = resolvePath(dir)
	end

	local filePattern = fs.getName(pattern)

	local luaPattern = filePattern:gsub("([%.%-%+%^%$%(%)%%])", "%%%1")
	luaPattern = luaPattern:gsub("%*", ".*")
	luaPattern = luaPattern:gsub("%?", ".")
	luaPattern = "^" .. luaPattern .. "$"

	local results = {}
	if fs.exists(dir) and fs.isDir(dir) then
		for _, file in ipairs(fs.list(dir)) do
			if file:match(luaPattern) then
				table.insert(results, fs.combine(dir, file))
			end
		end
	end

	table.sort(results)
	return #results > 0 and results or { pattern }
end

local function expandBraces(str)
	local result = { str }

	while true do
		local expanded = false
		local newResult = {}

		for _, s in ipairs(result) do
			local start, finish = s:find("%{[^{}]*%}")
			if start then
				local before = s:sub(1, start - 1)
				local braceContent = s:sub(start + 1, finish - 1)
				local after = s:sub(finish + 1)

				for item in braceContent:gmatch("[^,]+") do
					table.insert(newResult, before .. item .. after)
				end
				expanded = true
			else
				table.insert(newResult, s)
			end
		end

		result = newResult
		if not expanded then
			break
		end
	end

	return result
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
	local escape = false
	local i = 1

	while i <= #commandLine do
		local char = commandLine:sub(i, i)

		if escape then
			current = current .. char
			escape = false
		elseif char == "\\" and not inQuotes then
			escape = true
		elseif inQuotes then
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
	path = expandVariables(path)

	if path:sub(1, 1) == "/" then
		return path
	end
	return fs.combine(Shell.currentDir, path)
end

local function parseCommandPipeline(commandLine)
	local commands = {}
	local currentCmd = {
		cmd = "",
		stdin = nil,
		stdout = nil,
		stderr = nil,
		append = false,
		background = false,
	}

	local i = 1
	local inQuotes = false
	local quoteChar = nil

	while i <= #commandLine do
		local char = commandLine:sub(i, i)
		local nextChar = commandLine:sub(i + 1, i + 1)

		if inQuotes then
			if char == quoteChar then
				inQuotes = false
				quoteChar = nil
			end
			currentCmd.cmd = currentCmd.cmd .. char
		elseif char == '"' or char == "'" then
			inQuotes = true
			quoteChar = char
			currentCmd.cmd = currentCmd.cmd .. char
		elseif char == "|" then
			table.insert(commands, currentCmd)
			currentCmd = {
				cmd = "",
				stdin = nil,
				stdout = nil,
				stderr = nil,
				append = false,
				background = false,
			}
		elseif char == ">" then
			if nextChar == ">" then
				currentCmd.append = true
				i = i + 1
			end
			i = i + 1
			while i <= #commandLine and (commandLine:sub(i, i) == " " or commandLine:sub(i, i) == "\t") do
				i = i + 1
			end
			local filename = ""
			while
				i <= #commandLine
				and commandLine:sub(i, i) ~= " "
				and commandLine:sub(i, i) ~= "\t"
				and commandLine:sub(i, i) ~= "|"
				and commandLine:sub(i, i) ~= ">"
				and commandLine:sub(i, i) ~= "<"
			do
				filename = filename .. commandLine:sub(i, i)
				i = i + 1
			end
			currentCmd.stdout = filename
			i = i - 1
		elseif char == "<" then
			i = i + 1
			while i <= #commandLine and (commandLine:sub(i, i) == " " or commandLine:sub(i, i) == "\t") do
				i = i + 1
			end
			local filename = ""
			while
				i <= #commandLine
				and commandLine:sub(i, i) ~= " "
				and commandLine:sub(i, i) ~= "\t"
				and commandLine:sub(i, i) ~= "|"
				and commandLine:sub(i, i) ~= ">"
				and commandLine:sub(i, i) ~= "<"
			do
				filename = filename .. commandLine:sub(i, i)
				i = i + 1
			end
			currentCmd.stdin = filename
			i = i - 1
		elseif char == "2" and nextChar == ">" then
			i = i + 2
			if commandLine:sub(i, i) == "&" and commandLine:sub(i + 1, i + 1) == "1" then
				currentCmd.stderr = "stdout"
				i = i + 1
			else
				while i <= #commandLine and (commandLine:sub(i, i) == " " or commandLine:sub(i, i) == "\t") do
					i = i + 1
				end
				local filename = ""
				while
					i <= #commandLine
					and commandLine:sub(i, i) ~= " "
					and commandLine:sub(i, i) ~= "\t"
					and commandLine:sub(i, i) ~= "|"
				do
					filename = filename .. commandLine:sub(i, i)
					i = i + 1
				end
				currentCmd.stderr = filename
				i = i - 1
			end
		elseif char == "&" and (i == #commandLine or commandLine:sub(i + 1, i + 1):match("%s")) then
			currentCmd.background = true
		else
			currentCmd.cmd = currentCmd.cmd .. char
		end

		i = i + 1
	end

	if currentCmd.cmd:match("%S") then
		table.insert(commands, currentCmd)
	end

	return commands
end

local builtins = {}

function builtins.cd(args)
	local targetDir

	if #args == 0 then
		targetDir = Shell.variables.HOME or "/"
	elseif args[1] == "-" then
		targetDir = Shell.variables.OLDPWD or Shell.currentDir
		cepheus.term.print(targetDir)
	else
		targetDir = args[1]
	end

	targetDir = resolvePath(targetDir)

	if not fs.exists(targetDir) then
		cepheus.term.printError("cd: " .. targetDir .. ": No such file or directory")
		Shell.exitStatus = 1
		return
	end

	if not fs.isDir(targetDir) then
		cepheus.term.printError("cd: " .. targetDir .. ": Not a directory")
		Shell.exitStatus = 1
		return
	end

	Shell.variables.OLDPWD = Shell.currentDir
	Shell.currentDir = targetDir
	Shell.variables.PWD = targetDir
	Shell.exitStatus = 0
end

function builtins.pwd(args)
	local parsed = cepheus.parsing.parseArgs(args)
	if cepheus.parsing.hasFlag(parsed, "L") then
		cepheus.term.print(Shell.currentDir)
	else
		-- I don't have symlinks yet
		cepheus.term.print(Shell.currentDir)
	end
	Shell.exitStatus = 0
end

function builtins.echo(args)
	local parsed = cepheus.parsing.parseArgs(args)
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	local output = table.concat(positional, " ")

	if cepheus.parsing.hasFlag(parsed, "n") then
		cepheus.term.write(output)
	else
		cepheus.term.print(output)
	end

	Shell.exitStatus = 0
end

function builtins.printf(args)
	if #args == 0 then
		Shell.exitStatus = 0
		return
	end

	local format = args[1]
	local values = {}
	for i = 2, #args do
		table.insert(values, args[i])
	end

	local output = string.format(format, table.unpack(values))
	cepheus.term.write(output)
	Shell.exitStatus = 0
end

function builtins.export(args)
	if #args == 0 then
		for name, value in pairs(Shell.variables) do
			cepheus.term.print(string.format('export %s="%s"', name, value))
		end
		Shell.exitStatus = 0
		return
	end

	local i = 1
	while i <= #args do
		local arg = args[i]
		local name, value = arg:match("^([^=]+)=(.*)$")

		if name then
			Shell.variables[name] = value
			if name == "PATH" then
				Shell.path = value
			end
			i = i + 1
		elseif i + 2 <= #args and args[i + 1] == "=" then
			name = args[i]
			value = args[i + 2]
			Shell.variables[name] = value
			if name == "PATH" then
				Shell.path = value
			end
			i = i + 3
		else
			if not Shell.variables[arg] then
				Shell.variables[arg] = ""
			end
			i = i + 1
		end
	end

	Shell.exitStatus = 0
end

function builtins.unset(args)
	for _, name in ipairs(args) do
		Shell.variables[name] = nil
	end
	Shell.exitStatus = 0
end

function builtins.set(args)
	if #args == 0 then
		local sorted = {}
		for name in pairs(Shell.variables) do
			table.insert(sorted, name)
		end
		table.sort(sorted)

		for _, name in ipairs(sorted) do
			cepheus.term.print(string.format("%s=%s", name, Shell.variables[name]))
		end
		Shell.exitStatus = 0
		return
	end

	Shell.exitStatus = 0
end

function builtins.alias(args)
	if #args == 0 then
		for name, value in pairs(Shell.aliases) do
			cepheus.term.print(string.format("alias %s='%s'", name, value))
		end
		Shell.exitStatus = 0
		return
	end

	local aliasStr = table.concat(args, " ")
	local name, value = aliasStr:match("^([^=]+)=(.*)$")

	if name and value then
		value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
		Shell.aliases[name] = value
		Shell.exitStatus = 0
	else
		if Shell.aliases[args[1]] then
			cepheus.term.print(string.format("alias %s='%s'", args[1], Shell.aliases[args[1]]))
			Shell.exitStatus = 0
		else
			cepheus.term.printError("alias: " .. args[1] .. ": not found")
			Shell.exitStatus = 1
		end
	end
end

function builtins.unalias(args)
	if #args == 0 then
		cepheus.term.printError("unalias: missing argument")
		Shell.exitStatus = 1
		return
	end

	local parsed = cepheus.parsing.parseArgs(args)

	if cepheus.parsing.hasFlag(parsed, "a") then
		Shell.aliases = {}
		Shell.exitStatus = 0
		return
	end

	local positional = cepheus.parsing.getPositionalArgs(parsed)
	for _, name in ipairs(positional) do
		if Shell.aliases[name] then
			Shell.aliases[name] = nil
		else
			cepheus.term.printError("unalias: " .. name .. ": not found")
			Shell.exitStatus = 1
			return
		end
	end

	Shell.exitStatus = 0
end

function builtins.type(args)
	for _, cmd in ipairs(args) do
		if builtins[cmd] then
			cepheus.term.print(cmd .. " is a shell builtin")
		elseif Shell.aliases[cmd] then
			cepheus.term.print(cmd .. " is aliased to `" .. Shell.aliases[cmd] .. "'")
		elseif Shell.functions[cmd] then
			cepheus.term.print(cmd .. " is a function")
		else
			local path = resolveProgram(cmd)
			if path then
				cepheus.term.print(cmd .. " is " .. path)
			else
				cepheus.term.printError(cmd .. ": not found")
				Shell.exitStatus = 1
			end
		end
	end
	Shell.exitStatus = 0
end

function builtins.which(args)
	local parsed = cepheus.parsing.parseArgs(args)
	local showAll = cepheus.parsing.hasFlag(parsed, "a")
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	for _, cmd in ipairs(positional) do
		if builtins[cmd] then
			if not showAll then
				cepheus.term.print("shell built-in command")
			end
		elseif Shell.aliases[cmd] then
			if not showAll then
				cepheus.term.print("alias for " .. Shell.aliases[cmd])
			end
		else
			local path = resolveProgram(cmd)
			if path then
				cepheus.term.print(path)
			else
				Shell.exitStatus = 1
			end
		end
	end
end

function builtins.exit(args)
	local code = tonumber(args[1]) or Shell.exitStatus
	error("exit:" .. code)
end

function builtins.logout(args)
	error("exit:0")
end

builtins["return"] = function(args)
	local code = tonumber(args[1]) or Shell.exitStatus
	Shell.exitStatus = code
end

builtins["true"] = function(args)
	Shell.exitStatus = 0
end

builtins["false"] = function(args)
	Shell.exitStatus = 1
end

function builtins.test(args)
	if #args == 0 then
		Shell.exitStatus = 1
		return
	end

	if args[1] == "-e" and args[2] then
		Shell.exitStatus = fs.exists(resolvePath(args[2])) and 0 or 1
	elseif args[1] == "-f" and args[2] then
		local path = resolvePath(args[2])
		Shell.exitStatus = (fs.exists(path) and not fs.isDir(path)) and 0 or 1
	elseif args[1] == "-d" and args[2] then
		local path = resolvePath(args[2])
		Shell.exitStatus = (fs.exists(path) and fs.isDir(path)) and 0 or 1
	elseif args[1] == "-r" and args[2] then
		Shell.exitStatus = fs.exists(resolvePath(args[2])) and 0 or 1
	elseif args[1] == "-w" and args[2] then
		Shell.exitStatus = fs.exists(resolvePath(args[2])) and 0 or 1
	elseif args[1] == "-z" and args[2] then
		Shell.exitStatus = (#args[2] == 0) and 0 or 1
	elseif args[1] == "-n" and args[2] then
		Shell.exitStatus = (#args[2] > 0) and 0 or 1
	elseif #args == 3 then
		if args[2] == "=" or args[2] == "==" then
			Shell.exitStatus = (args[1] == args[3]) and 0 or 1
		elseif args[2] == "!=" then
			Shell.exitStatus = (args[1] ~= args[3]) and 0 or 1
		elseif args[2] == "-eq" then
			Shell.exitStatus = (tonumber(args[1]) == tonumber(args[3])) and 0 or 1
		elseif args[2] == "-ne" then
			Shell.exitStatus = (tonumber(args[1]) ~= tonumber(args[3])) and 0 or 1
		elseif args[2] == "-lt" then
			Shell.exitStatus = (tonumber(args[1]) < tonumber(args[3])) and 0 or 1
		elseif args[2] == "-le" then
			Shell.exitStatus = (tonumber(args[1]) <= tonumber(args[3])) and 0 or 1
		elseif args[2] == "-gt" then
			Shell.exitStatus = (tonumber(args[1]) > tonumber(args[3])) and 0 or 1
		elseif args[2] == "-ge" then
			Shell.exitStatus = (tonumber(args[1]) >= tonumber(args[3])) and 0 or 1
		else
			Shell.exitStatus = 1
		end
	else
		Shell.exitStatus = 1
	end
end

function builtins.history(args)
	local parsed = cepheus.parsing.parseArgs(args)
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	if cepheus.parsing.hasFlag(parsed, "c") then
		Shell.history = {}
		Shell.exitStatus = 0
		return
	end

	local count = tonumber(positional[1]) or #Shell.history
	local start = math.max(1, #Shell.history - count + 1)

	for i = start, #Shell.history do
		cepheus.term.print(string.format("%4d  %s", i, Shell.history[i]))
	end
	Shell.exitStatus = 0
end

function builtins.jobs(args)
	local hasJobs = false
	for jobId, job in pairs(Shell.jobs) do
		hasJobs = true
		local status = job.running and "Running" or "Stopped"
		cepheus.term.print(string.format("[%d]  %s  %s", jobId, status, job.command))
	end

	if not hasJobs then
	end

	Shell.exitStatus = 0
end

function builtins.fg(args)
	local jobId = tonumber(args[1]) or Shell.nextJobId - 1

	if not Shell.jobs[jobId] then
		cepheus.term.printError("fg: job not found")
		Shell.exitStatus = 1
		return
	end

	cepheus.term.print(Shell.jobs[jobId].command)
	Shell.jobs[jobId] = nil
	Shell.exitStatus = 0
end

function builtins.bg(args)
	local jobId = tonumber(args[1]) or Shell.nextJobId - 1

	if not Shell.jobs[jobId] then
		cepheus.term.printError("bg: job not found")
		Shell.exitStatus = 1
		return
	end

	Shell.jobs[jobId].running = true
	cepheus.term.print(string.format("[%d]  %s", jobId, Shell.jobs[jobId].command))
	Shell.exitStatus = 0
end

function builtins.source(args)
	if #args == 0 then
		cepheus.term.printError("source: missing file argument")
		Shell.exitStatus = 1
		return
	end

	local path = resolvePath(args[1])
	if not fs.exists(path) then
		cepheus.term.printError("source: " .. path .. ": No such file or directory")
		Shell.exitStatus = 1
		return
	end

	local file = fs.open(path, "r")
	if not file then
		cepheus.term.printError("source: cannot open " .. path)
		Shell.exitStatus = 1
		return
	end

	local content = file.readAll()
	file.close()

	for line in content:gmatch("[^\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if #line > 0 and not line:match("^#") then
			executeCommand(line)
		end
	end

	Shell.exitStatus = 0
end

builtins["."] = builtins.source

function builtins.exec(args)
	if #args == 0 then
		Shell.exitStatus = 0
		return
	end

	local commandLine = table.concat(args, " ")
	executeCommand(commandLine)
end

function builtins.eval(args)
	local commandLine = table.concat(args, " ")
	executeCommand(commandLine)
end

function builtins.shift(args)
	local n = tonumber(args[1]) or 1

	Shell.exitStatus = 0
end

function builtins.read(args)
	local parsed = cepheus.parsing.parseArgs(args)
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	local prompt = cepheus.parsing.getArg(parsed, "p")
	if prompt then
		cepheus.term.write(prompt)
	end

	local input = cepheus.term.read()

	if #positional > 0 then
		local words = {}
		for word in input:gmatch("%S+") do
			table.insert(words, word)
		end

		for i, varname in ipairs(positional) do
			if i < #positional then
				Shell.variables[varname] = words[i] or ""
			else
				local remaining = {}
				for j = i, #words do
					table.insert(remaining, words[j])
				end
				Shell.variables[varname] = table.concat(remaining, " ")
			end
		end
	else
		Shell.variables.REPLY = input
	end

	Shell.exitStatus = 0
end

function builtins.sleep(args)
	local duration = tonumber(args[1])
	if not duration then
		cepheus.term.printError("sleep: invalid time interval")
		Shell.exitStatus = 1
		return
	end

	sleep(duration)
	Shell.exitStatus = 0
end

function builtins.time(args)
	local start = os.epoch("utc")
	local commandLine = table.concat(args, " ")
	executeCommand(commandLine)
	local elapsed = os.epoch("utc") - start

	cepheus.term.printError(string.format("\nreal\t%.3fs", elapsed / 1000))
	Shell.exitStatus = 0
end

function builtins.help(args)
	if #args > 0 then
		local cmd = args[1]
		if builtins[cmd] then
			cepheus.term.print("Help for: " .. cmd)
		else
			cepheus.term.printError("help: no help topics match `" .. cmd .. "'")
			Shell.exitStatus = 1
			return
		end
	else
		cepheus.term.pager({
			"AndromedaOS Shell - Built-in Commands",
			"",
			"File Operations:",
			"  cd [dir]         - Change directory (use - for previous)",
			"  pwd [-L|-P]      - Print working directory",
			"  ls [options]     - List directory contents",
			"  cat [files]      - Display file contents",
			"  cp src dst       - Copy files",
			"  mv src dst       - Move/rename files",
			"  rm [files]       - Remove files",
			"  mkdir [dirs]     - Create directories",
			"  rmdir [dirs]     - Remove empty directories",
			"  touch [files]    - Create empty files",
			"",
			"Text Processing:",
			"  grep pattern     - Search for pattern in input",
			"  head [-n N]      - Output first N lines (default 10)",
			"  tail [-n N]      - Output last N lines (default 10)",
			"  wc [-l|-w|-c]    - Count lines, words, or characters",
			"",
			"Output:",
			"  echo [-n] [text] - Print text (use -n to omit newline)",
			"  printf fmt [args]- Format and print",
			"",
			"Variables:",
			"  export VAR=val   - Set and export environment variable",
			"  unset VAR        - Unset variable",
			"  set              - Display all variables",
			"  read [-p prompt] - Read input into variable",
			"",
			"Aliases:",
			"  alias name=cmd   - Create command alias",
			"  unalias [-a] name- Remove alias",
			"",
			"Command Info:",
			"  type cmd         - Display command type",
			"  which cmd        - Show command path",
			"  help [cmd]       - Display help",
			"",
			"Job Control:",
			"  jobs             - List background jobs",
			"  fg [job]         - Bring job to foreground",
			"  bg [job]         - Continue job in background",
			"",
			"Control Flow:",
			"  test expr        - Evaluate expression",
			"  true             - Return success (0)",
			"  false            - Return failure (1)",
			"  exit [n]         - Exit shell with code",
			"  return [n]       - Return from function",
			"",
			"Script Execution:",
			"  source file      - Execute file in current shell",
			"  . file           - Same as source",
			"  exec cmd         - Replace shell with command",
			"  eval args        - Evaluate arguments as command",
			"",
			"Utilities:",
			"  history [-c]     - Show/clear command history",
			"  sleep n          - Sleep for n seconds",
			"  time cmd         - Time command execution",
			"  clear            - Clear the screen",
			"",
			"Features:",
			"  Pipes:        cmd1 | cmd2 | cmd3",
			"  Redirects:    cmd > file, cmd >> file, cmd < file",
			"  Error redir:  cmd 2> errors.txt, cmd 2>&1",
			"  Background:   cmd &",
			"  Chains:       cmd1 && cmd2  (AND)",
			"               cmd1 || cmd2  (OR)",
			"               cmd1 ; cmd2   (sequential)",
			"  Variables:    $VAR, ${VAR}, $?, $$, $!",
			"  Globs:        *.lua, file?.txt",
			"  Braces:       {a,b,c}, {1..10}",
			"  History:      !!, !n, !$",
			"  Tilde:        ~, ~/dir",
		}, "Help")
	end
	Shell.exitStatus = 0
end

function builtins.ls(args)
	local parsed = cepheus.parsing.parseArgs(args)
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	local showAll = cepheus.parsing.hasFlag(parsed, "a")
	local longFormat = cepheus.parsing.hasFlag(parsed, "l")
	local humanReadable = cepheus.parsing.hasFlag(parsed, "h")

	local path = #positional > 0 and resolvePath(positional[1]) or Shell.currentDir

	if not fs.exists(path) then
		cepheus.term.printError("ls: cannot access '" .. path .. "': No such file or directory")
		Shell.exitStatus = 1
		return
	end

	if not fs.isDir(path) then
		cepheus.term.print(fs.getName(path))
		Shell.exitStatus = 0
		return
	end

	local files = fs.list(path)
	table.sort(files)

	if not showAll then
		local filtered = {}
		for _, file in ipairs(files) do
			if file:sub(1, 1) ~= "." then
				table.insert(filtered, file)
			end
		end
		files = filtered
	end

	if longFormat then
		for _, file in ipairs(files) do
			local fullPath = fs.combine(path, file)
			local stat = cepheus.perms.stat(fullPath)

			if stat then
				local ownerName = "unknown"
				local ownerInfo = cepheus.users.getUserInfo(stat.uid)
				if ownerInfo then
					ownerName = ownerInfo.username or "unknown"
				end

				local groupName = ownerName

				local perms = cepheus.perms.formatPerms(stat.perms)
				local typeChar = stat.isDir and "d" or "-"

				local permStr = perms
				if stat.hasSetuid then
					local ux = perms:sub(3, 3)
					permStr = perms:sub(1, 2) .. (ux == "x" and "s" or "S") .. perms:sub(4)
				end
				if stat.hasSetgid then
					local gx = perms:sub(6, 6)
					permStr = permStr:sub(1, 5) .. (gx == "x" and "s" or "S") .. permStr:sub(7)
				end
				if stat.hasSticky then
					local ox = perms:sub(9, 9)
					permStr = permStr:sub(1, 8) .. (ox == "x" and "t" or "T")
				end

				local links = 1

				local sizeStr
				if humanReadable then
					if stat.size >= 1073741824 then
						sizeStr = string.format("%4.1fG", stat.size / 1073741824)
					elseif stat.size >= 1048576 then
						sizeStr = string.format("%4.1fM", stat.size / 1048576)
					elseif stat.size >= 1024 then
						sizeStr = string.format("%4.1fK", stat.size / 1024)
					else
						sizeStr = string.format("%5d", stat.size)
					end
				else
					sizeStr = tostring(stat.size)
				end

				local timestamp
				if os.date then
					timestamp = os.date("%b %d %H:%M")
				else
					timestamp = "Jan  1 00:00"
				end

				local displayName = file
				local colorCode = ""
				local resetCode = ""

				if stat.isDir then
					if term.isColor() then
						term.setTextColor(cepheus.colors.cyan)
					end
					displayName = file
				end

				cepheus.term.print(
					string.format(
						"%s%s %2d %-8s %-8s %5s %s %s",
						typeChar,
						permStr,
						links,
						ownerName:sub(1, 8),
						groupName:sub(1, 8),
						sizeStr,
						timestamp,
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

		for _, file in ipairs(files) do
			if #file > maxWidth then
				maxWidth = #file
			end
		end

		local cols = math.floor(w / (maxWidth + 2))
		if cols < 1 then
			cols = 1
		end

		local col = 0
		for _, file in ipairs(files) do
			local fullPath = fs.combine(path, file)
			local color = term.getTextColor()

			if fs.isDir(fullPath) then
				if term.isColor() then
					term.setTextColor(cepheus.colors.cyan)
				end
				term.write(file .. "/")
			else
				term.write(file)
			end

			term.setTextColor(color)

			col = col + 1
			if col >= cols then
				cepheus.term.print("")
				col = 0
			else
				term.write(string.rep(" ", maxWidth + 2 - #file - (fs.isDir(fullPath) and 1 or 0)))
			end
		end

		if col > 0 then
			cepheus.term.print("")
		end
	end

	Shell.exitStatus = 0
end

function builtins.cat(args)
	if #args == 0 then
		local stdin = cepheus.sched.get_stdin()
		if stdin and stdin.readLine then
			local line = stdin:readLine()
			while line do
				cepheus.term.print(line)
				line = stdin:readLine()
			end
		end
		Shell.exitStatus = 0
		return
	end

	for _, arg in ipairs(args) do
		local path = resolvePath(arg)
		if not fs.exists(path) then
			cepheus.term.printError("cat: " .. arg .. ": No such file or directory")
			Shell.exitStatus = 1
			return
		end

		if fs.isDir(path) then
			cepheus.term.printError("cat: " .. arg .. ": Is a directory")
			Shell.exitStatus = 1
			return
		end

		local file = fs.open(path, "r")
		if not file then
			cepheus.term.printError("cat: " .. arg .. ": Permission denied")
			Shell.exitStatus = 1
			return
		end

		local content = file.readAll()
		file.close()

		cepheus.term.write(content)
	end

	Shell.exitStatus = 0
end

function builtins.cp(args)
	if #args < 2 then
		cepheus.term.printError("cp: missing file operand")
		Shell.exitStatus = 1
		return
	end

	local src = resolvePath(args[1])
	local dst = resolvePath(args[2])

	if not fs.exists(src) then
		cepheus.term.printError("cp: cannot stat '" .. args[1] .. "': No such file or directory")
		Shell.exitStatus = 1
		return
	end

	if fs.isDir(src) then
		cepheus.term.printError("cp: -r not specified; omitting directory '" .. args[1] .. "'")
		Shell.exitStatus = 1
		return
	end

	if fs.exists(dst) and fs.isDir(dst) then
		dst = fs.combine(dst, fs.getName(src))
	end

	fs.copy(src, dst)
	Shell.exitStatus = 0
end

function builtins.mv(args)
	if #args < 2 then
		cepheus.term.printError("mv: missing file operand")
		Shell.exitStatus = 1
		return
	end

	local src = resolvePath(args[1])
	local dst = resolvePath(args[2])

	if not fs.exists(src) then
		cepheus.term.printError("mv: cannot stat '" .. args[1] .. "': No such file or directory")
		Shell.exitStatus = 1
		return
	end

	if fs.exists(dst) and fs.isDir(dst) then
		dst = fs.combine(dst, fs.getName(src))
	end

	fs.move(src, dst)
	Shell.exitStatus = 0
end

function builtins.rm(args)
	if #args == 0 then
		cepheus.term.printError("rm: missing operand")
		Shell.exitStatus = 1
		return
	end

	local parsed = cepheus.parsing.parseArgs(args)
	local recursive = cepheus.parsing.hasFlag(parsed, "r") or cepheus.parsing.hasFlag(parsed, "R")
	local force = cepheus.parsing.hasFlag(parsed, "f")
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	for _, arg in ipairs(positional) do
		local path = resolvePath(arg)

		if not fs.exists(path) then
			if not force then
				cepheus.term.printError("rm: cannot remove '" .. arg .. "': No such file or directory")
				Shell.exitStatus = 1
			end
			goto continue
		end

		if fs.isDir(path) and not recursive then
			cepheus.term.printError("rm: cannot remove '" .. arg .. "': Is a directory")
			Shell.exitStatus = 1
			goto continue
		end

		fs.delete(path)

		::continue::
	end

	Shell.exitStatus = 0
end

function builtins.mkdir(args)
	if #args == 0 then
		cepheus.term.printError("mkdir: missing operand")
		Shell.exitStatus = 1
		return
	end

	local parsed = cepheus.parsing.parseArgs(args)
	local makeParents = cepheus.parsing.hasFlag(parsed, "p")
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	for _, arg in ipairs(positional) do
		local path = resolvePath(arg)

		if fs.exists(path) then
			cepheus.term.printError("mkdir: cannot create directory '" .. arg .. "': File exists")
			Shell.exitStatus = 1
			goto continue
		end

		if makeParents then
			local parts = {}
			for part in path:gmatch("[^/]+") do
				table.insert(parts, part)
			end

			local current = path:sub(1, 1) == "/" and "/" or ""
			for _, part in ipairs(parts) do
				current = fs.combine(current, part)
				if not fs.exists(current) then
					fs.makeDir(current)
				end
			end
		else
			fs.makeDir(path)
		end

		::continue::
	end

	Shell.exitStatus = 0
end

function builtins.rmdir(args)
	if #args == 0 then
		cepheus.term.printError("rmdir: missing operand")
		Shell.exitStatus = 1
		return
	end

	for _, arg in ipairs(args) do
		local path = resolvePath(arg)

		if not fs.exists(path) then
			cepheus.term.printError("rmdir: failed to remove '" .. arg .. "': No such file or directory")
			Shell.exitStatus = 1
			goto continue
		end

		if not fs.isDir(path) then
			cepheus.term.printError("rmdir: failed to remove '" .. arg .. "': Not a directory")
			Shell.exitStatus = 1
			goto continue
		end

		local files = fs.list(path)
		if #files > 0 then
			cepheus.term.printError("rmdir: failed to remove '" .. arg .. "': Directory not empty")
			Shell.exitStatus = 1
			goto continue
		end

		fs.delete(path)

		::continue::
	end

	Shell.exitStatus = 0
end

function builtins.touch(args)
	if #args == 0 then
		cepheus.term.printError("touch: missing file operand")
		Shell.exitStatus = 1
		return
	end

	for _, arg in ipairs(args) do
		local path = resolvePath(arg)

		if not fs.exists(path) then
			local file = fs.open(path, "w")
			if file then
				file.close()
			else
				cepheus.term.printError("touch: cannot touch '" .. arg .. "': Permission denied")
				Shell.exitStatus = 1
			end
		end
	end

	Shell.exitStatus = 0
end

function builtins.grep(args)
	if #args == 0 then
		cepheus.term.printError("grep: missing pattern")
		Shell.exitStatus = 1
		return
	end

	local pattern = args[1]
	local files = {}
	for i = 2, #args do
		table.insert(files, args[i])
	end

	local function grepContent(content, showFilename, filename)
		local matched = false
		for line in content:gmatch("[^\n]*\n?") do
			line = line:gsub("\n$", "")
			if line:match(pattern) then
				if showFilename then
					cepheus.term.print(filename .. ":" .. line)
				else
					cepheus.term.print(line)
				end
				matched = true
			end
		end
		return matched
	end

	if #files == 0 then
		local stdin = cepheus.sched.get_stdin()
		if stdin and stdin.readAll then
			local content = stdin:readAll()
			if not grepContent(content, false, nil) then
				Shell.exitStatus = 1
			end
		end
	else
		local anyMatched = false
		for _, arg in ipairs(files) do
			local path = resolvePath(arg)
			if not fs.exists(path) then
				cepheus.term.printError("grep: " .. arg .. ": No such file or directory")
				Shell.exitStatus = 2
				goto continue
			end

			if fs.isDir(path) then
				cepheus.term.printError("grep: " .. arg .. ": Is a directory")
				Shell.exitStatus = 2
				goto continue
			end

			local file = fs.open(path, "r")
			if not file then
				cepheus.term.printError("grep: " .. arg .. ": Permission denied")
				Shell.exitStatus = 2
				goto continue
			end

			local content = file.readAll()
			file.close()

			if grepContent(content, #files > 1, arg) then
				anyMatched = true
			end

			::continue::
		end

		if not anyMatched then
			Shell.exitStatus = 1
		end
	end

	Shell.exitStatus = Shell.exitStatus or 0
end

function builtins.head(args)
	local parsed = cepheus.parsing.parseArgs(args, { valueArgs = { n = true } })
	local lines = tonumber(cepheus.parsing.getArg(parsed, "n", 10))
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	local function headContent(content)
		local count = 0
		for line in content:gmatch("[^\n]*\n?") do
			if count >= lines then
				break
			end
			cepheus.term.write(line)
			count = count + 1
		end
	end

	if #positional == 0 then
		local stdin = cepheus.sched.get_stdin()
		if stdin and stdin.readAll then
			headContent(stdin:readAll())
		end
	else
		for _, arg in ipairs(positional) do
			local path = resolvePath(arg)
			if not fs.exists(path) then
				cepheus.term.printError("head: cannot open '" .. arg .. "' for reading: No such file or directory")
				Shell.exitStatus = 1
				goto continue
			end

			local file = fs.open(path, "r")
			if not file then
				cepheus.term.printError("head: cannot open '" .. arg .. "' for reading: Permission denied")
				Shell.exitStatus = 1
				goto continue
			end

			headContent(file.readAll())
			file.close()

			::continue::
		end
	end

	Shell.exitStatus = 0
end

function builtins.tail(args)
	local parsed = cepheus.parsing.parseArgs(args, { valueArgs = { n = true } })
	local lines = tonumber(cepheus.parsing.getArg(parsed, "n", 10))
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	local function tailContent(content)
		local allLines = {}
		for line in content:gmatch("[^\n]*\n?") do
			table.insert(allLines, line)
		end

		local start = math.max(1, #allLines - lines + 1)
		for i = start, #allLines do
			cepheus.term.write(allLines[i])
		end
	end

	if #positional == 0 then
		local stdin = cepheus.sched.get_stdin()
		if stdin and stdin.readAll then
			tailContent(stdin:readAll())
		end
	else
		for _, arg in ipairs(positional) do
			local path = resolvePath(arg)
			if not fs.exists(path) then
				cepheus.term.printError("tail: cannot open '" .. arg .. "' for reading: No such file or directory")
				Shell.exitStatus = 1
				goto continue
			end

			local file = fs.open(path, "r")
			if not file then
				cepheus.term.printError("tail: cannot open '" .. arg .. "' for reading: Permission denied")
				Shell.exitStatus = 1
				goto continue
			end

			tailContent(file.readAll())
			file.close()

			::continue::
		end
	end

	Shell.exitStatus = 0
end

function builtins.wc(args)
	local parsed = cepheus.parsing.parseArgs(args)
	local countLines = cepheus.parsing.hasFlag(parsed, "l")
	local countWords = cepheus.parsing.hasFlag(parsed, "w")
	local countChars = cepheus.parsing.hasFlag(parsed, "c")
	local positional = cepheus.parsing.getPositionalArgs(parsed)

	if not countLines and not countWords and not countChars then
		countLines = true
		countWords = true
		countChars = true
	end

	local function wcContent(content, filename)
		local lines = 0
		local words = 0
		local chars = #content

		for line in content:gmatch("[^\n]*\n?") do
			lines = lines + 1
			for word in line:gmatch("%S+") do
				words = words + 1
			end
		end

		local output = {}
		if countLines then
			table.insert(output, tostring(lines))
		end
		if countWords then
			table.insert(output, tostring(words))
		end
		if countChars then
			table.insert(output, tostring(chars))
		end
		if filename then
			table.insert(output, filename)
		end

		cepheus.term.print(table.concat(output, " "))
	end

	if #positional == 0 then
		local stdin = cepheus.sched.get_stdin()
		if stdin and stdin.readAll then
			wcContent(stdin:readAll(), nil)
		end
	else
		for _, arg in ipairs(positional) do
			local path = resolvePath(arg)
			if not fs.exists(path) then
				cepheus.term.printError("wc: " .. arg .. ": No such file or directory")
				Shell.exitStatus = 1
				goto continue
			end

			local file = fs.open(path, "r")
			if not file then
				cepheus.term.printError("wc: " .. arg .. ": Permission denied")
				Shell.exitStatus = 1
				goto continue
			end

			wcContent(file.readAll(), arg)
			file.close()

			::continue::
		end
	end

	Shell.exitStatus = 0
end

function builtins.clear(args)
	term.clear()
	term.setCursorPos(1, 1)
	Shell.exitStatus = 0
end

local function completeFunction(line)
	if not line or line:match("^%s*$") then
		return {}
	end

	local args = parseCommandLine(line)
	local completions = {}

	if #args == 0 or (#args == 1 and not line:match("%s$")) then
		local partial = args[1] or ""

		if partial == "" then
			return {}
		end

		for builtin in pairs(builtins) do
			if builtin:sub(1, #partial) == partial then
				table.insert(completions, builtin:sub(#partial + 1))
			end
		end

		for alias in pairs(Shell.aliases) do
			if alias:sub(1, #partial) == partial then
				table.insert(completions, alias:sub(#partial + 1))
			end
		end

		for pathDir in Shell.path:gmatch("[^:]+") do
			if fs.exists(pathDir) and fs.isDir(pathDir) then
				for _, file in ipairs(fs.list(pathDir)) do
					if file:sub(1, #partial) == partial then
						table.insert(completions, file:sub(#partial + 1))
					end
				end
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

local function executeCommandInPipeline(cmdSpec, stdinStream, stdoutStream, stderrStream)
	local args = parseCommandLine(cmdSpec.cmd)

	if #args == 0 then
		return 0
	end

	local expandedArgs = {}
	for _, arg in ipairs(args) do
		local braceExpanded = expandBraces(arg)
		for _, bArg in ipairs(braceExpanded) do
			local globExpanded = expandGlob(bArg)
			for _, gArg in ipairs(globExpanded) do
				table.insert(expandedArgs, gArg)
			end
		end
	end

	args = expandedArgs
	local command = args[1]
	table.remove(args, 1)

	if cmdSpec.stdin then
		local filename = resolvePath(cmdSpec.stdin)
		if not fs.exists(filename) then
			cepheus.term.printError(command .. ": " .. filename .. ": No such file or directory")
			return 1
		end

		local file = fs.open(filename, "r")
		if not file then
			cepheus.term.printError(command .. ": cannot open " .. filename)
			return 1
		end

		stdinStream = FileStream.new(file)
	end

	if cmdSpec.stdout then
		local filename = resolvePath(cmdSpec.stdout)
		local mode = cmdSpec.append and "a" or "w"

		local file = fs.open(filename, mode)
		if not file then
			cepheus.term.printError(command .. ": cannot create " .. filename)
			return 1
		end

		stdoutStream = FileStream.new(file)
	end

	if cmdSpec.stderr == "stdout" then
		stderrStream = stdoutStream
	elseif cmdSpec.stderr then
		local filename = resolvePath(cmdSpec.stderr)
		local file = fs.open(filename, "w")
		if not file then
			cepheus.term.printError(command .. ": cannot create " .. filename)
			return 1
		end

		stderrStream = FileStream.new(file)
	end

	if builtins[command] then
		local oldStdin = cepheus.sched.get_stdin()
		local oldStdout = cepheus.sched.get_stdout()
		local oldStderr = cepheus.sched.get_stderr()

		cepheus.sched.set_stdin(nil, stdinStream)
		cepheus.sched.set_stdout(nil, stdoutStream)
		cepheus.sched.set_stderr(nil, stderrStream)

		builtins[command](args)

		cepheus.sched.set_stdin(nil, oldStdin)
		cepheus.sched.set_stdout(nil, oldStdout)
		cepheus.sched.set_stderr(nil, oldStderr)

		if stdinStream and stdinStream.close and cmdSpec.stdin then
			stdinStream:close()
		end
		if stdoutStream and stdoutStream.close and cmdSpec.stdout then
			stdoutStream:close()
		end
		if stderrStream and stderrStream.close and cmdSpec.stderr and cmdSpec.stderr ~= "stdout" then
			stderrStream:close()
		end

		return Shell.exitStatus
	end

	if Shell.functions[command] then
		local oldStdin = cepheus.sched.get_stdin()
		local oldStdout = cepheus.sched.get_stdout()
		local oldStderr = cepheus.sched.get_stderr()

		cepheus.sched.set_stdin(nil, stdinStream)
		cepheus.sched.set_stdout(nil, stdoutStream)
		cepheus.sched.set_stderr(nil, stderrStream)

		for _, line in ipairs(Shell.functions[command]) do
			executeCommand(line)
		end

		cepheus.sched.set_stdin(nil, oldStdin)
		cepheus.sched.set_stdout(nil, oldStdout)
		cepheus.sched.set_stderr(nil, oldStderr)

		if stdinStream and stdinStream.close and cmdSpec.stdin then
			stdinStream:close()
		end
		if stdoutStream and stdoutStream.close and cmdSpec.stdout then
			stdoutStream:close()
		end
		if stderrStream and stderrStream.close and cmdSpec.stderr and cmdSpec.stderr ~= "stdout" then
			stderrStream:close()
		end

		return Shell.exitStatus
	end

	local programPath = resolveProgram(command)

	if not programPath then
		cepheus.term.printError(command .. ": command not found")
		return 127
	end

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
			cepheus.term.printError(command .. ": invalid .app bundle")
			_G.shell = oldShell
			return 1
		end

		local infoFile = fs.open(infoPath, "r")
		if not infoFile then
			cepheus.term.printError(command .. ": cannot read Info.json")
			_G.shell = oldShell
			return 1
		end
		local infoContent = infoFile.readAll()
		infoFile.close()

		local info = cepheus.json.decode(infoContent)
		if not info or not info.PList or not info.PList.Entry then
			cepheus.term.printError(command .. ": invalid Info.json")
			_G.shell = oldShell
			return 1
		end

		entryPoint = fs.combine(programPath, "Contents/" .. info.PList.Entry)
		if not fs.exists(entryPoint) then
			cepheus.term.printError(command .. ": entry point not found")
			_G.shell = oldShell
			return 1
		end
	end

	local success, err = pcall(function()
		local pid = cepheus.sched.spawnF(entryPoint, table.unpack(args))
		if pid then
			cepheus.sched.set_stdin(pid, stdinStream)
			cepheus.sched.set_stdout(pid, stdoutStream)
			cepheus.sched.set_stderr(pid, stderrStream)

			local exitCode = cepheus.sched.wait(pid)
			Shell.exitStatus = exitCode or 0
		else
			cepheus.term.printError("Could not create process")
			Shell.exitStatus = 1
		end
	end)

	_G.shell = oldShell

	if stdinStream and stdinStream.close and cmdSpec.stdin then
		stdinStream:close()
	end
	if stdoutStream and stdoutStream.close and cmdSpec.stdout then
		stdoutStream:close()
	end
	if stderrStream and stderrStream.close and cmdSpec.stderr and cmdSpec.stderr ~= "stdout" then
		stderrStream:close()
	end

	if not success then
		cepheus.term.printError(err)
		return 1
	end

	return Shell.exitStatus
end

local function executePipeline(pipeline)
	if #pipeline == 0 then
		return 0
	end

	if #pipeline == 1 then
		local exitCode = executeCommandInPipeline(pipeline[1], nil, nil, nil)
		Shell.exitStatus = exitCode
		return exitCode
	end

	local pipes = {}

	for i = 1, #pipeline - 1 do
		pipes[i] = PipeBuffer.new()
	end

	for i, cmdSpec in ipairs(pipeline) do
		local stdinSource = i > 1 and pipes[i - 1] or nil
		local stdoutTarget = i < #pipeline and pipes[i] or nil

		local exitCode = executeCommandInPipeline(cmdSpec, stdinSource, stdoutTarget, nil)

		if stdinSource then
			stdinSource:close()
		end

		if i < #pipeline then
		else
			Shell.exitStatus = exitCode
		end
	end

	return Shell.exitStatus
end

local function executeCommand(commandLine)
	commandLine = commandLine:match("^%s*(.-)%s*$")

	if commandLine == "" then
		return
	end

	if commandLine:sub(1, 1) == "#" then
		return
	end

	if commandLine:sub(1, 1) == "!" then
		if commandLine == "!!" and #Shell.history > 0 then
			commandLine = Shell.history[#Shell.history]
			cepheus.term.print(commandLine)
		elseif commandLine:match("^!%d+$") then
			local num = tonumber(commandLine:sub(2))
			if num and Shell.history[num] then
				commandLine = Shell.history[num]
				cepheus.term.print(commandLine)
			else
				cepheus.term.printError("bash: !" .. num .. ": event not found")
				Shell.exitStatus = 1
				return
			end
		elseif commandLine == "!$" and #Shell.history > 0 then
			local lastCmd = Shell.history[#Shell.history]
			local lastArgs = parseCommandLine(lastCmd)
			if #lastArgs > 0 then
				commandLine = lastArgs[#lastArgs]
				cepheus.term.print(commandLine)
			end
		end
	end

	if #Shell.history == 0 or Shell.history[#Shell.history] ~= commandLine then
		table.insert(Shell.history, commandLine)
		if #Shell.history > Shell.maxHistory then
			table.remove(Shell.history, 1)
		end
	end

	local commands = {}
	local currentCmd = ""
	local i = 1
	local inQuotes = false
	local quoteChar = nil

	while i <= #commandLine do
		local char = commandLine:sub(i, i)
		local nextChar = commandLine:sub(i + 1, i + 1)

		if inQuotes then
			if char == quoteChar then
				inQuotes = false
				quoteChar = nil
			end
			currentCmd = currentCmd .. char
		elseif char == '"' or char == "'" then
			inQuotes = true
			quoteChar = char
			currentCmd = currentCmd .. char
		elseif char == "&" and nextChar == "&" then
			table.insert(commands, { cmd = currentCmd, op = "&&" })
			currentCmd = ""
			i = i + 1
		elseif char == "|" and nextChar == "|" then
			table.insert(commands, { cmd = currentCmd, op = "||" })
			currentCmd = ""
			i = i + 1
		elseif char == ";" then
			table.insert(commands, { cmd = currentCmd, op = ";" })
			currentCmd = ""
		else
			currentCmd = currentCmd .. char
		end

		i = i + 1
	end

	if currentCmd:match("%S") then
		table.insert(commands, { cmd = currentCmd, op = nil })
	end

	for _, cmdData in ipairs(commands) do
		local shouldExecute = true

		if cmdData.op == "&&" then
			shouldExecute = (Shell.exitStatus == 0)
		elseif cmdData.op == "||" then
			shouldExecute = (Shell.exitStatus ~= 0)
		end

		if shouldExecute then
			local pipeline = parseCommandPipeline(cmdData.cmd)

			if #pipeline > 0 and pipeline[#pipeline].background then
				pipeline[#pipeline].background = false
				local jobId = Shell.nextJobId
				Shell.nextJobId = Shell.nextJobId + 1
				Shell.jobs[jobId] = {
					command = cmdData.cmd,
					running = true,
					pid = nil,
				}
				Shell.lastBackgroundPid = jobId
				cepheus.term.print(string.format("[%d] %d", jobId, jobId))
			else
				executePipeline(pipeline)
			end
		end
	end
end

local function shellLoop()
	term.clear()
	term.setCursorPos(1, 1)

	cepheus.term.print("AndromedaOS Shell")
	cepheus.term.print("Type 'help' for available commands")
	cepheus.term.print("")

	local rcPath = fs.combine(Shell.variables.HOME, ".shellrc")
	if fs.exists(rcPath) then
		builtins.source({ rcPath })
	end

	while true do
		local username = getUsername()
		local prompt = username == "root" and "#" or "$"
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
				term.setTextColor(cepheus.colors.green)
			end
		end
		term.write(prompt .. " ")

		if term.isColor() then
			term.setTextColor(cepheus.colors.white)
		end

		local command = cepheus.term.read(nil, Shell.history, completeFunction)

		local success, err = pcall(executeCommand, command)
		if not success and not err:match("^exit:") then
			cepheus.term.printError("Shell error: " .. tostring(err))
			Shell.exitStatus = 1
		elseif err and err:match("^exit:") then
			local code = tonumber(err:match("exit:(%d+)")) or 0
			break
		end
	end
end

shellLoop()
