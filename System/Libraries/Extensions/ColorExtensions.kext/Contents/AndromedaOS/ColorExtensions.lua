local MIN_COLOR = 0x1
local MAX_COLOR = 0x8000
local MAX_COMBINED = 0xFFFF

local colorToHex = {}
local hexToColor = {}
local colorToName = {}
local nameToColor = {}

local colorNames = {
	"white",
	"orange",
	"magenta",
	"lightBlue",
	"yellow",
	"lime",
	"pink",
	"gray",
	"lightGray",
	"cyan",
	"purple",
	"blue",
	"brown",
	"green",
	"red",
	"black",
}

for i = 0, 15 do
	local color = 2 ^ i
	local hex = string.format("%x", i)

	colorToHex[color] = hex
	hexToColor[hex] = color

	if colorNames[i + 1] then
		colorToName[color] = colorNames[i + 1]
		nameToColor[colorNames[i + 1]] = color
	end
end

local function validateRGBComponent(value, component, paramIndex)
	cepheus.expect(paramIndex, value, "number")

	if value < 0 or value > 1 then
		error(
			string.format("bad argument #%d (%s out of range, expected 0-1, got %.2f)", paramIndex, component, value),
			3
		)
	end

	return value
end

local function combine(...)
	local result = 0
	local argCount = select("#", ...)

	if argCount == 0 then
		return 0
	end

	for i = 1, argCount do
		local color = select(i, ...)
		cepheus.expect(i, color, "number")

		if color < 0 or color > MAX_COMBINED then
			error(string.format("bad argument #%d (color out of range)", i), 2)
		end

		result = bit32.bor(result, color)
	end

	return result
end

local function subtract(colors, ...)
	cepheus.expect(1, colors, "number")

	if colors < 0 or colors > MAX_COMBINED then
		error("bad argument #1 (color out of range)", 2)
	end

	local result = colors
	local argCount = select("#", ...)

	for i = 1, argCount do
		local color = select(i, ...)
		cepheus.expect(i + 1, color, "number")

		if color < 0 or color > MAX_COMBINED then
			error(string.format("bad argument #%d (color out of range)", i + 1), 2)
		end

		result = bit32.band(result, bit32.bnot(color))
	end

	return result
end

local function test(colors, color)
	cepheus.expect(1, colors, "number")
	cepheus.expect(2, color, "number")

	if colors < 0 or colors > MAX_COMBINED then
		error("bad argument #1 (color out of range)", 2)
	end

	if color < 0 or color > MAX_COMBINED then
		error("bad argument #2 (color out of range)", 2)
	end

	return bit32.band(colors, color) == color
end

local function packRGB(r, g, b)
	r = validateRGBComponent(r, "red", 1)
	g = validateRGBComponent(g, "green", 2)
	b = validateRGBComponent(b, "blue", 3)

	local rByte = bit32.band(r * 255 + 0.5, 0xFF)
	local gByte = bit32.band(g * 255 + 0.5, 0xFF)
	local bByte = bit32.band(b * 255 + 0.5, 0xFF)

	return bit32.lshift(rByte, 16) + bit32.lshift(gByte, 8) + bByte
end

local function unpackRGB(rgb)
	cepheus.expect(1, rgb, "number")

	if rgb < 0 or rgb > 0xFFFFFF then
		error("bad argument #1 (RGB value out of range, expected 0x000000-0xFFFFFF)", 2)
	end

	local r = bit32.band(bit32.rshift(rgb, 16), 0xFF) / 255
	local g = bit32.band(bit32.rshift(rgb, 8), 0xFF) / 255
	local b = bit32.band(rgb, 0xFF) / 255

	return r, g, b
end

local function toBlit(color)
	cepheus.expect(1, color, "number")

	local hex = colorToHex[color]
	if hex then
		return hex
	end

	if color < MIN_COLOR or color > MAX_COLOR then
		error(string.format("color out of range (got %d, expected 1-32768)", color), 2)
	end

	if bit32.band(color, color - 1) ~= 0 then
		error("cannot convert color combination to blit character (expected single color)", 2)
	end

	local exponent = math.floor(math.log(color) / math.log(2) + 0.5)

	if exponent < 0 or exponent > 15 then
		error(string.format("invalid color value %d", color), 2)
	end

	return string.format("%x", exponent)
end

local function fromBlit(hex)
	cepheus.expect(1, hex, "string")

	if #hex ~= 1 then
		return nil
	end

	local color = hexToColor[hex]
	if color then
		return color
	end

	local value = tonumber(hex, 16)
	if not value or value < 0 or value > 15 then
		return nil
	end

	return bit32.lshift(1, value)
end

local function getName(color)
	cepheus.expect(1, color, "number")
	return colorToName[color]
end

local function getByName(name)
	cepheus.expect(1, name, "string")
	return nameToColor[name]
end

local function listColors(colors)
	cepheus.expect(1, colors, "number")

	if colors < 0 or colors > MAX_COMBINED then
		error("color out of range", 2)
	end

	local result = {}

	for i = 0, 15 do
		local color = bit32.lshift(1, i)
		if bit32.band(colors, color) ~= 0 then
			table.insert(result, color)
		end
	end

	return result
end

local function countColors(colors)
	cepheus.expect(1, colors, "number")

	if colors < 0 or colors > MAX_COMBINED then
		error("color out of range", 2)
	end

	local count = 0

	while colors > 0 do
		if bit32.band(colors, 1) == 1 then
			count = count + 1
		end
		colors = bit32.rshift(colors, 1)
	end

	return count
end

local function toString(colors)
	cepheus.expect(1, colors, "number")

	if colors < 0 or colors > MAX_COMBINED then
		return "invalid"
	end

	if colors == 0 then
		return "none"
	end

	local colorList = listColors(colors)
	local names = {}

	for _, color in ipairs(colorList) do
		local name = colorToName[color]
		if name then
			table.insert(names, name)
		else
			table.insert(names, string.format("0x%x", color))
		end
	end

	return table.concat(names, ", ")
end

local function isSingleColor(color)
	if type(color) ~= "number" then
		return false
	end

	if color < MIN_COLOR or color > MAX_COLOR then
		return false
	end

	return bit32.band(color, color - 1) == 0
end

local function isValid(colors)
	if type(colors) ~= "number" then
		return false
	end

	return colors >= 0 and colors <= MAX_COMBINED
end

return {
	_LIST_NAME = "cepheus.colors",

	combine = combine,
	subtract = subtract,
	test = test,
	packRGB = packRGB,
	unpackRGB = unpackRGB,
	toBlit = toBlit,
	fromBlit = fromBlit,

	getName = getName,
	getByName = getByName,
	listColors = listColors,
	countColors = countColors,
	toString = toString,
	isSingleColor = isSingleColor,
	isValid = isValid,
}
