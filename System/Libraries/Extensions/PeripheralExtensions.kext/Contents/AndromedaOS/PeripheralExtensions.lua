local expect = cepheus.expect

local native = peripheral
local sides = rs.getSides()

local peripheralCache = {}
local cacheTimeout = 1
local lastCacheUpdate = 0

local function clearCache()
	peripheralCache = {}
	lastCacheUpdate = os.clock()
end

local function updateCacheIfNeeded()
	local currentTime = os.clock()
	if currentTime - lastCacheUpdate > cacheTimeout then
		clearCache()
	end
end

local function safeNativeCall(func, ...)
	local success, result = pcall(func, ...)
	if not success then
		return false, result
	end
	return true, result
end

local function getRemotePeripherals(side)
	if not native.hasType(side, "peripheral_hub") then
		return {}
	end

	local success, remote = safeNativeCall(native.call, side, "getNamesRemote")
	if not success or type(remote) ~= "table" then
		return {}
	end

	return remote
end

local function getNames()
	updateCacheIfNeeded()

	if peripheralCache.names then
		return peripheralCache.names
	end

	local results = {}
	local seen = {}

	for n = 1, #sides do
		local side = sides[n]
		if native.isPresent(side) then
			if not seen[side] then
				table.insert(results, side)
				seen[side] = true
			end

			local remote = getRemotePeripherals(side)
			for _, name in ipairs(remote) do
				if not seen[name] then
					table.insert(results, name)
					seen[name] = true
				end
			end
		end
	end

	peripheralCache.names = results
	return results
end

local function isPresent(name)
	expect(1, name, "string")

	if native.isPresent(name) then
		return true
	end

	for n = 1, #sides do
		local side = sides[n]
		if native.hasType(side, "peripheral_hub") then
			local success, present = safeNativeCall(native.call, side, "isPresentRemote", name)
			if success and present then
				return true
			end
		end
	end

	return false
end

local function getType(peripheral)
	expect(1, peripheral, "string", "table")

	if type(peripheral) == "string" then
		if native.isPresent(peripheral) then
			return native.getType(peripheral)
		end

		for n = 1, #sides do
			local side = sides[n]
			if native.hasType(side, "peripheral_hub") then
				local success, present = safeNativeCall(native.call, side, "isPresentRemote", peripheral)
				if success and present then
					local typeSuccess, pType = safeNativeCall(native.call, side, "getTypeRemote", peripheral)
					if typeSuccess then
						return pType
					end
				end
			end
		end

		return nil
	else
		local mt = getmetatable(peripheral)
		if not mt or mt.__name ~= "peripheral" or type(mt.types) ~= "table" then
			error("bad argument #1 (table is not a peripheral)", 2)
		end
		return table.unpack(mt.types)
	end
end

local function hasType(peripheral, peripheral_type)
	expect(1, peripheral, "string", "table")
	expect(2, peripheral_type, "string")

	if type(peripheral) == "string" then
		if native.isPresent(peripheral) then
			return native.hasType(peripheral, peripheral_type)
		end

		for n = 1, #sides do
			local side = sides[n]
			if native.hasType(side, "peripheral_hub") then
				local success, present = safeNativeCall(native.call, side, "isPresentRemote", peripheral)
				if success and present then
					local typeSuccess, hasType =
						safeNativeCall(native.call, side, "hasTypeRemote", peripheral, peripheral_type)
					if typeSuccess then
						return hasType
					end
				end
			end
		end

		return nil
	else
		local mt = getmetatable(peripheral)
		if not mt or mt.__name ~= "peripheral" or type(mt.types) ~= "table" then
			error("bad argument #1 (table is not a peripheral)", 2)
		end
		return mt.types[peripheral_type] ~= nil
	end
end

local function getMethods(name)
	expect(1, name, "string")

	if native.isPresent(name) then
		local success, methods = safeNativeCall(native.getMethods, name)
		if success then
			return methods
		end
	end

	for n = 1, #sides do
		local side = sides[n]
		if native.hasType(side, "peripheral_hub") then
			local success, present = safeNativeCall(native.call, side, "isPresentRemote", name)
			if success and present then
				local methodSuccess, methods = safeNativeCall(native.call, side, "getMethodsRemote", name)
				if methodSuccess then
					return methods
				end
			end
		end
	end

	return nil
end

local function getName(peripheral)
	expect(1, peripheral, "table")

	local mt = getmetatable(peripheral)
	if not mt or mt.__name ~= "peripheral" or type(mt.name) ~= "string" then
		error("bad argument #1 (table is not a peripheral)", 2)
	end

	return mt.name
end

local function call(name, method, ...)
	expect(1, name, "string")
	expect(2, method, "string")

	if native.isPresent(name) then
		local success, result = safeNativeCall(native.call, name, method, ...)
		if success then
			return result
		else
			error("Error calling " .. method .. " on " .. name .. ": " .. tostring(result), 2)
		end
	end

	for n = 1, #sides do
		local side = sides[n]
		if native.hasType(side, "peripheral_hub") then
			local success, present = safeNativeCall(native.call, side, "isPresentRemote", name)
			if success and present then
				local callSuccess, result = safeNativeCall(native.call, side, "callRemote", name, method, ...)
				if callSuccess then
					return result
				else
					error("Error calling " .. method .. " on " .. name .. ": " .. tostring(result), 2)
				end
			end
		end
	end

	error("No peripheral named " .. name, 2)
end

local function wrap(name)
	expect(1, name, "string")

	if not isPresent(name) then
		return nil
	end

	local methods = getMethods(name)
	if not methods then
		return nil
	end

	local types = { getType(name) }

	local typeLookup = {}
	for i = 1, #types do
		typeLookup[types[i]] = true
	end

	local result = setmetatable({}, {
		__name = "peripheral",
		name = name,
		type = types[1],
		types = typeLookup,
		__index = function(t, key)
			error("No such method " .. tostring(key) .. " on peripheral " .. name, 2)
		end,
	})

	for _, method in ipairs(methods) do
		result[method] = function(...)
			return call(name, method, ...)
		end
	end

	return result
end

local function find(ty, filter)
	expect(1, ty, "string")
	expect(2, filter, "function", "nil")

	local results = {}

	for _, name in ipairs(getNames()) do
		if hasType(name, ty) then
			local wrapped = wrap(name)
			if wrapped then
				if filter == nil or filter(name, wrapped) then
					table.insert(results, wrapped)
				end
			end
		end
	end

	return table.unpack(results)
end

local function refreshCache()
	clearCache()
end

local function getInfo(name)
	expect(1, name, "string")

	if not isPresent(name) then
		return nil
	end

	local types = { getType(name) }
	local methods = getMethods(name)

	return {
		name = name,
		types = types,
		methods = methods,
		isDirect = native.isPresent(name),
		isRemote = not native.isPresent(name),
	}
end

return {
	_LIST_NAME = "cepheus.peripherals",

	getNames = getNames,
	isPresent = isPresent,
	getType = getType,
	hasType = hasType,
	getMethods = getMethods,
	getName = getName,
	call = call,
	wrap = wrap,
	find = find,
	refreshCache = refreshCache,
	getInfo = getInfo,
}
