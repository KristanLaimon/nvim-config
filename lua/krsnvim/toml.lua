--- @module "krsnvim.toml"
--- Native Pure Lua TOML Parser, Encoder, and File I/O manager for `krsnvimscript`.
--- Handles TOML tables `[section]`, key-value assignments `key = value`, inline arrays `[1, 2]`, booleans, and strings.
---
--- @example
--- local toml = import("krsnvim.toml")
--- local cargo = toml.load("Cargo.toml")
--- print(cargo.package.name)
--- toml.save("Cargo.toml", cargo)
local M = {}

local function parse_scalar(val)
	if not val then
		return nil
	end
	val = val:match("^%s*(.-)%s*$")
	if val == "true" then
		return true
	end
	if val == "false" then
		return false
	end
	local num = tonumber(val)
	if num then
		return num
	end
	if (val:sub(1, 1) == '"' and val:sub(-1) == '"') or (val:sub(1, 1) == "'" and val:sub(-1) == "'") then
		return val:sub(2, -2)
	end
	if val:sub(1, 1) == "[" and val:sub(-1) == "]" then
		local items = {}
		local inner = val:sub(2, -2)
		for item in inner:gmatch("[^,%s]+") do
			table.insert(items, parse_scalar(item))
		end
		return items
	end
	return val
end

--- Decodes a TOML formatted string into a native Lua table.
---
--- @param str string|nil Raw TOML string text to parse.
--- @return table data Parsed Lua table representation. Returns `{}` if input is `nil` or empty `""`.
---
--- @note Edge Cases:
--- - Automatically strips `#` comments.
--- - Parses `[section]` headers into sub-tables.
--- - Handles strings, integers, floats, booleans, and inline arrays `[a, b]`.
---
--- @see krsnvim.toml.encode
--- @see krsnvim.toml.load
---
--- @example
--- local data = toml.decode([[
--- title = "TOML Example"
--- [owner]
--- name = "Kristan"
--- ]])
--- print(data.title, data.owner.name)
function M.decode(str)
	if not str or str == "" then
		return {}
	end
	local root = {}
	local current_section = root

	for line in str:gmatch("[^\r\n]+") do
		local uncommented = line:match("^([^#]*)")
		if uncommented then
			local trimmed = uncommented:match("^%s*(.-)%s*$")
			if trimmed ~= "" then
				local section = trimmed:match("^%[%s*([%w_%-%.]+)%s*%]$")
				if section then
					root[section] = root[section] or {}
					current_section = root[section]
				else
					local k, v = trimmed:match("^([%w_%-%.]+)%s*=%s*(.-)$")
					if k and v then
						current_section[k] = parse_scalar(v)
					end
				end
			end
		end
	end

	return root
end

--- Serializes a Lua table structure into a TOML formatted string.
---
--- @param obj table Data structure to encode as TOML text.
--- @return string toml_str Formatted TOML output string.
---
--- @see krsnvim.toml.decode
--- @see krsnvim.toml.save
---
--- @example
--- local str = toml.encode({ app = "Nvim", server = { port = 8080 } })
--- print(str)
function M.encode(obj)
	if not obj then
		return ""
	end
	local lines = {}
	local sections = {}

	for k, v in pairs(obj) do
		if type(v) == "table" then
			sections[k] = v
		else
			table.insert(lines, string.format("%s = %s", k, type(v) == "string" and ('"' .. v .. '"') or tostring(v)))
		end
	end

	for sec_name, sec_table in pairs(sections) do
		table.insert(lines, "\n[" .. sec_name .. "]")
		for k, v in pairs(sec_table) do
			table.insert(lines, string.format("%s = %s", k, type(v) == "string" and ('"' .. v .. '"') or tostring(v)))
		end
	end

	return table.concat(lines, "\n")
end

--- Reads a TOML file from disk and decodes its contents into a Lua table.
---
--- @param filepath string File path of the TOML file.
--- @return table data Parsed Lua table structure.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if the file cannot be opened or read.
---
--- @see krsnvim.toml.save
--- @see krsnvim.toml.decode
--- @see krsnvim.fs.read
---
--- @example
--- local pyproject = toml.load("pyproject.toml")
function M.load(filepath)
	local f = io.open(filepath, "r")
	if not f then
		error("krsnvim.toml: Cannot open file: " .. tostring(filepath))
	end
	local content = f:read("*a")
	f:close()
	return M.decode(content)
end

--- Serializes a Lua table and writes it directly to a TOML file on disk.
---
--- @param filepath string Target path for the output TOML file.
--- @param obj table Data structure to encode and save.
--- @return boolean success Returns `true` upon successful write.
---
--- @note Edge Cases & Errors:
--- - Overwrites existing target file.
--- - Throws a Lua error if target file cannot be created or written.
---
--- @see krsnvim.toml.load
--- @see krsnvim.toml.encode
--- @see krsnvim.fs.write
---
--- @example
--- toml.save("settings.toml", { theme = "dark" })
function M.save(filepath, obj)
	local str = M.encode(obj)
	local f = io.open(filepath, "w")
	if not f then
		error("krsnvim.toml: Cannot write file: " .. tostring(filepath))
	end
	f:write(str)
	f:close()
	return true
end

return M
