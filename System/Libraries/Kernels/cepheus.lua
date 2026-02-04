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

cepheus.json = dofile("System/Libraries/Persus/json-min.lua")

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
		coroutine.yield("sleep_yield")
		return true
	end

	local timer = os.startTimer(nTime)
	local completed = false

	repeat
		local event, param = coroutine.yield("timer")
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

	if cepheus.sched then
		local stdout = cepheus.sched.get_stdout()
		if stdout and stdout.write then
			stdout:write(tostring(sText))
			return 0
		end
	end

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
	if cepheus.sched then
		local stdout = cepheus.sched.get_stdout()
		if stdout and stdout.writeLine then
			local nArgs = select("#", ...)
			local parts = {}
			for i = 1, nArgs do
				table.insert(parts, tostring(select(i, ...)))
			end
			stdout:writeLine(table.concat(parts, "\t"))
			return 0
		end
	end

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

local _originalTermWrite = term.write

function term.write(text)
	if cepheus.sched then
		local stdout = cepheus.sched.get_stdout()
		if stdout and stdout.write then
			stdout:write(tostring(text))
			return
		end
	end

	_originalTermWrite(tostring(text))
end

--- Prints error messages in red (if color supported)
-- @param ... Values to print as error
function cepheus.term.printError(...)
	if cepheus.sched then
		local stderr = cepheus.sched.get_stderr()
		if stderr and stderr.writeLine then
			local nArgs = select("#", ...)
			local parts = {}
			for i = 1, nArgs do
				table.insert(parts, tostring(select(i, ...)))
			end
			stderr:writeLine(table.concat(parts, "\t"))
			return
		end
	end

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

	if cepheus.sched then
		local stdin = cepheus.sched.get_stdin()
		if stdin and stdin.readLine then
			local line = stdin:readLine()
			return line or ""
		end
	end

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

