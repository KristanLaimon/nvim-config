--- @module "krsnvim.yaml"
--- Native Pure Lua YAML Parser, Encoder, and File I/O manager for `krsnvimscript`.
--- Handles basic YAML mappings, sequences, numbers, booleans, nulls, and comments.
---
--- @example
--- local yaml = import("krsnvim.yaml")
--- local config = yaml.load("config.yaml")
--- config.build_env = "production"
--- yaml.save("config.yaml", config)
local M = {}

local function parse_scalar(val)
	if not val then
		return nil
	end
	val = val:match("^%s*(.-)%s*$")
	if val == "" or val == "~" or val:lower() == "null" then
		return nil
	end
	if val:lower() == "true" or val:lower() == "yes" then
		return true
	end
	if val:lower() == "false" or val:lower() == "no" then
		return false
	end
	local num = tonumber(val)
	if num then
		return num
	end
	if (val:sub(1, 1) == '"' and val:sub(-1) == '"') or (val:sub(1, 1) == "'" and val:sub(-1) == "'") then
		return val:sub(2, -2)
	end
	return val
end

--- Decodes a YAML formatted string into a native Lua table.
---
--- @param str string|nil Raw YAML string to parse.
--- @return table data Parsed Lua table representation. Returns `{}` if input is `nil` or empty `""`.
---
--- @note Edge Cases:
--- - Ignores `#` comment lines automatically.
--- - Parses basic scalars (booleans `true`/`false`, numbers, `null`, strings).
--- - Handles nested indented blocks and `-` list items.
---
--- @see krsnvim.yaml.encode
--- @see krsnvim.yaml.load
---
--- @example
--- local data = yaml.decode([[
--- name: MyApp
--- version: 1.0.0
--- features:
---   - fast
---   - native
--- ]])
--- print(data.name, data.features[1])
function M.decode(str)
	if not str or str == "" then
		return {}
	end
	local lines = {}
	for line in str:gmatch("[^\r\n]+") do
		local uncommented = line:match("^([^#]*)")
		if uncommented and uncommented:find("%S") then
			table.insert(lines, uncommented)
		end
	end

	local function parse_lines(index, current_indent)
		local result = {}
		local is_array = false

		while index <= #lines do
			local line = lines[index]
			local indent = #(line:match("^(%s*)") or "")
			if indent < current_indent then
				break
			end

			local trimmed = line:match("^%s*(.-)%s*$")
			if trimmed:sub(1, 2) == "- " or trimmed == "-" then
				is_array = true
				local item_str = trimmed:sub(3)
				if item_str == "" then
					local item_val, next_idx = parse_lines(index + 1, indent + 2)
					table.insert(result, item_val)
					index = next_idx - 1
				else
					table.insert(result, parse_scalar(item_str))
				end
			else
				local key, rest = trimmed:match("^([%w_%-%.]+)%s*:%s*(.*)$")
				if key then
					if rest == "" then
						local child_val, next_idx = parse_lines(index + 1, indent + 2)
						result[key] = child_val
						index = next_idx - 1
					else
						result[key] = parse_scalar(rest)
					end
				end
			end
			index = index + 1
		end

		return result, index
	end

	local res, _ = parse_lines(1, 0)
	return res
end

local function dump_val(val, indent)
	local spaces = string.rep("  ", indent)
	local t = type(val)
	if t == "table" then
		local is_list = vim.islist and vim.islist(val) or (#val > 0)
		local out = {}
		if is_list then
			for _, v in ipairs(val) do
				if type(v) == "table" then
					table.insert(out, spaces .. "-\n" .. dump_val(v, indent + 1))
				else
					table.insert(out, spaces .. "- " .. tostring(v))
				end
			end
		else
			for k, v in pairs(val) do
				if type(v) == "table" then
					table.insert(out, spaces .. tostring(k) .. ":\n" .. dump_val(v, indent + 1))
				else
					table.insert(out, spaces .. tostring(k) .. ": " .. tostring(v))
				end
			end
		end
		return table.concat(out, "\n")
	elseif t == "boolean" or t == "number" then
		return tostring(val)
	else
		return tostring(val)
	end
end

--- Serializes a Lua table into a YAML formatted string.
---
--- @param obj table|any Data structure to convert to YAML text.
--- @return string yaml_str Formatted YAML output string.
---
--- @see krsnvim.yaml.decode
--- @see krsnvim.yaml.save
---
--- @example
--- local text = yaml.encode({ app = "KrsNvim", ports = { 8080, 3000 } })
--- print(text)
function M.encode(obj)
	if not obj then
		return ""
	end
	return dump_val(obj, 0)
end

--- Reads a YAML file from disk and parses its contents into a Lua table.
---
--- @param filepath string Path to the YAML file.
--- @return table data Parsed Lua table representation.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if the file cannot be opened or read.
---
--- @see krsnvim.yaml.save
--- @see krsnvim.yaml.decode
--- @see krsnvim.fs.read
---
--- @example
--- local data = yaml.load("docker-compose.yml")
function M.load(filepath)
	local f = io.open(filepath, "r")
	if not f then
		error("krsnvim.yaml: Cannot open file: " .. tostring(filepath))
	end
	local content = f:read("*a")
	f:close()
	return M.decode(content)
end

--- Serializes a Lua table and writes it directly to a YAML file on disk.
---
--- @param filepath string Target path for the output YAML file.
--- @param obj table Data structure to encode and save.
--- @return boolean success Returns `true` upon successful save.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if file writing fails.
---
--- @see krsnvim.yaml.load
--- @see krsnvim.yaml.encode
--- @see krsnvim.fs.write
---
--- @example
--- yaml.save("config.yaml", { env = "production" })
function M.save(filepath, obj)
	local str = M.encode(obj)
	local f = io.open(filepath, "w")
	if not f then
		error("krsnvim.yaml: Cannot write file: " .. tostring(filepath))
	end
	f:write(str)
	f:close()
	return true
end

return M
