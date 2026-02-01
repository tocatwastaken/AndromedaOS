local cepheus = _G.cepheus or require("cepheus")

local Shell = {}
Shell.aliases = {}
Shell.path = "/Programs:/System/Programs"
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

local function prettyname(name)
	if name == "" or name == "/" then
		return "/"
	end
	return name
end

local function resolveProgram(program)
	if fs.exists(program) then
		return program
	end

	local relativePath = fs.combine(Shell.currentDir, program)
	if fs.exists(relativePath) then
		return relativePath
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

local builtins = {}

function builtins.cd(args)
	local target = args[1] or "/"

	if target == ".." then
		Shell.currentDir = fs.getDir(Shell.currentDir)
		if Shell.currentDir == "" then
			Shell.currentDir = "/"
		end
	elseif target == "." then
	elseif target == "/" then
		Shell.currentDir = "/"
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

function builtins.pwd(args)
	cepheus.term.print(Shell.currentDir)
end

function builtins.ls(args)
	local target

	if not args[1] then
		target = Shell.currentDir
	else
		if args[1]:sub(1, 1) == "/" then
			target = args[1]
		else
			target = fs.combine(Shell.currentDir, args[1])
		end
	end

	if not fs.exists(target) then
		return
	end

	if fs.isDir(target) then
		local items = fs.list(target)
		table.sort(items)

		if #items == 0 then
			return
		end

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
	else
		cepheus.term.print(fs.getName(target))
	end
end

function builtins.clear(args)
	term.clear()
	term.setCursorPos(1, 1)
end

function builtins.exit(args)
	cepheus.term.print("Goodbye!")
	os.shutdown()
end

function builtins.reboot(args)
	os.reboot()
end

function builtins.alias(args)
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

function builtins.echo(args)
	cepheus.term.print(table.concat(args, " "))
end

function builtins.help(args)
	cepheus.term.print("Available built-in commands:")
	cepheus.term.print("  cd [dir]       - Change directory")
	cepheus.term.print("  pwd            - Print working directory")
	cepheus.term.print("  ls [dir]       - List directory contents")
	cepheus.term.print("  clear          - Clear the screen")
	cepheus.term.print("  exit           - Shutdown the system")
	cepheus.term.print("  reboot         - Reboot the system")
	cepheus.term.print("  alias [name] [cmd] - Set or list aliases")
	cepheus.term.print("  echo [text]    - Print text")
	cepheus.term.print("  help           - Show this help")
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

	local success, err = pcall(function()
		local func, loadErr = loadfile(programPath, nil, _G)
		if not func then
			error(loadErr)
		end
		func(table.unpack(args))
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
		term.write("[root@" .. getHostname() .. " " .. prettyname(fs.getName(Shell.currentDir)) .. "]$ ")

		local command = cepheus.term.read(nil, Shell.history, completeFunction)

		executeCommand(command)
	end
end

shellLoop()
