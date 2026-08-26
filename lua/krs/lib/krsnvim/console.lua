--- @module "krsnvim.console"
--- Human-readable Console Logging, Debugging, and JSON Pretty-Printing library for `krsnvimscript`.
--- Provides `console.log`, `console.info`, `console.warn`, `console.error`, `console.dir`, `console.json`, and direct callable `console(...)`.
---
--- @example
--- local console = import("console")
--- console.log("User details:", { name = "Kristan", role = "Developer", active = true })
--- console.dir({ status = "ok", count = 42 })

local M = {}

--- Recursively formats any Lua value into human-readable JSON text with 2-space indentation.
--- Handles tables, arrays, dictionaries, primitive values, functions, userdata, and circular references.
---
--- @param val any Value to format (table, string, number, boolean, function, userdata, nil).
--- @param indent string|nil Optional indentation string (defaults to "  ").
--- @param level number|nil Current nesting level (internal recursion).
--- @param visited table|nil Table tracking visited references for circular dependency prevention.
--- @return string formatted_json Human-readable JSON string.
local function stringify_json(val, indent, level, visited)
	indent = indent or "  "
	level = level or 0
	visited = visited or {}

	local t = type(val)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return val and "true" or "false"
	elseif t == "number" then
		return tostring(val)
	elseif t == "string" then
		return vim.json.encode(val)
	elseif t == "function" or t == "userdata" or t == "thread" then
		return vim.json.encode(tostring(val))
	elseif t == "table" then
		if visited[val] then
			return '"[Circular Reference]"'
		end
		visited[val] = true

		local cur_indent = string.rep(indent, level)
		local next_indent = string.rep(indent, level + 1)

		-- Detect if table is a sequential numeric array
		local is_array = true
		local count = 0
		for k, _ in pairs(val) do
			if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
				is_array = false
				break
			end
			count = count + 1
		end
		if is_array and count ~= #val then
			is_array = false
		end

		if is_array then
			if #val == 0 then
				visited[val] = nil
				return "[]"
			end
			local parts = {}
			for _, v in ipairs(val) do
				table.insert(parts, next_indent .. stringify_json(v, indent, level + 1, visited))
			end
			visited[val] = nil
			return "[\n" .. table.concat(parts, ",\n") .. "\n" .. cur_indent .. "]"
		else
			local keys = {}
			for k in pairs(val) do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)

			if #keys == 0 then
				visited[val] = nil
				return "{}"
			end

			local parts = {}
			for _, k in ipairs(keys) do
				local v = val[k]
				if v == nil then
					for orig_k, orig_v in pairs(val) do
						if tostring(orig_k) == k then
							v = orig_v
							break
						end
					end
				end
				local encoded_key = vim.json.encode(tostring(k))
				local encoded_val = stringify_json(v, indent, level + 1, visited)
				table.insert(parts, next_indent .. encoded_key .. ": " .. encoded_val)
			end
			visited[val] = nil
			return "{\n" .. table.concat(parts, ",\n") .. "\n" .. cur_indent .. "}"
		end
	end

	return vim.json.encode(tostring(val))
end

M.stringify = stringify_json

--- Formats a list of arguments into a space-separated log output string.
--- Tables and objects are automatically pretty-printed in JSON format.
---
--- @param ... any List of values to format.
--- @return string formatted Formatted log string.
function M.format_args(...)
	local n = select("#", ...)
	if n == 0 then
		return ""
	end

	local parts = {}
	for i = 1, n do
		local arg = select(i, ...)
		if type(arg) == "table" then
			table.insert(parts, stringify_json(arg))
		elseif type(arg) == "string" then
			table.insert(parts, arg)
		else
			table.insert(parts, tostring(arg))
		end
	end
	return table.concat(parts, " ")
end

--- Serializes any object or table to human-readable indented JSON string.
---
--- @param obj any Object or data structure to format.
--- @param indent string|nil Optional indentation string (default "  ").
--- @return string json_string Formatted JSON string.
function M.json(obj, indent)
	return stringify_json(obj, indent or "  ")
end

--- Prints inspect/dir view of an object or value to console.
---
--- @param obj any Object or data structure to inspect.
function M.dir(obj)
	local out = stringify_json(obj)
	print(out)
	return out
end

--- Standard console.log function. Prints space-separated arguments to console.
--- Tables/objects are formatted as pretty JSON.
---
--- @param ... any Arguments to log.
--- @return string log_output The formatted log string.
function M.log(...)
	local out = M.format_args(...)
	print(out)
	return out
end

--- Prints log output with [INFO] prefix.
---
--- @param ... any Arguments to log.
--- @return string log_output The formatted log string.
function M.info(...)
	local out = "[INFO] " .. M.format_args(...)
	print(out)
	return out
end

--- Prints log output with [WARN] prefix.
---
--- @param ... any Arguments to log.
--- @return string log_output The formatted log string.
function M.warn(...)
	local out = "[WARN] " .. M.format_args(...)
	print(out)
	return out
end

--- Prints log output with [ERROR] prefix.
---
--- @param ... any Arguments to log.
--- @return string log_output The formatted log string.
function M.error(...)
	local out = "[ERROR] " .. M.format_args(...)
	print(out)
	return out
end

--- Prints log output with [DEBUG] prefix.
---
--- @param ... any Arguments to log.
--- @return string log_output The formatted log string.
function M.debug(...)
	local out = "[DEBUG] " .. M.format_args(...)
	print(out)
	return out
end

--- Alias for console.dir
M.dump = M.dir

-- Make the module table directly callable: console(...) -> console.log(...)
setmetatable(M, {
	__call = function(_, ...)
		return M.log(...)
	end,
})

_G.console = M

return M