--- Display text with pagination (like 'less' or 'more')
-- @param text String or table of lines to display
-- @param title Optional title to display at the top
-- Press Enter to scroll down one line, Space to scroll down one page, q to quit
function cepheus.term.pager(text, title)
	expect(1, text, "string", "table")
	expect(2, title, "string", "nil")

	local lines = {}
	if type(text) == "string" then
		for line in text:gmatch("[^\n]*") do
			table.insert(lines, line)
		end
	else
		lines = text
	end

	local w, h = term.getSize()
	local topLine = 1
	local displayHeight = h - 1

	local function drawPage()
		term.clear()
		term.setCursorPos(1, 1)

		for i = 1, displayHeight do
			local lineNum = topLine + i - 1
			if lineNum <= #lines then
				term.setCursorPos(1, i)
				local line = lines[lineNum]
				if #line > w then
					term.write(line:sub(1, w))
				else
					term.write(line)
				end
			end
		end

		term.setCursorPos(1, h)
		if term.isColor() then
			term.setBackgroundColor(cepheus.colors.white)
			term.setTextColor(cepheus.colors.black)
		end

		local percent = math.floor((topLine / math.max(1, #lines - displayHeight + 1)) * 100)
		if topLine + displayHeight - 1 >= #lines then
			percent = 100
		end

		local status
		if title then
			status = string.format(" %s - %d%% (q=quit, Enter=line, Space=page)", title, percent)
		else
			status = string.format(
				" Line %d-%d of %d - %d%% (q=quit, Enter=line, Space=page)",
				topLine,
				math.min(topLine + displayHeight - 1, #lines),
				#lines,
				percent
			)
		end

		if #status > w then
			status = status:sub(1, w)
		else
			status = status .. string.rep(" ", w - #status)
		end
		term.write(status)

		if term.isColor() then
			term.setBackgroundColor(cepheus.colors.black)
			term.setTextColor(cepheus.colors.white)
		end
	end

	drawPage()

	while true do
		local event, key = coroutine.yield()

		if event == "key" then
			if key == keys.q then
				break
			elseif key == keys.enter then
				if topLine + displayHeight - 1 < #lines then
					topLine = topLine + 1
					drawPage()
				end
			elseif key == keys.space then
				if topLine + displayHeight - 1 < #lines then
					topLine = math.min(topLine + displayHeight, #lines - displayHeight + 1)
					drawPage()
				end
			elseif key == keys.down then
				if topLine + displayHeight - 1 < #lines then
					topLine = topLine + 1
					drawPage()
				end
			elseif key == keys.up then
				if topLine > 1 then
					topLine = topLine - 1
					drawPage()
				end
			elseif key == keys.pageDown then
				if topLine + displayHeight - 1 < #lines then
					topLine = math.min(topLine + displayHeight, #lines - displayHeight + 1)
					drawPage()
				end
			elseif key == keys.pageUp then
				if topLine > 1 then
					topLine = math.max(topLine - displayHeight, 1)
					drawPage()
				end
			elseif key == keys.home then
				topLine = 1
				drawPage()
			elseif key == keys["end"] then
				topLine = math.max(1, #lines - displayHeight + 1)
				drawPage()
			end
		elseif event == "term_resize" then
			w, h = term.getSize()
			displayHeight = h - 1
			drawPage()
		elseif event == "char" and key == "q" then
			break
		end
	end

	term.clear()
	term.setCursorPos(1, 1)
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

cepheus.users = {}

local _userDatabase = {}
local _currentUser = nil
local _userDatabaseFile = "System/users.db"
local _nextUid = 1000

cepheus.users.CAPS = {
	SPAWN = "spawn",
	KILL = "kill",
	SIGNAL = "signal",
	SET_PRIORITY = "set_priority",
	SCHEDULER_CONTROL = "scheduler_control",
	FREEZE_WORLD = "freeze_world",
	CRITICAL = "critical",
	TRACE = "trace",
	BROADCAST = "broadcast",
	CHOWN = "chown",
	SETUID = "setuid",
	USER_ADMIN = "user_admin",
}

local sha256 = dofile("/System/Libraries/Persus/sha2.lua")

--- Generate cryptographically random salt
-- @return string 32-character hex salt
local function generateSalt()
	local chars = "0123456789abcdef"
	local salt = ""
	for i = 1, 32 do
		local idx = math.random(1, #chars)
		salt = salt .. chars:sub(idx, idx)
	end
	return salt
end

--- Hash password with salt
-- @param password Plain text password
-- @param salt Salt (if nil, generates new one)
-- @return string, string Hash and salt
local function hashPassword(password, salt)
	salt = salt or generateSalt()
	local hash = sha256.sha256(salt .. password)
	return hash, salt
end

--- Verify password against hash
-- @param password Plain text password
-- @param hash Stored hash
-- @param salt Stored salt
-- @return boolean True if password matches
local function verifyPassword(password, hash, salt)
	local computed = sha256.sha256(salt .. password)
	return computed == hash
end

local function loadUsers()
	if fs.exists(_userDatabaseFile) then
		local file = fs.open(_userDatabaseFile, "r")
		local data = file.readAll()
		file.close()

		local success, result = pcall(cepheus.json.decode, data)
		if success and type(result) == "table" then
			_userDatabase = result.users or {}
			_nextUid = result.nextUid or 1000
		end
	end
end

local function saveUsers()
	local data = {
		users = _userDatabase,
		nextUid = _nextUid,
	}

	local file = fs.open(_userDatabaseFile, "w")
	file.write(cepheus.json.encode(data))
	file.close()
end

function cepheus.users.init()
	loadUsers()

	if not _userDatabase["root"] then
		local hash, salt = hashPassword("root")
		_userDatabase["root"] = {
			uid = 0,
			gid = 0,
			home = "/root",
			shell = "System/Applications/Shell.app",
			passwordHash = hash,
			passwordSalt = salt,
			capabilities = {
				[cepheus.users.CAPS.SPAWN] = true,
				[cepheus.users.CAPS.KILL] = true,
				[cepheus.users.CAPS.SIGNAL] = true,
				[cepheus.users.CAPS.SET_PRIORITY] = true,
				[cepheus.users.CAPS.SCHEDULER_CONTROL] = true,
				[cepheus.users.CAPS.FREEZE_WORLD] = true,
				[cepheus.users.CAPS.CRITICAL] = true,
				[cepheus.users.CAPS.TRACE] = true,
				[cepheus.users.CAPS.BROADCAST] = true,
				[cepheus.users.CAPS.CHOWN] = true,
				[cepheus.users.CAPS.SETUID] = true,
				[cepheus.users.CAPS.USER_ADMIN] = true,
			},
		}
		saveUsers()
		printLog("INFO", "Created default root user")
	end

	_currentUser = "root"
	printLog("INFO", "Logged in as root")
end

--- Get current user
-- @return table|nil User object copy
function cepheus.users.getCurrentUser()
	if not _currentUser or not _userDatabase[_currentUser] then
		return nil
	end

	local user = _userDatabase[_currentUser]
	return {
		username = _currentUser,
		uid = user.uid,
		gid = user.gid,
		home = user.home,
		shell = user.shell,
	}
end

--- Authenticate and switch user
-- @param username Target username
-- @param password User's password
-- @return boolean Success
function cepheus.users.authenticate(username, password)
	expect(1, username, "string")
	expect(2, password, "string")

	local user = _userDatabase[username]
	if not user then
		return false
	end

	if verifyPassword(password, user.passwordHash, user.passwordSalt) then
		_currentUser = username
		return true
	end

	return false
end

--- Authenticate for setuid execution
-- This returns the effective UID for executing setuid programs
-- @param programPath Path to program to execute
-- @return number|nil Effective UID or nil if not setuid
function cepheus.users.getEffectiveUid(programPath)
	expect(1, programPath, "string")

	local stat = cepheus.perms.stat(programPath)
	if not stat or not stat.hasSetuid then
		return nil
	end

	if not cepheus.users.hasCap(cepheus.users.CAPS.SETUID) then
		return nil
	end

	return stat.uid
end

--- Check if current user is root
-- @return boolean True if root
function cepheus.users.isRoot()
	if not _currentUser or not _userDatabase[_currentUser] then
		return false
	end
	return _userDatabase[_currentUser].uid == 0
end

--- Check if current user has capability
-- @param capability Capability name
-- @return boolean True if user has capability
function cepheus.users.hasCap(capability)
	expect(1, capability, "string")

	if not _currentUser or not _userDatabase[_currentUser] then
		return false
	end

	local user = _userDatabase[_currentUser]

	if user.uid == 0 then
		return true
	end

	return user.capabilities and user.capabilities[capability] == true
end

--- Verify password for a user
-- @param username Username
-- @param password Password to verify
-- @return boolean True if password matches
function cepheus.users.verifyPassword(username, password)
	expect(1, username, "string")
	expect(2, password, "string")

	local user = _userDatabase[username]
	if not user then
		return false
	end

	return verifyPassword(password, user.passwordHash, user.passwordSalt)
end

--- Change password
-- @param username Username
-- @param oldPassword Old password
-- @param newPassword New password
-- @return boolean Success
function cepheus.users.changePassword(username, oldPassword, newPassword)
	expect(1, username, "string")
	expect(2, oldPassword, "string")
	expect(3, newPassword, "string")

	local user = _userDatabase[username]
	if not user then
		return false
	end

	local currentUser = cepheus.users.getCurrentUser()
	local isRoot = currentUser and currentUser.uid == 0

	if not isRoot then
		if not verifyPassword(oldPassword, user.passwordHash, user.passwordSalt) then
			return false
		end
	end

	local hash, salt = hashPassword(newPassword)
	user.passwordHash = hash
	user.passwordSalt = salt

	saveUsers()
	return true
end

--- Create new user
-- @param username Username
-- @param password Password
-- @param home Home directory
-- @return boolean Success
function cepheus.users.createUser(username, password, home)
	expect(1, username, "string")
	expect(2, password, "string")
	expect(3, home, "string", "nil")

	if not cepheus.users.hasCap(cepheus.users.CAPS.USER_ADMIN) then
		error("Permission denied: requires USER_ADMIN capability")
		return
	end

	if _userDatabase[username] then
		return false, "User already exists"
	end

	home = home or ("/home/" .. username)

	local hash, salt = hashPassword(password)

	_userDatabase[username] = {
		uid = _nextUid,
		gid = _nextUid,
		home = home,
		shell = "System/Applications/Shell.app",
		passwordHash = hash,
		passwordSalt = salt,
		capabilities = {},
	}

	_nextUid = _nextUid + 1

	if not fs.exists("/home") then
		fs.makeDir("/home")
		cepheus.perms.chown("/home", 0, 0)
		cepheus.perms.chmod("/home", 0x1ED)
	end

	if not fs.exists(home) then
		fs.makeDir(home)
		cepheus.perms.chown(home, _userDatabase[username].uid, _userDatabase[username].gid)
		cepheus.perms.chmod(home, 0x1C0)
	end

	saveUsers()
	return true
end

--- Delete user
-- @param username Username
-- @return boolean Success
function cepheus.users.deleteUser(username)
	expect(1, username, "string")

	if not cepheus.users.hasCap(cepheus.users.CAPS.USER_ADMIN) then
		error("Permission denied: requires USER_ADMIN capability")
		return
	end

	if username == "root" then
		return false, "Cannot delete root user"
	end

	if not _userDatabase[username] then
		return false, "User does not exist"
	end

	if fs.exists(_userDatabase[username].home) then
		fs.delete(_userDatabase[username].home)
	end
	_userDatabase[username] = nil
	saveUsers()
	return true
end

--- Grant capability to user
-- @param username Username
-- @param capability Capability name
-- @return boolean Success
function cepheus.users.grantCap(username, capability)
	expect(1, username, "string")
	expect(2, capability, "string")

	if not cepheus.users.hasCap(cepheus.users.CAPS.USER_ADMIN) then
		error("Permission denied: requires USER_ADMIN capability")
		return
	end

	local user = _userDatabase[username]
	if not user then
		return false, "User does not exist"
	end

	if not user.capabilities then
		user.capabilities = {}
	end

	user.capabilities[capability] = true
	saveUsers()
	return true
end

--- Revoke capability from user
-- @param username Username
-- @param capability Capability name
-- @return boolean Success
function cepheus.users.revokeCap(username, capability)
	expect(1, username, "string")
	expect(2, capability, "string")

	if not cepheus.users.hasCap(cepheus.users.CAPS.USER_ADMIN) then
		error("Permission denied: requires USER_ADMIN capability")
		return
	end

	if username == "root" then
		return false, "Cannot revoke capabilities from root"
	end

	local user = _userDatabase[username]
	if not user then
		return false, "User does not exist"
	end

	if user.capabilities then
		user.capabilities[capability] = nil
	end

	saveUsers()
	return true
end

--- Get read-only user list
-- @return table Array of usernames
function cepheus.users.listUsers()
	local users = {}
	for username, _ in pairs(_userDatabase) do
		table.insert(users, username)
	end
	return users
end

--- Get read-only user info
-- @param username Username OR UID
-- @return table|nil User info (no password data!)
function cepheus.users.getUserInfo(username)
	if type(username) == "number" then
		local uid = username
		for uname, user in pairs(_userDatabase) do
			if user.uid == uid then
				return {
					username = uname,
					uid = user.uid,
					gid = user.gid,
					home = user.home,
					shell = user.shell,
				}
			end
		end
		return nil
	end

	expect(1, username, "string")

	local user = _userDatabase[username]
	if not user then
		return nil
	end

	return {
		username = username,
		uid = user.uid,
		gid = user.gid,
		home = user.home,
		shell = user.shell,
	}
end

--- Get user capabilities
-- @param username Username
-- @return table List of capability names
function cepheus.users.getUserCapabilities(username)
	expect(1, username, "string")

	local user = _userDatabase[username]
	if not user then
		return {}
	end

	if user.uid == 0 then
		local allCaps = {}
		for _, cap in pairs(cepheus.users.CAPS) do
			table.insert(allCaps, cap)
		end
		return allCaps
	end

	local caps = {}
	if user.capabilities then
		for cap, granted in pairs(user.capabilities) do
			if granted then
				table.insert(caps, cap)
			end
		end
	end

	return caps
end

cepheus.perms = {}

cepheus.perms.PERMS = {
	READ = 4,
	WRITE = 2,
	EXEC = 1,
}

cepheus.perms.FLAGS = {
	SETUID = 0x800,
	SETGID = 0x400,
	STICKY = 0x200,
}

cepheus.perms._metaCache = {}

local _originalFs = {}
for k, v in pairs(fs) do
	_originalFs[k] = v
end

local _metaCleaner = {}

local function deleteAllMetaFilesInternal(startPath, options)
	startPath = startPath or "/"
	options = options or {}
	local dryRun = options.dryRun or false
	local excludePaths = options.excludePaths or {}
	local stats = { metaFilesFound = 0, metaFilesDeleted = 0, directoriesScanned = 0, errors = {} }

	local function isExcluded(path)
		for _, excludePath in ipairs(excludePaths) do
			if path == excludePath or path:sub(1, #excludePath + 1) == excludePath .. "/" then
				return true
			end
		end
		return false
	end

	local function scanDirectory(dirPath)
		if isExcluded(dirPath) then
			return
		end
		stats.directoriesScanned = stats.directoriesScanned + 1
		if not _originalFs.exists(dirPath) or not _originalFs.isDir(dirPath) then
			return
		end

		local metaPath = _originalFs.combine(dirPath, ".meta")
		if _originalFs.exists(metaPath) and not _originalFs.isDir(metaPath) then
			stats.metaFilesFound = stats.metaFilesFound + 1
			if not dryRun then
				local success, err = pcall(function()
					_originalFs.delete(metaPath)
					if cepheus.perms._metaCache then
						cepheus.perms._metaCache[dirPath] = nil
					end
				end)
				if success then
					stats.metaFilesDeleted = stats.metaFilesDeleted + 1
				else
					table.insert(stats.errors, "Failed to delete " .. metaPath .. ": " .. tostring(err))
				end
			end
		end

		local success, items = pcall(function()
			return _originalFs.list(dirPath)
		end)
		if success then
			for _, item in ipairs(items) do
				local itemPath = _originalFs.combine(dirPath, item)
				if _originalFs.isDir(itemPath) and item ~= ".meta" then
					scanDirectory(itemPath)
				end
			end
		end
	end

	scanDirectory(startPath)
	return stats
end

_metaCleaner.deleteAll = function(options)
	return deleteAllMetaFilesInternal("/", options)
end

_metaCleaner.deleteInPath = function(path, options)
	return deleteAllMetaFilesInternal(path, options)
end

_metaCleaner.clearCache = function()
	if cepheus.perms._metaCache then
		cepheus.perms._metaCache = {}
	end
end

--- Encode permissions metadata to binary format
-- Format: <version:1><entries:2><entry1><entry2>...
-- Entry: <nameLen:1><name:nameLen><uid:2><gid:2><perms:2><flags:2>
local function encodeMetadata(entries)
	local data = {}

	table.insert(data, string.char(1))

	local count = 0
	for _ in pairs(entries) do
		count = count + 1
	end
	table.insert(data, string.char(math.floor(count / 256)))
	table.insert(data, string.char(count % 256))

	for name, entry in pairs(entries) do
		local nameLen = math.min(#name, 255)
		table.insert(data, string.char(nameLen))

		table.insert(data, name:sub(1, nameLen))

		table.insert(data, string.char(math.floor(entry.uid / 256)))
		table.insert(data, string.char(entry.uid % 256))

		table.insert(data, string.char(math.floor(entry.gid / 256)))
		table.insert(data, string.char(entry.gid % 256))

		table.insert(data, string.char(math.floor(entry.perms / 256)))
		table.insert(data, string.char(entry.perms % 256))

		table.insert(data, string.char(math.floor(entry.flags / 256)))
		table.insert(data, string.char(entry.flags % 256))
	end

	return table.concat(data)
end

local function decodeMetadata(data)
	if not data or #data < 3 then
		return nil, "Invalid metadata"
	end

	local pos = 1

	local version = string.byte(data, pos)
	pos = pos + 1

	if version ~= 1 then
		return nil, "Unsupported metadata version"
	end

	local countHigh = string.byte(data, pos)
	local countLow = string.byte(data, pos + 1)
	local count = countHigh * 256 + countLow
	pos = pos + 2

	local entries = {}

	for i = 1, count do
		if pos > #data then
			break
		end

		local nameLen = string.byte(data, pos)
		pos = pos + 1

		if pos + nameLen - 1 > #data then
			break
		end

		local name = data:sub(pos, pos + nameLen - 1)
		pos = pos + nameLen

		if pos + 7 > #data then
			break
		end

		local uidHigh = string.byte(data, pos)
		local uidLow = string.byte(data, pos + 1)
		local uid = uidHigh * 256 + uidLow
		pos = pos + 2

		local gidHigh = string.byte(data, pos)
		local gidLow = string.byte(data, pos + 1)
		local gid = gidHigh * 256 + gidLow
		pos = pos + 2

		local permsHigh = string.byte(data, pos)
		local permsLow = string.byte(data, pos + 1)
		local perms = permsHigh * 256 + permsLow
		pos = pos + 2

		local flagsHigh = string.byte(data, pos)
		local flagsLow = string.byte(data, pos + 1)
		local flags = flagsHigh * 256 + flagsLow
		pos = pos + 2

		entries[name] = {
			uid = uid,
			gid = gid,
			perms = perms,
			flags = flags,
		}
	end

	return entries
end

local function getDirectoryMeta(dirPath)
	if cepheus.perms._metaCache[dirPath] then
		return cepheus.perms._metaCache[dirPath]
	end

	local metaPath = _originalFs.combine(dirPath, ".meta")

	if not _originalFs.exists(metaPath) then
		local entries = {}

		if _originalFs.exists(dirPath) and _originalFs.isDir(dirPath) then
			local items = _originalFs.list(dirPath)

			for _, item in ipairs(items) do
				if item ~= ".meta" then
					local itemPath = _originalFs.combine(dirPath, item)
					local isDir = _originalFs.isDir(itemPath)

					entries[item] = {
						uid = 0,
						gid = 0,
						perms = isDir and 0x1ED or 0x1A4,
						flags = 0,
					}
				end
			end
		end

		local encoded = encodeMetadata(entries)
		local file = _originalFs.open(metaPath, "wb")
		if file then
			file.write(encoded)
			file.close()
		end

		cepheus.perms._metaCache[dirPath] = entries
		return entries
	end

	local file = _originalFs.open(metaPath, "rb")
	if not file then
		return {}
	end

	local data = file.readAll()
	file.close()

	local entries, err = decodeMetadata(data)
	if not entries then
		printLog("WARN", "Failed to decode .meta in " .. dirPath .. ": " .. err)
		return {}
	end

	cepheus.perms._metaCache[dirPath] = entries
	return entries
end

local function updateMeta(path, uid, gid, perms, flags)
	local dir = _originalFs.getDir(path)
	if dir == "" then
		dir = "/"
	end
	local name = _originalFs.getName(path)

	local meta = getDirectoryMeta(dir)

	meta[name] = {
		uid = uid,
		gid = gid,
		perms = perms,
		flags = flags or 0,
	}

	cepheus.perms._metaCache[dir] = nil

	local metaPath = _originalFs.combine(dir, ".meta")
	local encoded = encodeMetadata(meta)
	local file = _originalFs.open(metaPath, "wb")
	if file then
		file.write(encoded)
		file.close()
	end

	cepheus.perms._metaCache[dir] = meta
end

--- Get metadata for a specific file/directory
function cepheus.perms.getMeta(path)
	local systemPaths = {
		[""] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },

		["/"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },

		["/startup.lua"] = { uid = 0, gid = 0, perms = 0x000, flags = 0 },

		["/System"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },

		["/System/Applications"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/System/Libraries"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/System/Config"] = { uid = 0, gid = 0, perms = 0x1C0, flags = 0 },

		["/System/Logs"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/System/Resources"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/System/Drivers"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/sbin"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/home"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },

		["/Applications"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
		["/Programs"] = { uid = 0, gid = 0, perms = 0x1ED, flags = 0 },
	}

	if systemPaths[path] then
		return systemPaths[path]
	end

	local dir = _originalFs.getDir(path)
	if dir == "" then
		dir = "/"
	end
	local name = _originalFs.getName(path)

	local meta = getDirectoryMeta(dir)
	local result = meta[name]

	if not result and _originalFs.exists(path) then
		local isDir = _originalFs.isDir(path)
		return {
			uid = 0,
			gid = 0,
			perms = isDir and 0x1ED or 0x1A4,

			flags = 0,
		}
	end

	return result
end

local function checkPermission(path, requiredPerm)
	local euid, egid
	local currentPid = cepheus.sched and cepheus.sched.current_pid and cepheus.sched.current_pid() or 0

	if currentPid > 0 and cepheus.sched._tasks and cepheus.sched._tasks[currentPid] then
		local task = cepheus.sched._tasks[currentPid]
		euid = task.euid or task.owner or 0
		egid = task.egid or task.gid or 0
	else
		local currentUser = cepheus.users.getCurrentUser()
		if currentUser then
			euid = currentUser.uid
			egid = currentUser.gid or 0
		else
			euid = 0
			egid = 0
		end
	end

	if euid == 0 then
		return true
	end

	local meta = cepheus.perms.getMeta(path)
	if not meta then
		return false
	end

	if meta.uid == euid then
		local ownerPerms = math.floor(meta.perms / 64) % 8
		return bit32.band(ownerPerms, requiredPerm) ~= 0
	end

	if meta.gid == egid then
		local groupPerms = math.floor(meta.perms / 8) % 8
		return bit32.band(groupPerms, requiredPerm) ~= 0
	end

	local otherPerms = meta.perms % 8
	return bit32.band(otherPerms, requiredPerm) ~= 0
end

--- Set file permissions (chmod)
function cepheus.perms.chmod(path, perms)
	expect(1, path, "string")
	expect(2, perms, "number")

	if not _originalFs.exists(path) then
		error("File not found: " .. path)
		return
	end

	local meta = cepheus.perms.getMeta(path) or {}

	local currentUser = cepheus.users.getCurrentUser()
	if not cepheus.users.isRoot() and meta.uid and meta.uid ~= currentUser.uid then
		error("Permission denied: not file owner")
		return
	end

	updateMeta(path, meta.uid or 0, meta.gid or 0, perms, meta.flags or 0)
end

--- Set file owner (chown)
function cepheus.perms.chown(path, uid, gid)
	expect(1, path, "string")
	expect(2, uid, "number")
	expect(3, gid, "number", "nil")

	if not cepheus.users.isRoot() then
		error("Permission denied: only root can change ownership")
		return
	end

	if not _originalFs.exists(path) then
		error("File not found: " .. path)
		return
	end

	local meta = cepheus.perms.getMeta(path) or {}
	gid = gid or meta.gid or 0

	updateMeta(path, uid, gid, meta.perms or 0x1A4, meta.flags or 0)
end

--- Set special flags (setuid, setgid, sticky)
function cepheus.perms.setFlags(path, flags)
	expect(1, path, "string")
	expect(2, flags, "number")

	if not cepheus.users.isRoot() then
		error("Permission denied: only root can set special flags")
		return
	end

	if not _originalFs.exists(path) then
		error("File not found: " .. path)
		return
	end

	local meta = cepheus.perms.getMeta(path) or {}
	updateMeta(path, meta.uid or 0, meta.gid or 0, meta.perms or 0x1A4, flags)
end

--- Get file statistics
function cepheus.perms.stat(path)
	expect(1, path, "string")

	if not _originalFs.exists(path) then
		return nil, "File not found"
	end

	local meta = cepheus.perms.getMeta(path)
		or {
			uid = 0,
			gid = 0,
			perms = _originalFs.isDir(path) and 0x1ED or 0x1A4,
			flags = 0,
		}

	return {
		path = path,
		isDir = _originalFs.isDir(path),
		size = _originalFs.isDir(path) and 0 or _originalFs.getSize(path),
		uid = meta.uid,
		gid = meta.gid,
		perms = meta.perms,
		flags = meta.flags,
		hasSetuid = bit32.band(meta.flags, cepheus.perms.FLAGS.SETUID) ~= 0,
		hasSetgid = bit32.band(meta.flags, cepheus.perms.FLAGS.SETGID) ~= 0,
		hasSticky = bit32.band(meta.flags, cepheus.perms.FLAGS.STICKY) ~= 0,
	}
end

function cepheus.perms.formatPerms(perms)
	local function bit(p, n)
		return bit32.band(p, n) ~= 0
	end

	local result = ""

	result = result .. (bit(perms, 0x100) and "r" or "-")
	result = result .. (bit(perms, 0x80) and "w" or "-")
	result = result .. (bit(perms, 0x40) and "x" or "-")

	result = result .. (bit(perms, 0x20) and "r" or "-")
	result = result .. (bit(perms, 0x10) and "w" or "-")
	result = result .. (bit(perms, 0x8) and "x" or "-")

	result = result .. (bit(perms, 0x4) and "r" or "-")
	result = result .. (bit(perms, 0x2) and "w" or "-")
	result = result .. (bit(perms, 0x1) and "x" or "-")

	return result
end

--- Check if current user has access to a path with required permissions
-- @param path Path to check
-- @param requiredPerm Required permission (cepheus.perms.PERMS.READ/WRITE/EXEC)
-- @return boolean True if access is allowed
function cepheus.perms.checkAccess(path, requiredPerm)
	return checkPermission(path, requiredPerm)
end

--- Check if user can traverse to a path (has execute on all parent dirs)
-- @param path Path to check
-- @return boolean True if path is accessible
local function checkPathTraversal(path)
	local euid = 0
	local currentPid = cepheus.sched and cepheus.sched.current_pid and cepheus.sched.current_pid() or 0

	if currentPid > 0 and cepheus.sched._tasks and cepheus.sched._tasks[currentPid] then
		local task = cepheus.sched._tasks[currentPid]
		euid = task.euid or task.owner or 0
	else
		local currentUser = cepheus.users.getCurrentUser()
		if currentUser then
			euid = currentUser.uid
		end
	end

	if euid == 0 then
		return true
	end

	local current = path
	while current ~= "" and current ~= "/" do
		current = _originalFs.getDir(current)
		if current ~= "" and current ~= "/" then
			if not checkPermission(current, cepheus.perms.PERMS.EXEC) then
				return false
			end
		end
	end

	return true
end

local _wrappedFs = {}

for k, v in pairs(_originalFs) do
	_wrappedFs[k] = v
end

function _wrappedFs.open(path, mode)
	if not checkPathTraversal(path) then
		return nil, "Permission denied: cannot access parent directory"
	end

	local requiredPerm = mode:match("r") and cepheus.perms.PERMS.READ or 0
	requiredPerm = requiredPerm + (mode:match("w") and cepheus.perms.PERMS.WRITE or 0)
	requiredPerm = requiredPerm + (mode:match("a") and cepheus.perms.PERMS.WRITE or 0)

	if not checkPermission(path, requiredPerm) then
		return nil, "Permission denied"
	end

	return _originalFs.open(path, mode)
end

function _wrappedFs.delete(path)
	if not checkPathTraversal(path) then
		error("Permission denied: cannot access parent directory", 2)
		return
	end

	if not checkPermission(path, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: " .. path, 2)
		return
	end

	local parent = _originalFs.getDir(path)
	if parent == "" then
		parent = "/"
	end
	if not checkPermission(parent, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: cannot modify " .. parent, 2)
		return
	end

	cepheus.perms._metaCache[parent] = nil

	return _originalFs.delete(path)
end

function _wrappedFs.move(fromPath, toPath)
	if not checkPathTraversal(fromPath) then
		error("Permission denied: cannot access source parent directory", 2)
		return
	end

	if not checkPathTraversal(toPath) then
		error("Permission denied: cannot access destination parent directory", 2)
		return
	end

	if not checkPermission(fromPath, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: " .. fromPath, 2)
		return
	end

	local fromParent = _originalFs.getDir(fromPath)
	if fromParent == "" then
		fromParent = "/"
	end
	local toParent = _originalFs.getDir(toPath)
	if toParent == "" then
		toParent = "/"
	end

	if not checkPermission(fromParent, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: cannot modify " .. fromParent, 2)
		return
	end

	if not checkPermission(toParent, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: cannot modify " .. toParent, 2)
		return
	end

	cepheus.perms._metaCache[fromParent] = nil
	cepheus.perms._metaCache[toParent] = nil

	return _originalFs.move(fromPath, toPath)
end

function _wrappedFs.copy(fromPath, toPath)
	if not checkPathTraversal(fromPath) then
		error("Permission denied: cannot access source parent directory", 2)
		return
	end

	if not checkPathTraversal(toPath) then
		error("Permission denied: cannot access destination parent directory", 2)
		return
	end

	if not checkPermission(fromPath, cepheus.perms.PERMS.READ) then
		error("Permission denied: " .. fromPath, 2)
		return
	end

	local toParent = _originalFs.getDir(toPath)
	if toParent == "" then
		toParent = "/"
	end
	if not checkPermission(toParent, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: cannot modify " .. toParent, 2)
		return
	end

	cepheus.perms._metaCache[toParent] = nil

	return _originalFs.copy(fromPath, toPath)
end

function _wrappedFs.makeDir(path)
	local parent = _originalFs.getDir(path)
	if parent == "" then
		parent = "/"
	end

	if not checkPathTraversal(parent) then
		error("Permission denied: cannot access parent directory", 2)
		return
	end

	if not checkPermission(parent, cepheus.perms.PERMS.WRITE) then
		error("Permission denied: cannot modify " .. parent, 2)
		return
	end

	local result = _originalFs.makeDir(path)

	local currentUser = cepheus.users.getCurrentUser()
	updateMeta(path, currentUser and currentUser.uid or 0, 0, 0x1ED, 0)

	cepheus.perms._metaCache[parent] = nil

	return result
end

function _wrappedFs.list(path)
	if not checkPathTraversal(path) then
		error("Permission denied: cannot access parent directory", 2)
		return
	end

	if not checkPermission(path, cepheus.perms.PERMS.READ) or not checkPermission(path, cepheus.perms.PERMS.EXEC) then
		error("Permission denied: " .. path, 2)
		return
	end

	local items = _originalFs.list(path)

	local filtered = {}
	for _, item in ipairs(items) do
		if item ~= ".meta" then
			table.insert(filtered, item)
		end
	end

	return filtered
end

function _wrappedFs.exists(path)
	path = _originalFs.combine(path)
	if not checkPathTraversal(path) then
		return false
	end

	if path == "/" or path == "" then
		return _originalFs.exists(path)
	end

	local parent = _originalFs.getDir(path)
	if parent == "" then
		parent = "/"
	end
	if parent ~= "/" then
		if not checkPermission(parent, cepheus.perms.PERMS.EXEC) then
			return false
		end
	end

	if _originalFs.exists(path) and _originalFs.isDir(path) then
		if not checkPermission(path, cepheus.perms.PERMS.EXEC) then
			return false
		end
	end

	return _originalFs.exists(path)
end

function _wrappedFs.isDir(path)
	path = _originalFs.combine(path)
	if not checkPathTraversal(path) then
		return false
	end

	if path == "/" or path == "" then
		return _originalFs.isDir(path)
	end

	local parent = _originalFs.getDir(path)
	if parent == "" then
		parent = "/"
	end
	if parent ~= "/" then
		if not checkPermission(parent, cepheus.perms.PERMS.EXEC) then
			return false
		end
	end

	if not _originalFs.exists(path) then
		return false
	end

	local isDir = _originalFs.isDir(path)
	if isDir and not checkPermission(path, cepheus.perms.PERMS.EXEC) then
		return false
	end

	return isDir
end

function _wrappedFs.getSize(path)
	if not checkPathTraversal(path) then
		error("Permission denied: cannot access parent directory", 2)
		return
	end

	if not checkPermission(path, cepheus.perms.PERMS.READ) then
		error("Permission denied: " .. path, 2)
		return
	end

	return _originalFs.getSize(path)
end

function _wrappedFs.getDrive(path)
	if not checkPathTraversal(path) then
		return nil
	end

	return _originalFs.getDrive(path)
end

function _wrappedFs.isReadOnly(path)
	if not checkPathTraversal(path) then
		return true
	end

	return _originalFs.isReadOnly(path)
end

function _wrappedFs.getCapacity(path)
	if not checkPathTraversal(path) then
		return nil
	end

	return _originalFs.getCapacity(path)
end

function _wrappedFs.getFreeSpace(path)
	if not checkPathTraversal(path) then
		return 0
	end

	return _originalFs.getFreeSpace(path)
end

function _wrappedFs.attributes(path)
	if not checkPathTraversal(path) then
		error("Permission denied: cannot access parent directory", 2)
		return
	end

	if not checkPermission(path, cepheus.perms.PERMS.READ) then
		error("Permission denied: " .. path, 2)
		return
	end

	return _originalFs.attributes and _originalFs.attributes(path)
end

function _wrappedFs.getAttributes(path)
	if not checkPathTraversal(path) then
		error("Permission denied: cannot access parent directory", 2)
		return
	end

	if not checkPermission(path, cepheus.perms.PERMS.READ) then
		error("Permission denied: " .. path, 2)
		return
	end

	return _originalFs.getAttributes and _originalFs.getAttributes(path)
end

function _wrappedFs.find(wildcard)
	local results = _originalFs.find(wildcard)
	local filtered = {}

	for _, path in ipairs(results) do
		if checkPathTraversal(path) then
			local parent = _originalFs.getDir(path)
			if parent == "" or parent == "/" or checkPermission(parent, cepheus.perms.PERMS.EXEC) then
				table.insert(filtered, path)
			end
		end
	end

	return filtered
end

_G.fs = _wrappedFs

cepheus.perms._originalFs = _originalFs
cepheus.sched = {}

cepheus.sched.STATE = {
	READY = "ready",
	RUNNING = "running",
	BLOCKED = "blocked",
	PAUSED = "paused",
	DEAD = "dead",
}

cepheus.sched.SIGNAL = {
	TERM = "SIGTERM",
	KILL = "SIGKILL",
	INT = "SIGINT",
	USR1 = "SIGUSR1",
	USR2 = "SIGUSR2",
}

cepheus.sched.MODE = {
	ROUND_ROBIN = "rr",
	PRIORITY = "priority",
	FAIR = "fair",
}

cepheus.sched._tasks = {}
cepheus.sched._nextPid = 1
cepheus.sched._currentPid = 0
cepheus.sched._schedulerMode = cepheus.sched.MODE.ROUND_ROBIN
cepheus.sched._worldFrozen = false
cepheus.sched._criticalSection = 0
cepheus.sched._events = {}
cepheus.sched._deferredQueue = {}

cepheus.sched._resources = {}
cepheus.sched._mutexes = {}
cepheus.sched._semaphores = {}
cepheus.sched._conditions = {}
cepheus.sched._nextResourceId = 1

--- Get current task's PID
-- @return number Current PID
function cepheus.sched.current_pid()
	return cepheus.sched._currentPid
end

--- Spawn a new task
-- @param func Function to run
-- @param ... Arguments to pass to function
-- @return number PID of new task
function cepheus.sched.spawn(func, ...)
	expect(1, func, "function")

	local pid = cepheus.sched._nextPid
	cepheus.sched._nextPid = cepheus.sched._nextPid + 1

	local args = { ... }

	local parentTask = cepheus.sched._tasks[cepheus.sched._currentPid]
	local stdin = parentTask and parentTask.stdin or nil
	local stdout = parentTask and parentTask.stdout or nil
	local stderr = parentTask and parentTask.stderr or nil

	cepheus.sched._tasks[pid] = {
		pid = pid,
		state = cepheus.sched.STATE.READY,
		priority = 0,
		coroutine = coroutine.create(func),
		args = args,
		parent = cepheus.sched._currentPid,
		children = {},
		owner = cepheus.users.getCurrentUser() and cepheus.users.getCurrentUser().uid or 0,
		gid = cepheus.users.getCurrentUser() and cepheus.users.getCurrentUser().gid or 0,
		euid = cepheus.users.getCurrentUser() and cepheus.users.getCurrentUser().uid or 0,
		egid = cepheus.users.getCurrentUser() and cepheus.users.getCurrentUser().gid or 0,
		mailbox = {},
		mailboxLimit = 100,
		signals = {},
		signalMask = {},
		signalHandlers = {},
		resources = {},
		cpuTime = 0,
		memory = 0,
		exitCode = nil,
		blockReason = nil,
		eventFilter = nil,
		hasStarted = false,
		stdin = stdin,
		stdout = stdout,
		stderr = stderr,
	}

	if cepheus.sched._currentPid ~= 0 and cepheus.sched._tasks[cepheus.sched._currentPid] then
		table.insert(cepheus.sched._tasks[cepheus.sched._currentPid].children, pid)
	end

	return pid
end

--- Spawn a task from a file
-- @param path Path to file
-- @param ... Arguments
-- @return number PID
function cepheus.sched.spawnF(path, ...)
	expect(1, path, "string")

	if not checkPermission(path, cepheus.perms.PERMS.EXEC) then
		error("Permission denied: cannot execute " .. path)
		return
	end

	local func, err = loadfile(path)
	if not func then
		error("Failed to load file: " .. err)
		return
	end

	local pid = cepheus.sched.spawn(func, ...)
	local task = cepheus.sched._tasks[pid]

	local stat = cepheus.perms.stat(path)
	if stat then
		if stat.hasSetuid then
			task.euid = stat.uid

			local oldEnv = getfenv(func)
			local newEnv = setmetatable({}, { __index = oldEnv })

			newEnv.setuid = function(newUid)
				expect(1, newUid, "number")
				local currentTask = cepheus.sched._tasks[cepheus.sched.current_pid()]
				if currentTask then
					if currentTask.euid == 0 or newUid == currentTask.owner then
						currentTask.euid = newUid
						return true
					end
					error("Permission denied: cannot setuid")
					return
				end
				return false
			end

			newEnv.getuid = function()
				local currentTask = cepheus.sched._tasks[cepheus.sched.current_pid()]
				return currentTask and currentTask.owner or 0
			end

			newEnv.geteuid = function()
				local currentTask = cepheus.sched._tasks[cepheus.sched.current_pid()]
				return currentTask and currentTask.euid or 0
			end

			setfenv(func, newEnv)
		end

		if stat.hasSetgid then
			task.egid = stat.gid

			local oldEnv = getfenv(func)
			local newEnv = setmetatable({}, { __index = oldEnv })

			newEnv.setgid = function(newGid)
				expect(1, newGid, "number")
				local currentTask = cepheus.sched._tasks[cepheus.sched.current_pid()]
				if currentTask then
					if currentTask.euid == 0 or newGid == currentTask.gid then
						currentTask.egid = newGid
						return true
					end
					error("Permission denied: cannot setgid")
					return
				end
				return false
			end

			newEnv.getgid = function()
				local currentTask = cepheus.sched._tasks[cepheus.sched.current_pid()]
				return currentTask and currentTask.gid or 0
			end

			newEnv.getegid = function()
				local currentTask = cepheus.sched._tasks[cepheus.sched.current_pid()]
				return currentTask and currentTask.egid or 0
			end

			setfenv(func, newEnv)
		end
	end

	return pid
end

--- Spawn a task as a specific user (requires root)
-- @param path Path to file to execute
-- @param uid User ID to run as
-- @param gid Group ID to run as
-- @param ... Arguments to pass to the program
-- @return number PID of spawned task
function cepheus.sched.spawnAsUser(path, uid, gid, ...)
	expect(1, path, "string")
	expect(2, uid, "number")
	expect(3, gid, "number")

	local currentPid = cepheus.sched.current_pid()
	local hasRootPriv = false

	if currentPid > 0 and cepheus.sched._tasks[currentPid] then
		local task = cepheus.sched._tasks[currentPid]
		hasRootPriv = (task.euid == 0) or (task.owner == 0)
	else
		hasRootPriv = cepheus.users.isRoot()
	end

	if not hasRootPriv then
		error("Permission denied: only root can spawn tasks as other users")
		return
	end

	if not checkPermission(path, cepheus.perms.PERMS.EXEC) then
		error("Permission denied: cannot execute " .. path)
		return
	end

	local func, err = loadfile(path)
	if not func then
		error("Failed to load file: " .. err)
		return
	end

	local args = { ... }
	local pid = cepheus.sched.spawn(func, table.unpack(args))
	local task = cepheus.sched._tasks[pid]

	task.owner = uid
	task.euid = uid
	task.gid = gid
	task.egid = gid

	return pid
end

--- Exit current task
-- @param code Exit code
function cepheus.sched.exit(code)
	expect(1, code, "number", "nil")

	local pid = cepheus.sched.current_pid()
	if pid == 0 then
		error("Cannot exit kernel task")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if task then
		task.state = cepheus.sched.STATE.DEAD
		task.exitCode = code or 0

		for _, resourceId in ipairs(task.resources) do
			local resource = cepheus.sched._resources[resourceId]
			if resource and resource.cleanup then
				pcall(resource.cleanup, resource.object)
			end
			cepheus.sched._resources[resourceId] = nil
		end
	end

	coroutine.yield()
end

--- Kill a task
-- @param pid PID to kill
-- @param signal Signal to send (default: SIGKILL)
function cepheus.sched.kill(pid, signal)
	expect(1, pid, "number")
	expect(2, signal, "string", "nil")

	if not cepheus.users.hasCap(cepheus.users.CAPS.KILL) then
		error("Permission denied: requires KILL capability")
		return
	end

	signal = signal or cepheus.sched.SIGNAL.KILL

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	if signal == cepheus.sched.SIGNAL.KILL then
		task.state = cepheus.sched.STATE.DEAD
		task.exitCode = -1
	else
		cepheus.sched.signal(pid, signal)
	end
end

--- Wait for a task to complete
-- @param pid PID to wait for
-- @return number Exit code
function cepheus.sched.wait(pid)
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. tostring(pid))
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	if task.state ~= cepheus.sched.STATE.DEAD then
		cepheus.sched.block("wait:" .. pid)
	end

	local exitCode = task.exitCode
	cepheus.sched._tasks[pid] = nil
	return exitCode
end

--- Detach a task (prevents waiting)
-- @param pid PID to detach
function cepheus.sched.detach(pid)
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.detached = true
end

--- Replace current task with a new function
-- @param func Function to execute
-- @param ... Arguments
function cepheus.sched.exec(func, ...)
	expect(1, func, "function")

	local pid = cepheus.sched.current_pid()
	if pid == 0 then
		error("Cannot exec kernel task")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if task then
		task.coroutine = coroutine.create(func)
		task.args = { ... }
		task.state = cepheus.sched.STATE.READY
	end

	coroutine.yield()
end

--- Replace current task with a file
-- @param path Path to file
-- @param ... Arguments
function cepheus.sched.execF(path, ...)
	expect(1, path, "string")

	if not checkPermission(path, cepheus.perms.PERMS.EXEC) then
		error("Permission denied: cannot execute " .. path)
		return
	end

	local func, err = loadfile(path, "bt", _G)
	if not func then
		error("Failed to load file: " .. err)
		return
	end

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	local stat = cepheus.perms.stat(path)
	if stat and task then
		if stat.hasSetuid then
			task.euid = stat.uid
		end
		if stat.hasSetgid then
			task.egid = stat.gid
		end
	end

	cepheus.sched.exec(func, ...)
end

--- Yield to scheduler
function cepheus.sched.yield()
	coroutine.yield()
end

--- Sleep for milliseconds
-- @param ms Milliseconds to sleep
function cepheus.sched.sleep(ms)
	expect(1, ms, "number")

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if task then
		task.wakeTime = os.epoch("utc") + ms
		task.state = cepheus.sched.STATE.BLOCKED
		task.blockReason = "sleep"
	end

	cepheus.sched.yield()
end

--- Set task priority
-- @param pid PID
-- @param prio Priority (higher = more CPU time)
function cepheus.sched.set_priority(pid, prio)
	expect(1, pid, "number")
	expect(2, prio, "number")

	if not cepheus.users.hasCap(cepheus.users.CAPS.SET_PRIORITY) then
		error("Permission denied: requires SET_PRIORITY capability")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.priority = prio
end

--- Get task priority
-- @param pid PID
-- @return number Priority
function cepheus.sched.get_priority(pid)
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	return task.priority
end

--- Set stdin for a task
-- @param pid PID (or nil for current task)
-- @param stream Stream object with read/readLine/readAll methods
function cepheus.sched.set_stdin(pid, stream)
	pid = pid or cepheus.sched.current_pid()
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.stdin = stream
end

--- Set stdout for a task
-- @param pid PID (or nil for current task)
-- @param stream Stream object with write/writeLine methods
function cepheus.sched.set_stdout(pid, stream)
	pid = pid or cepheus.sched.current_pid()
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.stdout = stream
end

--- Set stderr for a task
-- @param pid PID (or nil for current task)
-- @param stream Stream object with write/writeLine methods
function cepheus.sched.set_stderr(pid, stream)
	pid = pid or cepheus.sched.current_pid()
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.stderr = stream
end

--- Get stdin for a task
-- @param pid PID (or nil for current task)
-- @return Stream object or nil
function cepheus.sched.get_stdin(pid)
	pid = pid or cepheus.sched.current_pid()
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		return nil
	end

	return task.stdin
end

--- Get stdout for a task
-- @param pid PID (or nil for current task)
-- @return Stream object or nil
function cepheus.sched.get_stdout(pid)
	pid = pid or cepheus.sched.current_pid()
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		return nil
	end

	return task.stdout
end

--- Get stderr for a task
-- @param pid PID (or nil for current task)
-- @return Stream object or nil
function cepheus.sched.get_stderr(pid)
	pid = pid or cepheus.sched.current_pid()
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		return nil
	end

	return task.stderr
end

--- Pause a task
-- @param pid PID to pause
function cepheus.sched.pause(pid)
	expect(1, pid, "number")

	if not cepheus.users.hasCap(cepheus.users.CAPS.SIGNAL) then
		error("Permission denied: requires SIGNAL capability")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.state = cepheus.sched.STATE.PAUSED
end

--- Resume a paused task
-- @param pid PID to resume
function cepheus.sched.resume(pid)
	expect(1, pid, "number")

	if not cepheus.users.hasCap(cepheus.users.CAPS.SIGNAL) then
		error("Permission denied: requires SIGNAL capability")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	if task.state == cepheus.sched.STATE.PAUSED then
		task.state = cepheus.sched.STATE.READY
	end
end

--- Block current task
-- @param reason Block reason
function cepheus.sched.block(reason)
	expect(1, reason, "string", "nil")

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if task then
		task.state = cepheus.sched.STATE.BLOCKED
		task.blockReason = reason or "unknown"
		task.eventFilter = nil
	end

	cepheus.sched.yield()
end

--- Wake a blocked task
-- @param pid PID to wake
function cepheus.sched.wake(pid)
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if task.state == cepheus.sched.STATE.BLOCKED then
		task.state = cepheus.sched.STATE.READY
		task.blockReason = nil
		task.wakeTime = nil
	end
end

--- Wake all tasks blocked on a reason
-- @param reason Block reason
function cepheus.sched.wake_all(reason)
	expect(1, reason, "string")

	for pid, task in pairs(cepheus.sched._tasks) do
		if task.state == cepheus.sched.STATE.BLOCKED and task.blockReason == reason then
			task.state = cepheus.sched.STATE.READY
			task.blockReason = nil
		end
	end
end

--- Wait for an event
-- @param event Event name
function cepheus.sched.wait_event(event)
	expect(1, event, "string")

	local pid = cepheus.sched.current_pid()

	if not cepheus.sched._events[event] then
		cepheus.sched._events[event] = {}
	end

	table.insert(cepheus.sched._events[event], pid)
	cepheus.sched.block("event:" .. event)
end

--- Signal an event
-- @param event Event name
function cepheus.sched.signal_event(event)
	expect(1, event, "string")

	if cepheus.sched._events[event] then
		for _, pid in ipairs(cepheus.sched._events[event]) do
			cepheus.sched.wake(pid)
		end
		cepheus.sched._events[event] = nil
	end
end

--- Send a message to a task
-- @param pid Target PID
-- @param message Message to send
function cepheus.sched.send(pid, message)
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if #task.mailbox >= task.mailboxLimit then
		error("Mailbox full")
		return
	end

	table.insert(task.mailbox, {
		sender = cepheus.sched.current_pid(),
		message = message,
	})

	if task.state == cepheus.sched.STATE.BLOCKED and task.blockReason == "recv" then
		cepheus.sched.wake(pid)
	end
end

--- Receive a message (blocking)
-- @param timeout Optional timeout in ms
-- @return number, any Sender PID and message
function cepheus.sched.recv(timeout)
	expect(1, timeout, "number", "nil")

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if not task then
		error("No such task")
		return
	end

	local startTime = timeout and (os.epoch("utc")) or nil

	while #task.mailbox == 0 do
		if timeout then
			local elapsed = (os.epoch("utc")) - startTime
			if elapsed >= timeout then
				return nil, nil
			end
		end

		cepheus.sched.block("recv")
	end

	local msg = table.remove(task.mailbox, 1)
	return msg.sender, msg.message
end

--- Poll for a message (non-blocking)
-- @return number, any Sender PID and message, or nil
function cepheus.sched.poll()
	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if not task or #task.mailbox == 0 then
		return nil, nil
	end

	local msg = table.remove(task.mailbox, 1)
	return msg.sender, msg.message
end

--- Broadcast message to a group
-- @param group Group identifier
-- @param message Message to send
function cepheus.sched.broadcast(group, message)
	expect(1, group, "string")

	if not cepheus.users.hasCap(cepheus.users.CAPS.BROADCAST) then
		error("Permission denied: requires BROADCAST capability")
		return
	end

	for pid, task in pairs(cepheus.sched._tasks) do
		if task.groups and task.groups[group] then
			pcall(cepheus.sched.send, pid, message)
		end
	end
end

--- Set mailbox limit for a task
-- @param pid PID
-- @param n Limit
function cepheus.sched.set_mailbox_limit(pid, n)
	expect(1, pid, "number")
	expect(2, n, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	task.mailboxLimit = n
end

--- Send a signal to a task
-- @param pid Target PID
-- @param sig Signal name
function cepheus.sched.signal(pid, sig)
	expect(1, pid, "number")
	expect(2, sig, "string")

	if not cepheus.users.hasCap(cepheus.users.CAPS.SIGNAL) then
		error("Permission denied: requires SIGNAL capability")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	if not cepheus.users.isRoot() and task.owner ~= cepheus.users.getCurrentUser().uid then
		error("Permission denied: not task owner")
		return
	end

	if not task.signalMask[sig] then
		table.insert(task.signals, sig)
	end
end

--- Register a signal handler
-- @param sig Signal name
-- @param handler Handler function
function cepheus.sched.on_signal(sig, handler)
	expect(1, sig, "string")
	expect(2, handler, "function", "nil")

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if task then
		task.signalHandlers[sig] = handler
	end
end

--- Mask a signal
-- @param sig Signal name
function cepheus.sched.mask_signal(sig)
	expect(1, sig, "string")

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if task then
		task.signalMask[sig] = true
	end
end

--- Unmask a signal
-- @param sig Signal name
function cepheus.sched.unmask_signal(sig)
	expect(1, sig, "string")

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if task then
		task.signalMask[sig] = nil
	end
end

--- Create a mutex
-- @return number Mutex ID
function cepheus.sched.mutex_create()
	local id = cepheus.sched._nextResourceId
	cepheus.sched._nextResourceId = cepheus.sched._nextResourceId + 1

	cepheus.sched._mutexes[id] = {
		locked = false,
		owner = nil,
		queue = {},
	}

	return id
end

--- Lock a mutex
-- @param m Mutex ID
function cepheus.sched.mutex_lock(m)
	expect(1, m, "number")

	local mutex = cepheus.sched._mutexes[m]
	if not mutex then
		error("Invalid mutex: " .. m)
		return
	end

	local pid = cepheus.sched.current_pid()

	while mutex.locked do
		table.insert(mutex.queue, pid)
		cepheus.sched.block("mutex:" .. m)
	end

	mutex.locked = true
	mutex.owner = pid
end

--- Unlock a mutex
-- @param m Mutex ID
function cepheus.sched.mutex_unlock(m)
	expect(1, m, "number")

	local mutex = cepheus.sched._mutexes[m]
	if not mutex then
		error("Invalid mutex: " .. m)
		return
	end

	local pid = cepheus.sched.current_pid()

	if mutex.owner ~= pid then
		error("Not mutex owner")
		return
	end

	mutex.locked = false
	mutex.owner = nil

	if #mutex.queue > 0 then
		local nextPid = table.remove(mutex.queue, 1)
		cepheus.sched.wake(nextPid)
	end
end

--- Create a semaphore
-- @param count Initial count
-- @return number Semaphore ID
function cepheus.sched.sem_create(count)
	expect(1, count, "number")

	local id = cepheus.sched._nextResourceId
	cepheus.sched._nextResourceId = cepheus.sched._nextResourceId + 1

	cepheus.sched._semaphores[id] = {
		count = count,
		queue = {},
	}

	return id
end

--- Wait on a semaphore
-- @param s Semaphore ID
function cepheus.sched.sem_wait(s)
	expect(1, s, "number")

	local sem = cepheus.sched._semaphores[s]
	if not sem then
		error("Invalid semaphore: " .. s)
		return
	end

	local pid = cepheus.sched.current_pid()

	while sem.count <= 0 do
		table.insert(sem.queue, pid)
		cepheus.sched.block("semaphore:" .. s)
	end

	sem.count = sem.count - 1
end

--- Post to a semaphore
-- @param s Semaphore ID
function cepheus.sched.sem_post(s)
	expect(1, s, "number")

	local sem = cepheus.sched._semaphores[s]
	if not sem then
		error("Invalid semaphore: " .. s)
		return
	end

	sem.count = sem.count + 1

	if #sem.queue > 0 then
		local nextPid = table.remove(sem.queue, 1)
		cepheus.sched.wake(nextPid)
	end
end

--- Create a condition variable
-- @return number Condition ID
function cepheus.sched.cond_create()
	local id = cepheus.sched._nextResourceId
	cepheus.sched._nextResourceId = cepheus.sched._nextResourceId + 1

	cepheus.sched._conditions[id] = {
		queue = {},
	}

	return id
end

--- Wait on a condition variable
-- @param cond Condition ID
-- @param mutex Mutex ID
function cepheus.sched.cond_wait(cond, mutex)
	expect(1, cond, "number")
	expect(2, mutex, "number")

	local cv = cepheus.sched._conditions[cond]
	if not cv then
		error("Invalid condition variable: " .. cond)
		return
	end

	local pid = cepheus.sched.current_pid()
	table.insert(cv.queue, pid)

	cepheus.sched.mutex_unlock(mutex)
	cepheus.sched.block("condition:" .. cond)
	cepheus.sched.mutex_lock(mutex)
end

--- Signal a condition variable
-- @param cond Condition ID
function cepheus.sched.cond_signal(cond)
	expect(1, cond, "number")

	local cv = cepheus.sched._conditions[cond]
	if not cv then
		error("Invalid condition variable: " .. cond)
		return
	end

	if #cv.queue > 0 then
		local nextPid = table.remove(cv.queue, 1)
		cepheus.sched.wake(nextPid)
	end
end

--- Broadcast to a condition variable
-- @param cond Condition ID
function cepheus.sched.cond_broadcast(cond)
	expect(1, cond, "number")

	local cv = cepheus.sched._conditions[cond]
	if not cv then
		error("Invalid condition variable: " .. cond)
		return
	end

	for _, pid in ipairs(cv.queue) do
		cepheus.sched.wake(pid)
	end
	cv.queue = {}
end

--- Register a resource with cleanup function
-- @param obj Resource object
-- @param cleanup_fn Cleanup function
-- @return number Resource ID
function cepheus.sched.register_resource(obj, cleanup_fn)
	expect(2, cleanup_fn, "function", "nil")

	local id = cepheus.sched._nextResourceId
	cepheus.sched._nextResourceId = cepheus.sched._nextResourceId + 1

	cepheus.sched._resources[id] = {
		object = obj,
		cleanup = cleanup_fn,
	}

	local pid = cepheus.sched.current_pid()
	local task = cepheus.sched._tasks[pid]

	if task then
		table.insert(task.resources, id)
	end

	return id
end

--- Release a resource
-- @param obj Resource object
function cepheus.sched.release_resource(obj)
	for id, resource in pairs(cepheus.sched._resources) do
		if resource.object == obj then
			if resource.cleanup then
				pcall(resource.cleanup, obj)
			end
			cepheus.sched._resources[id] = nil
			break
		end
	end
end

--- List all tasks
-- @return table Array of task info
function cepheus.sched.list_tasks()
	local tasks = {}

	for pid, task in pairs(cepheus.sched._tasks) do
		table.insert(tasks, {
			pid = pid,
			state = task.state,
			priority = task.priority,
			owner = task.owner,
			cpu = task.cpuTime,
			mem = task.memory,
			parent = task.parent,
		})
	end

	return tasks
end

--- Get task information
-- @param pid PID
-- @return table Task info
function cepheus.sched.task_info(pid)
	expect(1, pid, "number")

	local task = cepheus.sched._tasks[pid]
	if not task then
		return nil
	end

	return {
		pid = pid,
		state = task.state,
		priority = task.priority,
		owner = task.owner,
		parent = task.parent,
		children = task.children,
		cpuTime = task.cpuTime,
		memory = task.memory,
		mailboxSize = #task.mailbox,
		resources = #task.resources,
	}
end

--- Enable/disable tracing for a task
-- @param pid PID
-- @param enable Boolean
function cepheus.sched.trace(pid, enable)
	expect(1, pid, "number")
	expect(2, enable, "boolean")

	if not cepheus.users.hasCap(cepheus.users.CAPS.TRACE) then
		error("Permission denied: requires TRACE capability")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	task.trace = enable
end

--- Dump task state
-- @param pid PID
function cepheus.sched.dump_state(pid)
	expect(1, pid, "number")

	if not cepheus.users.hasCap(cepheus.users.CAPS.TRACE) then
		error("Permission denied: requires TRACE capability")
		return
	end

	local task = cepheus.sched._tasks[pid]
	if not task then
		error("No such task: " .. pid)
		return
	end

	print(string.format("Task %d:", pid))
	print(string.format("  State: %s", task.state))
	print(string.format("  Priority: %d", task.priority))
	print(string.format("  Owner: %d", task.owner))
	print(string.format("  CPU Time: %.2f", task.cpuTime))
	print(string.format("  Mailbox: %d/%d", #task.mailbox, task.mailboxLimit))
	print(string.format("  Resources: %d", #task.resources))
end

--- Set scheduler mode
-- @param mode Scheduler mode (rr, priority, fair)
function cepheus.sched.set_scheduler(mode)
	expect(1, mode, "string")

	if not cepheus.users.hasCap(cepheus.users.CAPS.SCHEDULER_CONTROL) then
		error("Permission denied: requires SCHEDULER_CONTROL capability")
		return
	end

	if
		mode ~= cepheus.sched.MODE.ROUND_ROBIN
		and mode ~= cepheus.sched.MODE.PRIORITY
		and mode ~= cepheus.sched.MODE.FAIR
	then
		error("Invalid scheduler mode: " .. mode)
		return
	end

	cepheus.sched._schedulerMode = mode
end

--- Freeze the world (stop all tasks)
function cepheus.sched.freeze_world()
	if not cepheus.users.hasCap(cepheus.users.CAPS.FREEZE_WORLD) then
		error("Permission denied: requires FREEZE_WORLD capability")
		return
	end

	cepheus.sched._worldFrozen = true
end

--- Thaw the world (resume all tasks)
function cepheus.sched.thaw_world()
	if not cepheus.users.hasCap(cepheus.users.CAPS.FREEZE_WORLD) then
		error("Permission denied: requires FREEZE_WORLD capability")
		return
	end

	cepheus.sched._worldFrozen = false
end

--- Enter critical section
function cepheus.sched.enter_critical()
	if not cepheus.users.hasCap(cepheus.users.CAPS.CRITICAL) then
		error("Permission denied: requires CRITICAL capability")
		return
	end

	cepheus.sched._criticalSection = cepheus.sched._criticalSection + 1
end

--- Leave critical section
function cepheus.sched.leave_critical()
	if not cepheus.users.hasCap(cepheus.users.CAPS.CRITICAL) then
		error("Permission denied: requires CRITICAL capability")
		return
	end

	if cepheus.sched._criticalSection > 0 then
		cepheus.sched._criticalSection = cepheus.sched._criticalSection - 1
	end
end

--- Defer a function to run after current time slice
-- @param func Function to defer
function cepheus.sched.defer(func)
	expect(1, func, "function")

	table.insert(cepheus.sched._deferredQueue, func)
end

local function sched_run()
	while true do
		::continue::

		while #cepheus.sched._deferredQueue > 0 do
			local func = table.remove(cepheus.sched._deferredQueue, 1)
			pcall(func)
		end

		if cepheus.sched._worldFrozen then
			coroutine.yield()
			goto continue
		end

		local now = os.epoch("utc")
		for pid, task in pairs(cepheus.sched._tasks) do
			if task.state == cepheus.sched.STATE.BLOCKED and task.wakeTime and now >= task.wakeTime then
				task.state = cepheus.sched.STATE.READY
				task.wakeTime = nil
				task.blockReason = nil
			end
		end

		local nextTask = nil

		if cepheus.sched._schedulerMode == cepheus.sched.MODE.ROUND_ROBIN then
			local pids = {}
			for pid, task in pairs(cepheus.sched._tasks) do
				if task.state == cepheus.sched.STATE.READY then
					table.insert(pids, pid)
				end
			end
			table.sort(pids)

			for _, pid in ipairs(pids) do
				if pid > cepheus.sched._currentPid then
					nextTask = cepheus.sched._tasks[pid]
					break
				end
			end

			if not nextTask and #pids > 0 then
				nextTask = cepheus.sched._tasks[pids[1]]
			end
		elseif cepheus.sched._schedulerMode == cepheus.sched.MODE.PRIORITY then
			local highestPrio = -math.huge
			for pid, task in pairs(cepheus.sched._tasks) do
				if task.state == cepheus.sched.STATE.READY and task.priority > highestPrio then
					highestPrio = task.priority
					nextTask = task
				end
			end
		elseif cepheus.sched._schedulerMode == cepheus.sched.MODE.FAIR then
			local leastCpu = math.huge
			for pid, task in pairs(cepheus.sched._tasks) do
				if task.state == cepheus.sched.STATE.READY and task.cpuTime < leastCpu then
					leastCpu = task.cpuTime
					nextTask = task
				end
			end
		end

		if nextTask then
			cepheus.sched._currentPid = nextTask.pid
			nextTask.state = cepheus.sched.STATE.RUNNING

			local startTime = os.epoch("utc")

			while #nextTask.signals > 0 do
				local sig = table.remove(nextTask.signals, 1)
				local handler = nextTask.signalHandlers[sig]

				if handler then
					pcall(handler, sig)
				end
			end

			local success, result
			if coroutine.status(nextTask.coroutine) == "suspended" then
				success, result = coroutine.resume(nextTask.coroutine, table.unpack(nextTask.args))
				nextTask.hasStarted = true

				nextTask.args = {}

				if success and coroutine.status(nextTask.coroutine) == "suspended" then
					nextTask.eventFilter = result
				else
					nextTask.eventFilter = nil
				end
			end

			local endTime = os.epoch("utc")
			nextTask.cpuTime = nextTask.cpuTime + (endTime - startTime)

			if not success then
				printLog("ERROR", string.format("Task %d crashed: %s", nextTask.pid, tostring(result)))
				nextTask.state = cepheus.sched.STATE.DEAD
				nextTask.exitCode = -1

				if nextTask.parent and cepheus.sched._tasks[nextTask.parent] then
					local parent = cepheus.sched._tasks[nextTask.parent]
					if
						parent.state == cepheus.sched.STATE.BLOCKED
						and parent.blockReason == "wait:" .. nextTask.pid
					then
						parent.state = cepheus.sched.STATE.READY
						parent.blockReason = nil
						parent.justWoken = true
					end
				end
			elseif coroutine.status(nextTask.coroutine) == "dead" then
				nextTask.state = cepheus.sched.STATE.DEAD
				nextTask.exitCode = nextTask.exitCode or 0

				if nextTask.parent and cepheus.sched._tasks[nextTask.parent] then
					local parent = cepheus.sched._tasks[nextTask.parent]
					if
						parent.state == cepheus.sched.STATE.BLOCKED
						and parent.blockReason == "wait:" .. nextTask.pid
					then
						parent.state = cepheus.sched.STATE.READY
						parent.blockReason = nil
						parent.justWoken = true
					end
				end
			else
				if nextTask.state == cepheus.sched.STATE.RUNNING then
					nextTask.state = cepheus.sched.STATE.READY
				end
			end
		end

		local anyJustWoken = false
		for pid, task in pairs(cepheus.sched._tasks) do
			if task.justWoken then
				anyJustWoken = true
				task.justWoken = false
			end
		end

		if anyJustWoken then
			goto continue
		end

		local event = { coroutine.yield() }
		local eventType = event[1]

		for pid, task in pairs(cepheus.sched._tasks) do
			if task.state == cepheus.sched.STATE.READY and task.hasStarted then
				if task.eventFilter == nil or task.eventFilter == eventType then
					task.args = event
				end
			end
		end
	end
end

cepheus.users.init()

local function initMeta()
	local systemDirs = {
		"/",
		"/System",
		"/System/Applications",
		"/System/Libraries",
		"/System/Config",
		"/System/Logs",
		"/System/Resources",
		"/System/Drivers",
		"/sbin",
		"/home",
		"/Applications",
		"/Programs",
	}

	for _, dir in ipairs(systemDirs) do
		if _originalFs.exists(dir) and _originalFs.isDir(dir) then
			local metaPath = _originalFs.combine(dir, ".meta")
			if not _originalFs.exists(metaPath) then
				getDirectoryMeta(dir)
			end
		end
	end
end

initMeta()

local _, postCount = KextLoader.loadExtensions("System/Libraries/Extensions", true, true)

_G.error = function(msg)
	printLog("ERROR", msg)
end
_ENV.error = _G.error

cepheus.sched.spawnF("/sbin/launchd.lua")
sched_run()
