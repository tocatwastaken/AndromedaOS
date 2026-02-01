local K_ARGS = { ... }
_G.cepheus = {}
cepheus.parsing = {}
cepheus.term = {}
cepheus.colors = {}

cepheus.colors.white = 0x1
cepheus.colors.orange = 0x2
cepheus.colors.magenta = 0x4
cepheus.colors.lightBlue = 0x8
cepheus.colors.yellow = 0x10
cepheus.colors.lime = 0x20
cepheus.colors.pink = 0x40
cepheus.colors.gray = 0x80
cepheus.colors.lightGray = 0x100
cepheus.colors.cyan = 0x200
cepheus.colors.purple = 0x400
cepheus.colors.blue = 0x800
cepheus.colors.brown = 0x1000
cepheus.colors.green = 0x2000
cepheus.colors.red = 0x4000
cepheus.colors.black = 0x8000

--- Validates function arguments against expected types
-- @param index The argument index (for error messages)
-- @param value The value to check
-- @param ... Expected type names
local function expect(index, value, ...)
	local valueType = type(value)
	local expectedTypes = { ... }

	for _, expectedType in ipairs(expectedTypes) do
		if valueType == expectedType then
			return value
		end
	end

	local typeList = table.concat(expectedTypes, " or ")
	error(string.format("bad argument #%d (expected %s, got %s)", index, typeList, valueType), 3)
end

cepheus.expect = expect

function loadfile(filename, mode, env)
	if type(mode) == "table" and env == nil then
		mode, env = nil, mode
	end

	expect(1, filename, "string")
	expect(2, mode, "string", "nil")
	expect(3, env, "table", "nil")

	local file = fs.open(filename, "r")
	if not file then
		return nil, "File not found"
	end

	local func, err = load(file.readAll(), "@/" .. fs.combine(filename), mode, env)
	file.close()
	return func, err
end

function dofile(path)
	expect(1, path, "string")

	local fnFile, e = loadfile(path, nil, _G)
	if fnFile then
		return fnFile()
	else
		error(e, 2)
	end
end

local package = {}
package.loaded = {}
package.path = "?.lua;?/init.lua;System/Libraries/?.lua;System/Libraries/?/init.lua"
package.preload = {}

_G.package = package

--- Implements the require function
-- @param modname The module name to require
-- @return any The module's return value
function require(modname)
	expect(1, modname, "string")

	if package.loaded[modname] then
		return package.loaded[modname]
	end

	if package.preload[modname] then
		local result = package.preload[modname](modname)
		if result == nil then
			result = true
		end
		package.loaded[modname] = result
		return result
	end

	local errors = {}

	local modpath = modname:gsub("%.", "/")

	for pattern in package.path:gmatch("[^;]+") do
		local filepath = pattern:gsub("%?", modpath)

		if fs.exists(filepath) and not fs.isDir(filepath) then
			local func, err = loadfile(filepath, nil, _G)
			if not func then
				table.insert(errors, string.format("\n\tloadfile error in '%s': %s", filepath, err))
			else
				local success, result = pcall(func, modname)
				if not success then
					error(
						string.format("error loading module '%s' from file '%s':\n\t%s", modname, filepath, result),
						2
					)
				end

				if result == nil then
					result = true
				end
				package.loaded[modname] = result
				return result
			end
		else
			table.insert(errors, string.format("\n\tno file '%s'", filepath))
		end
	end

	error(string.format("module '%s' not found:%s", modname, table.concat(errors)), 2)
end

_G.require = require

cepheus.json = dofile("System/Libraries/Perseus/json-min.lua")

