-- Regenerate the LÖVE 11.5 LuaLS schema from love2d-community/love-api.
-- Usage: lua scripts/generate_love_types.lua /path/to/love-api
-- The catalog is maintained from https://love2d.org/wiki/love .
local root = assert(arg[1], "pass the extracted love-api directory")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local api = require("love_api")
assert(api.version == "11.5", "expected the LÖVE 11.5 catalog")

local lines = {}
local function add(s)
	lines[#lines + 1] = s
end
local function clean(s)
	s = (s or ""):gsub("\r", " "):gsub("\n+", " "):gsub("%s+", " ")
	s = s:gsub("%-%-%-", "—")
	return s:match("^%s*(.-)%s*$")
end
local function first_sentence(s)
	s = clean(s)
	return clean(s:match("^.-%.%s") or s)
end
local function url(name)
	return "https://love2d.org/wiki/" .. name
end
local table_types = {}
local table_definitions = {}
local function type_of(raw, parameter)
	if parameter and table_types[parameter] then
		return table_types[parameter]
	end
	if not raw then
		return "any"
	end
	if raw:find(" or ", 1, true) then
		local variants = {}
		for part in raw:gmatch("[^ ]+") do
			if part ~= "or" then
				variants[#variants + 1] = type_of(part)
			end
		end
		return table.concat(variants, "|")
	end
	if raw == "table" then
		return "table"
	end
	if raw == "function" then
		return "function"
	end
	if raw == "light userdata" then
		return "userdata"
	end
	if raw == "cdata" then
		return "any" -- LuaJIT FFI cdata has no LuaLS builtin type.
	end
	if raw == "Variant" then
		return "string|number|boolean|love.Object|table"
	end
	if raw == "nil" then
		return "nil"
	end
	if raw == "number" or raw == "string" or raw == "boolean" or raw == "any" then
		return raw
	end
	return "love." .. raw
end
local function identifier(name, index)
	name = clean(name):gsub("[^%w_]", "_")
	if name == "" or name == "___" then
		return "..."
	end
	if
		name:match("^%d")
		or name == "end"
		or name == "function"
		or name == "local"
		or name == "repeat"
		or name == "until"
	then
		return "arg" .. index
	end
	return name
end
local function signature(variant, owner)
	local args = {}
	if owner then
		args[#args + 1] = "self: " .. owner
	end
	for i, p in ipairs(variant.arguments or {}) do
		local name = identifier(p.name, i)
		local ty = type_of(p.type, p)
		if name == "..." then
			args[#args + 1] = "...: " .. ty
		else
			args[#args + 1] = name .. (p.default and "?" or "") .. ": " .. ty
		end
	end
	local returns = {}
	for _, p in ipairs(variant.returns or {}) do
		returns[#returns + 1] = type_of(p.type, p)
	end
	return "fun(" .. table.concat(args, ", ") .. ")" .. (#returns > 0 and (": " .. table.concat(returns, ", ")) or "")
end

local examples = {
	["love.load"] = 'function love.load() image = love.graphics.newImage("player.png") end',
	["love.update"] = "function love.update(dt) x = x + speed * dt end",
	["love.draw"] = "function love.draw() love.graphics.draw(image, x, y) end",
	["love.graphics.draw"] = "love.graphics.draw(image, 100, 80, math.pi / 4)",
	["love.graphics.print"] = 'love.graphics.print("Hello, LÖVE!", 20, 20)',
	["love.graphics.setColor"] = "love.graphics.setColor(1, 0.4, 0.2, 1)",
	["love.graphics.newImage"] = 'local image = love.graphics.newImage("player.png")',
	["love.graphics.newCanvas"] = "local canvas = love.graphics.newCanvas(320, 180)",
	["love.graphics.setCanvas"] = "love.graphics.setCanvas(canvas); love.graphics.clear(); love.graphics.setCanvas()",
	["love.graphics.push"] = "love.graphics.push(); love.graphics.translate(20, 30); love.graphics.pop()",
	["love.audio.newSource"] = 'local music = love.audio.newSource("music.ogg", "stream")',
	["love.filesystem.write"] = 'local ok, err = love.filesystem.write("save.txt", "level=2")',
	["love.filesystem.read"] = 'local contents, size = love.filesystem.read("save.txt")',
	["love.keyboard.isDown"] = 'if love.keyboard.isDown("space") then jump() end',
	["love.mouse.getPosition"] = "local x, y = love.mouse.getPosition()",
	["love.physics.newWorld"] = "local world = love.physics.newWorld(0, 9.81 * 64, true)",
	["love.timer.getDelta"] = "local dt = love.timer.getDelta()",
	["love.window.setMode"] = "love.window.setMode(800, 600, { resizable = true })",
}
local tips = {
	["love.update"] = "Multiply movement speeds by dt to keep motion independent of frame rate.",
	["love.draw"] = "Draw each frame here; load images and fonts once in love.load.",
	["love.graphics.setColor"] = "Color channels use 0–1 values in LÖVE 11.x.",
	["love.graphics.setCanvas"] = "Call with no canvas afterward to resume drawing to the screen.",
	["love.graphics.push"] = "Pair each push with pop to restore the previous graphics state.",
	["love.audio.newSource"] = "Use 'stream' for long music and 'static' for short effects.",
	["love.filesystem.write"] = "Paths are relative to LÖVE's save directory; check the return value.",
	["love.physics.newWorld"] = "Step the world from love.update with world:update(dt).",
}
local function register_tables(fn, prefix)
	for _, variant in ipairs(fn.variants or {}) do
		for _, category in ipairs({ "arguments", "returns" }) do
			for i, p in ipairs(variant[category] or {}) do
				if p.table and #p.table > 0 and not table_types[p] then
					local name = "love." .. (prefix .. fn.name .. "_" .. identifier(p.name, i)):gsub("[^%w_]", "_")
					if category == "returns" then
						name = name .. "Result"
					end
					local existing = {}
					for _, definition in ipairs(table_definitions) do
						existing[definition.name] = true
					end
					local base = name
					local suffix = 2
					while existing[name] do
						name = base .. suffix
						suffix = suffix + 1
					end
					table_types[p] = name
					local source = prefix:find(":", 1, true) and (prefix .. fn.name) or ("love." .. prefix .. fn.name)
					table_definitions[#table_definitions + 1] = { name = name, fields = p.table, source = source }
				end
			end
		end
	end
end
for _, module in ipairs(api.modules) do
	for _, fn in ipairs(module.functions or {}) do
		register_tables(fn, module.name .. ".")
	end
	for _, t in ipairs(module.types or {}) do
		for _, fn in ipairs(t.functions or {}) do
			register_tables(fn, t.name .. ":")
		end
	end
end
for _, t in ipairs(api.types or {}) do
	for _, fn in ipairs(t.functions or {}) do
		register_tables(fn, t.name .. ":")
	end
end
for _, fn in ipairs(api.functions or {}) do
	register_tables(fn, "")
end
for _, fn in ipairs(api.callbacks or {}) do
	register_tables(fn, "")
end

local function function_field(fn, prefix, owner, callback)
	local full = prefix .. fn.name
	if full == "love.window.setMode" then
		for _, variant in ipairs(fn.variants or {}) do
			for _, p in ipairs(variant.arguments or {}) do
				if p.name == "flags" then
					p.default = p.default or "nil"
				end
			end
		end
	end
	local variants = {}
	for _, v in ipairs(fn.variants or {}) do
		variants[#variants + 1] = signature(v, owner)
	end
	if #variants == 0 then
		variants[1] = "fun(...: any): any"
	end
	add("--- " .. first_sentence(fn.description))
	local primary = (fn.variants or {})[1]
	if primary then
		for i, p in ipairs(primary.arguments or {}) do
			local detail = first_sentence(p.description)
			if detail ~= "" then
				local default = p.default and (" Default: `" .. clean(p.default) .. "`.") or ""
				add("--- Parameter `" .. identifier(p.name, i) .. "` (" .. type_of(p.type, p) .. "): " .. detail .. default)
			end
		end
		for i, p in ipairs(primary.returns or {}) do
			local detail = first_sentence(p.description)
			if detail ~= "" then
				add("--- Returns `" .. identifier(p.name, i) .. "` (" .. type_of(p.type, p) .. "): " .. detail)
			end
		end
	end
	if examples[full] then
		add("--- Example: `" .. examples[full] .. "`")
	end
	if tips[full] then
		add("--- Tip: " .. tips[full])
	end
	add("--- See: " .. url(full))
	for i, variant in ipairs(variants) do
		variants[i] = "(" .. variant .. ")"
	end
	add(
		"---@field "
			.. fn.name
			.. (callback and "?" or "")
			.. " "
			.. table.concat(variants, "|")
			.. " "
			.. first_sentence(fn.description)
	)
end

add("---@meta")
add("-- LÖVE 11.5 API types. Generated from love2d-community/love-api (wiki-derived).")
add("-- Regenerate with: lua scripts/generate_love_types.lua /path/to/love-api")
add("-- Reference: https://love2d.org/wiki/love")
add("")
add("--- A Canvas or a table selecting its mipmap, layer, or cubemap face.")
add("--- See: " .. url("love.graphics.setCanvas"))
add("---@alias love.RenderTargetSetup love.Canvas|table")
add("")

for _, definition in ipairs(table_definitions) do
	add("--- Options and values documented for " .. definition.source .. ".")
	add("--- See: " .. url(definition.source))
	add("---@class " .. definition.name)
	for i, field in ipairs(definition.fields) do
		local name = identifier(field.name, i)
		if name ~= "..." then
			local ty = type_of(field.type, field)
			if name == "vsync" and definition.source:find("love.window.", 1, true) then
				ty = "integer"
			end
			add(
				"---@field " .. name .. (field.default and "?" or "") .. " " .. ty .. " " .. first_sentence(field.description)
			)
		end
	end
	add("")
end

-- Enums are aliases so completion offers the actual accepted values.
for _, module in ipairs(api.modules) do
	for _, enum in ipairs(module.enums or {}) do
		local values = {}
		for _, constant in ipairs(enum.constants or {}) do
			values[#values + 1] = string.format("%q", constant.name)
		end
		add("--- " .. first_sentence(enum.description))
		add("--- See: " .. url(enum.name))
		add("---@alias love." .. enum.name .. " " .. (#values > 0 and table.concat(values, "|") or "string"))
		add("")
	end
end

local types = {}
for _, t in ipairs(api.types or {}) do
	types[#types + 1] = t
end
for _, module in ipairs(api.modules) do
	for _, t in ipairs(module.types or {}) do
		types[#types + 1] = t
	end
end
table.sort(types, function(a, b)
	return a.name < b.name
end)
for _, t in ipairs(types) do
	add("--- " .. first_sentence(t.description))
	add("--- See: " .. url(t.name))
	local parent = t.supertypes and t.supertypes[1]
	add("---@class love." .. t.name .. (parent and (" : love." .. parent) or ""))
	for _, fn in ipairs(t.functions or {}) do
		function_field(fn, t.name .. ":", "love." .. t.name)
	end
	add("")
end

for _, module in ipairs(api.modules) do
	add("--- " .. first_sentence(module.description))
	add("--- See: " .. url("love." .. module.name))
	add("---@class love." .. module.name)
	for _, fn in ipairs(module.functions or {}) do
		function_field(fn, "love." .. module.name .. ".")
	end
	add("")
end

add("--- Main LÖVE namespace. Callbacks are assigned by the game.")
add("--- See: " .. url("love"))
add("---@class love")
for _, module in ipairs(api.modules) do
	add("---@field " .. module.name .. " love." .. module.name .. " " .. first_sentence(module.description))
end
for _, fn in ipairs(api.functions or {}) do
	function_field(fn, "love.")
end
for _, fn in ipairs(api.callbacks or {}) do
	function_field(fn, "love.", nil, true)
end
add("love = love or {}")
add("")

local output = "schemas-langs/lua/love/love_types.lua"
local file = assert(io.open(output, "w"))
file:write(table.concat(lines, "\n"))
file:close()
print(string.format("Generated %s: %d modules, %d types, %d lines", output, #api.modules, #types, #lines))