--- Parses command-line arguments into a structured table
-- Supports both flags (like -v) and options with values (like -o file.txt)
-- @param args Array of argument strings (e.g., {"-v", "-o", "test.lua", "-a"})
-- @param options Optional configuration table:
--   - valueArgs: table of argument names that expect values (e.g., {o = true, output = true})
--   - allowShorthand: boolean, if true, allows combining short flags like -abc -> -a -b -c (default: false)
-- @return table Parsed arguments with flags, options, and positional args
function cepheus.parsing.parseArgs(args, options)
	expect(1, args, "table")
	expect(2, options, "table", "nil")

	options = options or {}
	local valueArgs = options.valueArgs or {}
	local allowShorthand = options.allowShorthand or false

	local parsed = {
		flags = {},
		options = {},
		positional = {},
		raw = args,
	}

	local i = 1
	while i <= #args do
		local arg = args[i]

		if string.sub(arg, 1, 1) == "-" then
			if string.sub(arg, 1, 2) == "--" then
				local name = string.sub(arg, 3)

				local equalPos = string.find(name, "=")
				if equalPos then
					local optName = string.sub(name, 1, equalPos - 1)
					local optValue = string.sub(name, equalPos + 1)
					parsed.options[optName] = optValue
					parsed.flags[optName] = true
				else
					if valueArgs[name] then
						i = i + 1
						if i <= #args and string.sub(args[i], 1, 1) ~= "-" then
							parsed.options[name] = args[i]
						else
							parsed.flags[name] = true
							i = i - 1
						end
					else
						parsed.flags[name] = true
					end
				end
			else
				local flagStr = string.sub(arg, 2)

				if allowShorthand and #flagStr > 1 then
					local firstChar = string.sub(flagStr, 1, 1)
					if valueArgs[firstChar] then
						local value = string.sub(flagStr, 2)
						parsed.options[firstChar] = value
						parsed.flags[firstChar] = true
					else
						for j = 1, #flagStr do
							local flag = string.sub(flagStr, j, j)
							parsed.flags[flag] = true
						end
					end
				else
					local name = flagStr

					if valueArgs[name] then
						i = i + 1
						if i <= #args and string.sub(args[i], 1, 1) ~= "-" then
							parsed.options[name] = args[i]
						else
							parsed.flags[name] = true
							i = i - 1
						end
					else
						parsed.flags[name] = true
					end
				end
			end
		else
			table.insert(parsed.positional, arg)
		end

		i = i + 1
	end

	return parsed
end

--- Checks if an argument exists in the parsed arguments
-- @param parsedArgs The parsed arguments table from parseArgs()
-- @param argName The argument name to check (without dashes)
-- @param aliases Optional table of alternative names for this argument
-- @return boolean, string|nil Returns true if found, and the value if it has one
function cepheus.parsing.hasArg(parsedArgs, argName, aliases)
	expect(1, parsedArgs, "table")
	expect(2, argName, "string")
	expect(3, aliases, "table", "nil")

	aliases = aliases or {}

	if parsedArgs.flags[argName] then
		return true, parsedArgs.options[argName]
	end

	for _, alias in ipairs(aliases) do
		if parsedArgs.flags[alias] then
			return true, parsedArgs.options[alias]
		end
	end

	return false, nil
end

--- Gets the value of an option argument
-- @param parsedArgs The parsed arguments table from parseArgs()
-- @param argName The argument name to get the value for
-- @param default Optional default value if argument not found
-- @param aliases Optional table of alternative names
-- @return string|nil The value of the option, or default if not found
function cepheus.parsing.getArg(parsedArgs, argName, default, aliases)
	expect(1, parsedArgs, "table")
	expect(2, argName, "string")
	expect(4, aliases, "table", "nil")

	aliases = aliases or {}

	if parsedArgs.options[argName] then
		return parsedArgs.options[argName]
	end

	for _, alias in ipairs(aliases) do
		if parsedArgs.options[alias] then
			return parsedArgs.options[alias]
		end
	end

	return default
end

--- Checks if a flag is set
-- @param parsedArgs The parsed arguments table from parseArgs()
-- @param flagName The flag name to check
-- @param aliases Optional table of alternative names
-- @return boolean True if the flag is set
function cepheus.parsing.hasFlag(parsedArgs, flagName, aliases)
	local exists = cepheus.parsing.hasArg(parsedArgs, flagName, aliases)
	return exists
end

--- Gets all positional arguments
-- @param parsedArgs The parsed arguments table from parseArgs()
-- @return table Array of positional arguments
function cepheus.parsing.getPositionalArgs(parsedArgs)
	expect(1, parsedArgs, "table")
	return parsedArgs.positional
end

--- Sleeps for a specified duration
-- @param nTime Number of seconds to sleep
-- @return boolean True if sleep completed normally
function sleep(nTime)
	expect(1, nTime, "number", "nil")

	nTime = nTime or 0

	if nTime <= 0 then
		os.queueEvent("sleep_yield")
		os.pullEvent("sleep_yield")
		return true
	end

	local timer = os.startTimer(nTime)
	local completed = false

	repeat
		local event, param = os.pullEvent("timer")
		if param == timer then
			completed = true
		end
	until completed

	return true
end

local parsedArgs = cepheus.parsing.parseArgs(K_ARGS)
local ARGS_VERBOSE = cepheus.parsing.hasFlag(parsedArgs, "verbose", { "v" })

--- Writes text to the terminal with word wrapping
-- @param sText Text to write (string or number)
-- @return number Number of lines printed
function cepheus.term.write(sText)
	expect(1, sText, "string", "number")

	local w, h = term.getSize()
	local x, y = term.getCursorPos()
	local nLinesPrinted = 0

	local function newLine()
		if y + 1 <= h then
			term.setCursorPos(1, y + 1)
		else
			term.setCursorPos(1, h)
			term.scroll(1)
		end
		x, y = term.getCursorPos()
		nLinesPrinted = nLinesPrinted + 1
	end

	sText = tostring(sText)

	if #sText == 0 then
		return 0
	end

	while #sText > 0 do
		local whitespace = string.match(sText, "^[ \t]+")
		if whitespace then
			term.write(whitespace)
			x, y = term.getCursorPos()
			sText = string.sub(sText, #whitespace + 1)
		end

		local newline = string.match(sText, "^\n")
		if newline then
			newLine()
			sText = string.sub(sText, 2)
		end

		local text = string.match(sText, "^[^ \t\n]+")
		if text then
			sText = string.sub(sText, #text + 1)

			if #text > w then
				while #text > 0 do
					if x > w then
						newLine()
					end
					term.write(text)
					text = string.sub(text, w - x + 2)
					x, y = term.getCursorPos()
				end
			else
				if x + #text - 1 > w then
					newLine()
				end
				term.write(text)
				x, y = term.getCursorPos()
			end
		end
	end

	return nLinesPrinted
end

--- Prints values with automatic spacing and newline
-- @param ... Values to print
-- @return number Total lines printed
function cepheus.term.print(...)
	local nLinesPrinted = 0
	local nArgs = select("#", ...)

	for i = 1, nArgs do
		local value = select(i, ...)
		local text = tostring(value)

		if i < nArgs then
			text = text .. "\t"
		end

		nLinesPrinted = nLinesPrinted + cepheus.term.write(text)
	end

	nLinesPrinted = nLinesPrinted + cepheus.term.write("\n")

	return nLinesPrinted
end

--- Prints error messages in red (if color supported)
-- @param ... Values to print as error
function cepheus.term.printError(...)
	local oldColour

	if term.isColour() then
		oldColour = term.getTextColour()
		term.setTextColour(cepheus.colors.red)
	end

	cepheus.term.print(...)

	if term.isColour() then
		term.setTextColour(oldColour)
	end
end

--- Reads a line of input
-- @param sReplaceChar Character to display instead of actual input (for passwords)
-- @param tHistory Table of previous inputs for history cycling
-- @param fnComplete Function to generate autocomplete suggestions
-- @param sDefault Default text to pre-populate
-- @return string The input line
function cepheus.term.read(sReplaceChar, tHistory, fnComplete, sDefault)
	expect(1, sReplaceChar, "string", "nil")
	expect(2, tHistory, "table", "nil")
	expect(3, fnComplete, "function", "nil")
	expect(4, sDefault, "string", "nil")

	term.setCursorBlink(true)

	local sLine = sDefault or ""
	local nPos = #sLine
	local nScroll = 0
	local nHistoryPos = nil

	if sReplaceChar then
		sReplaceChar = string.sub(sReplaceChar, 1, 1)
	end

	local tCompletions = nil
	local nCompletion = nil

	local function recomplete()
		if fnComplete and nPos == #sLine then
			tCompletions = fnComplete(sLine)
			if tCompletions and #tCompletions > 0 then
				nCompletion = 1
			else
				nCompletion = nil
			end
		else
			tCompletions = nil
			nCompletion = nil
		end
	end

	local function uncomplete()
		tCompletions = nil
		nCompletion = nil
	end

	local w = term.getSize()
	local sx = term.getCursorPos()

	local function redraw(bClear)
		local cursorPos = nPos - nScroll

		if sx + cursorPos >= w then
			nScroll = sx + nPos - w
		elseif cursorPos < 0 then
			nScroll = nPos
		end

		local _, cy = term.getCursorPos()
		term.setCursorPos(sx, cy)

		local sReplace = bClear and " " or sReplaceChar

		if sReplace then
			term.write(string.rep(sReplace, math.max(#sLine - nScroll, 0)))
		else
			term.write(string.sub(sLine, nScroll + 1))
		end

		if nCompletion then
			local sCompletion = tCompletions[nCompletion]
			local oldText, oldBg

			if not bClear then
				oldText = term.getTextColor()
				oldBg = term.getBackgroundColor()
				term.setTextColor(cepheus.colors.white)
				term.setBackgroundColor(cepheus.colors.gray)
			end

			if sReplace then
				term.write(string.rep(sReplace, #sCompletion))
			else
				term.write(sCompletion)
			end

			if not bClear then
				term.setTextColor(oldText)
				term.setBackgroundColor(oldBg)
			end
		end

		term.setCursorPos(sx + nPos - nScroll, cy)
	end

	local function clear()
		redraw(true)
	end

	local function acceptCompletion()
		if nCompletion then
			clear()

			local sCompletion = tCompletions[nCompletion]
			sLine = sLine .. sCompletion
			nPos = #sLine

			recomplete()
			redraw()
		end
	end

	recomplete()
	redraw()

	while true do
		local sEvent, param, param1, param2 = coroutine.yield()

		if sEvent == "char" then
			clear()
			sLine = string.format("%s%s%s", string.sub(sLine, 1, nPos), param, string.sub(sLine, nPos + 1))
			nPos = nPos + 1
			recomplete()
			redraw()
		elseif sEvent == "paste" then
			clear()
			sLine = string.format("%s%s%s", string.sub(sLine, 1, nPos), param, string.sub(sLine, nPos + 1))
			nPos = nPos + #param
			recomplete()
			redraw()
		elseif sEvent == "key" then
			if param == keys.enter or param == keys.numPadEnter then
				if nCompletion then
					clear()
					uncomplete()
					redraw()
				end
				break
			elseif param == keys.left then
				if nPos > 0 then
					clear()
					nPos = nPos - 1
					recomplete()
					redraw()
				end
			elseif param == keys.right then
				if nPos < #sLine then
					clear()
					nPos = nPos + 1
					recomplete()
					redraw()
				else
					acceptCompletion()
				end
			elseif param == keys.up or param == keys.down then
				if nCompletion then
					clear()

					if param == keys.up then
						nCompletion = nCompletion - 1
						if nCompletion < 1 then
							nCompletion = #tCompletions
						end
					else
						nCompletion = nCompletion + 1
						if nCompletion > #tCompletions then
							nCompletion = 1
						end
					end

					redraw()
				elseif tHistory then
					clear()

					if param == keys.up then
						if nHistoryPos == nil then
							if #tHistory > 0 then
								nHistoryPos = #tHistory
							end
						elseif nHistoryPos > 1 then
							nHistoryPos = nHistoryPos - 1
						end
					else
						if nHistoryPos == #tHistory then
							nHistoryPos = nil
						elseif nHistoryPos ~= nil then
							nHistoryPos = nHistoryPos + 1
						end
					end

					if nHistoryPos then
						sLine = tHistory[nHistoryPos]
						nPos = #sLine
						nScroll = 0
					else
						sLine = ""
						nPos = 0
						nScroll = 0
					end

					uncomplete()
					redraw()
				end
			elseif param == keys.backspace then
				if nPos > 0 then
					clear()
					sLine = string.format("%s%s", string.sub(sLine, 1, nPos - 1), string.sub(sLine, nPos + 1))
					nPos = nPos - 1
					if nScroll > 0 then
						nScroll = nScroll - 1
					end
					recomplete()
					redraw()
				end
			elseif param == keys.home then
				if nPos > 0 then
					clear()
					nPos = 0
					recomplete()
					redraw()
				end
			elseif param == keys.delete then
				if nPos < #sLine then
					clear()
					sLine = string.format("%s%s", string.sub(sLine, 1, nPos), string.sub(sLine, nPos + 2))
					recomplete()
					redraw()
				end
			elseif param == keys["end"] then
				if nPos < #sLine then
					clear()
					nPos = #sLine
					recomplete()
					redraw()
				end
			elseif param == keys.tab then
				acceptCompletion()
			end
		elseif sEvent == "mouse_click" or (sEvent == "mouse_drag" and param == 1) then
			local _, cy = term.getCursorPos()

			if param1 >= sx and param1 <= w and param2 == cy then
				nPos = math.min(math.max(nScroll + param1 - sx, 0), #sLine)
				redraw()
			end
		elseif sEvent == "term_resize" then
			w = term.getSize()
			redraw()
		end
	end

	local _, cy = term.getCursorPos()
	term.setCursorBlink(false)
	term.setCursorPos(w + 1, cy)
	cepheus.term.print()

	return sLine
end

local function printLog(msgType, text)
	if ARGS_VERBOSE then
		local formatted = string.format("[%-7s] %s", msgType:upper(), text)

		if term.isColour() then
			local oldColour = term.getTextColour()

			if msgType:upper() == "ERROR" or msgType:upper() == "FAIL" then
				term.setTextColour(cepheus.colors.red)
			elseif msgType:upper() == "WARN" or msgType:upper() == "WARNING" then
				term.setTextColour(cepheus.colors.yellow)
			elseif msgType:upper() == "SUCCESS" or msgType:upper() == "OK" then
				term.setTextColour(cepheus.colors.green)
			elseif msgType:upper() == "INFO" then
				term.setTextColour(cepheus.colors.cyan)
			end

			cepheus.term.print(formatted)
			term.setTextColour(oldColour)
		else
			cepheus.term.print(formatted)
		end
	end
end

local KextLoader = {}
KextLoader.loadedExtensions = {}
KextLoader.extensionData = {}

local function findExtensions(path)
	if not fs.exists(path) or not fs.isDir(path) then
		return {}
	end

	local extensions = {}
	local items = fs.list(path)

	for _, item in ipairs(items) do
		local fullPath = fs.combine(path, item)

		if fs.isDir(fullPath) and item:match("%.kext$") then
			local infoPlistPath = fs.combine(fullPath, "Contents/Info.plist")

			if fs.exists(infoPlistPath) then
				local file = fs.open(infoPlistPath, "r")
				if file then
					local content = file.readAll()
					file.close()

					local success, plist = pcall(cepheus.json.decode, content)

					if success and plist then
						plist.KextPath = fullPath
						plist.KextName = item
						table.insert(extensions, plist)
					else
						printLog("WARN", string.format("Failed to parse Info.plist for %s", item))
					end
				end
			end
		end
	end

	return extensions
end

local function validateExtension(plist)
	if not plist.BundleIdentifier then
		return false, "Missing BundleIdentifier"
	end

	if not plist.BundleName then
		return false, "Missing BundleName"
	end

	if not plist.BundleEntrypoint then
		return false, "Missing BundleEntrypoint"
	end

	if plist.BundlePackageType ~= "KEXT" then
		return false, "Invalid BundlePackageType (must be KEXT)"
	end

	if plist.Capabilities then
		if type(plist.Capabilities) ~= "table" then
			return false, "Capabilities must be a table"
		end

		if plist.Capabilities.LoadBeforeKernel ~= nil and type(plist.Capabilities.LoadBeforeKernel) ~= "boolean" then
			return false, "LoadBeforeKernel must be a boolean"
		end
	end

	if plist.OSBundleDependencies then
		if type(plist.OSBundleDependencies) ~= "table" then
			return false, "OSBundleDependencies must be a table"
		end
	end

	return true
end

local function topologicalSort(extensions)
	local graph = {}
	local inDegree = {}
	local idToExtension = {}

	for _, ext in ipairs(extensions) do
		local id = ext.BundleIdentifier
		graph[id] = {}
		inDegree[id] = 0
		idToExtension[id] = ext
	end

	for _, ext in ipairs(extensions) do
		local id = ext.BundleIdentifier
		local deps = ext.OSBundleDependencies or {}

		for depId, _ in pairs(deps) do
			if graph[depId] then
				table.insert(graph[depId], id)
				inDegree[id] = inDegree[id] + 1
			else
				printLog("WARN", string.format("Extension %s depends on %s which is not found", ext.BundleName, depId))
			end
		end
	end

	local queue = {}
	local sorted = {}

	for id, degree in pairs(inDegree) do
		if degree == 0 then
			table.insert(queue, id)
		end
	end

	while #queue > 0 do
		local current = table.remove(queue, 1)
		table.insert(sorted, idToExtension[current])

		for _, dependent in ipairs(graph[current]) do
			inDegree[dependent] = inDegree[dependent] - 1

			if inDegree[dependent] == 0 then
				table.insert(queue, dependent)
			end
		end
	end

	if #sorted ~= #extensions then
		local cyclic = {}
		for id, degree in pairs(inDegree) do
			if degree > 0 then
				table.insert(cyclic, idToExtension[id].BundleName)
			end
		end

		printLog("ERROR", string.format("Circular dependency detected in extensions: %s", table.concat(cyclic, ", ")))
		return nil
	end

	return sorted
end

local function sepExtensions(extensions)
	local preKernel = {}
	local postKernel = {}

	for _, ext in ipairs(extensions) do
		local loadBefore = false

		if ext.Capabilities and ext.Capabilities.LoadBeforeKernel == true then
			loadBefore = true
		end

		if loadBefore then
			table.insert(preKernel, ext)
		else
			table.insert(postKernel, ext)
		end
	end

	return preKernel, postKernel
end

local function loadExtension(ext, isPreKernel)
	local id = ext.BundleIdentifier

	if KextLoader.loadedExtensions[id] then
		printLog("WARN", string.format("Extension %s already loaded, skipping", ext.BundleName))
		return true
	end

	local entrypointPath = fs.combine(ext.KextPath, "Contents/AndromedaOS", ext.BundleEntrypoint)

	if not fs.exists(entrypointPath) then
		printLog("ERROR", string.format("Entrypoint not found for %s: %s", ext.BundleName, entrypointPath))
		return false
	end

	printLog(
		"INFO",
		string.format(
			"Loading %s extension: %s (v%s)",
			isPreKernel and "pre-kernel" or "post-kernel",
			ext.BundleName,
			ext.BundleVersion or "unknown"
		)
	)

	local success, result = pcall(function()
		return dofile(entrypointPath)
	end)

	if not success then
		printLog("ERROR", string.format("Failed to load %s: %s", ext.BundleName, tostring(result)))
		return false
	end

	KextLoader.loadedExtensions[id] = {
		info = ext,
		module = result,
		loadTime = isPreKernel and "pre-kernel" or "post-kernel",
	}

	if type(result) == "table" then
		local listName = result._LIST_NAME

		if listName then
			printLog("INFO", string.format("Integrating into %s", listName))

			local parts = {}
			for part in listName:gmatch("[^.]+") do
				table.insert(parts, part)
			end

			local targetTable = _G
			for i, part in ipairs(parts) do
				if not targetTable[part] then
					targetTable[part] = {}
				end
				targetTable = targetTable[part]
			end

			local count = 0
			for key, value in pairs(result) do
				if key ~= "init" and key ~= "unload" and key ~= "_LIST_NAME" then
					targetTable[key] = value
					count = count + 1
				end
			end

			printLog("INFO", string.format("Loaded %d functions into %s", count, listName))
		end

		if type(result.init) == "function" then
			local initSuccess, initError = pcall(result.init)
			if not initSuccess then
				printLog("ERROR", string.format("Failed to initialize %s: %s", ext.BundleName, tostring(initError)))
				return false
			end
		end
	end

	printLog("SUCCESS", string.format("Loaded %s", ext.BundleName))
	return true
end

local function loadExtensionGroup(extensions, isPreKernel)
	if #extensions == 0 then
		return 0
	end

	local sorted = topologicalSort(extensions)
	if not sorted then
		printLog("ERROR", "Cannot load extensions due to circular dependencies")
		return 0
	end

	local successCount = 0

	for _, ext in ipairs(sorted) do
		local valid, err = validateExtension(ext)
		if not valid then
			printLog("ERROR", string.format("Invalid extension %s: %s", ext.KextName, err))
		else
			local depsLoaded = true
			if ext.OSBundleDependencies then
				for depId, _ in pairs(ext.OSBundleDependencies) do
					if not KextLoader.loadedExtensions[depId] then
						printLog(
							"ERROR",
							string.format("Cannot load %s: dependency %s not loaded", ext.BundleName, depId)
						)
						depsLoaded = false
						break
					end
				end
			end

			if depsLoaded then
				if loadExtension(ext, isPreKernel) then
					successCount = successCount + 1
				end
			end
		end
	end

	return successCount
end

--- Main function to load all kernel extensions
-- @param path The path to the extensions directory (default: "System/Libraries/Extensions")
-- @param loadPreKernel If true, only load pre-kernel extensions
-- @param loadPostKernel If true, only load post-kernel extensions
-- @return number, number Number of pre-kernel and post-kernel extensions loaded
function KextLoader.loadExtensions(path, loadPreKernel, loadPostKernel)
	path = path or "System/Libraries/Extensions"

	if loadPreKernel == nil and loadPostKernel == nil then
		loadPreKernel = true
		loadPostKernel = true
	end

	printLog("INFO", string.format("Scanning for kernel extensions in %s", path))

	local extensions = findExtensions(path)

	if #extensions == 0 then
		printLog("INFO", "No kernel extensions found")
		return 0, 0
	end

	printLog("INFO", string.format("Found %d kernel extension(s)", #extensions))

	local preKernelExts, postKernelExts = sepExtensions(extensions)
	local preCount = 0
	local postCount = 0

	if loadPreKernel and #preKernelExts > 0 then
		printLog("INFO", string.format("Loading %d pre-kernel extension(s)", #preKernelExts))
		preCount = loadExtensionGroup(preKernelExts, true)
	end

	if loadPostKernel and #postKernelExts > 0 then
		printLog("INFO", string.format("Loading %d post-kernel extension(s)", #postKernelExts))
		postCount = loadExtensionGroup(postKernelExts, false)
	end

	printLog("INFO", string.format("Extension loading complete: %d pre-kernel, %d post-kernel", preCount, postCount))

	return preCount, postCount
end

--- Gets information about a loaded extension
-- @param bundleId The bundle identifier
-- @return table|nil Extension info, or nil if not found
function KextLoader.getLoadedExtension(bundleId)
	return KextLoader.loadedExtensions[bundleId]
end

--- Lists all loaded extensions
-- @return table Array of loaded extension info
function KextLoader.listLoadedExtensions()
	local list = {}
	for id, data in pairs(KextLoader.loadedExtensions) do
		table.insert(list, {
			id = id,
			name = data.info.BundleName,
			version = data.info.BundleVersion,
			loadTime = data.loadTime,
		})
	end
	return list
end

--- Unloads an extension (if it has an unload function)
-- @param bundleId The bundle identifier
-- @return boolean True if unloaded successfully
function KextLoader.unloadExtension(bundleId)
	local ext = KextLoader.loadedExtensions[bundleId]
	if not ext then
		return false
	end

	if type(ext.module) == "table" and type(ext.module.unload) == "function" then
		local success, err = pcall(ext.module.unload)
		if not success then
			printLog("ERROR", string.format("Failed to unload %s: %s", ext.info.BundleName, tostring(err)))
			return false
		end
	end

	KextLoader.loadedExtensions[bundleId] = nil
	printLog("INFO", string.format("Unloaded %s", ext.info.BundleName))
	return true
end

local _, postCount = KextLoader.loadExtensions("System/Libraries/Extensions", true, true)

_G.error = function(msg)
	printLog("ERROR", msg)
	coroutine.yield("key")
	os.shutdown()
end
_ENV.error = _G.error

dofile("/sbin/launchd.lua")
