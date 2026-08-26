--- @module "krsnvim.json"
--- Fast JSON Parser, Encoder, and File Management module for `krsnvimscript`.
--- Wraps Neovim's native C-accelerated JSON parser (`vim.json`) with safe error handling and file I/O helpers.
---
--- @example
--- local json = import("krsnvim.json")
--- local data = json.load("package.json")
--- data.version = "1.2.0"
--- json.save("package.json", data)
local M = {}

--- Decodes a JSON string into a native Lua table or primitive value.
---
--- @param str string|nil The raw JSON string to decode.
--- @return table|any|nil data Decoded Lua table or value. Returns `nil` if input string is `nil` or empty `""`.
---
--- @note Edge Cases & Errors:
--- - Throws a descriptive Lua error if the JSON string is malformed or contains syntax errors.
--- - Decodes `null` as `vim.NIL` (or `nil` depending on structure).
---
--- @see krsnvim.json.encode
--- @see krsnvim.json.load
---
--- @example
--- local data = json.decode('{"name": "Neovim", "active": true}')
--- print(data.name) -- Output: Neovim
function M.decode(str)
	if not str or str == "" then
		return nil
	end
	local ok, res = pcall(vim.json.decode, str)
	if not ok then
		error("krsnvim.json: Error decoding JSON: " .. tostring(res))
	end
	return res
end

--- Serializes a Lua table or primitive value into a JSON formatted string.
---
--- @param obj table|any Lua table, array, or primitive data structure to encode.
--- @param opts table|nil Optional formatting configurations (reserved for extension).
--- @return string json_str Serialized JSON text string.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if the table contains recursive references or function values.
--- - Empty Lua tables `{}` encode as `{}` (or `[]` for empty sequences).
---
--- @see krsnvim.json.decode
--- @see krsnvim.json.save
---
--- @example
--- local str = json.encode({ name = "Project", tags = { "lua", "nvim" } })
--- print(str) -- Output: {"name":"Project","tags":["lua","nvim"]}
function M.encode(obj, opts)
	opts = opts or {}
	local ok, res = pcall(vim.json.encode, obj)
	if not ok then
		error("krsnvim.json: Error encoding JSON: " .. tostring(res))
	end
	return res
end

--- Reads a file from disk and parses its contents as JSON.
---
--- @param filepath string Path to the JSON file to load.
--- @return table|any data Parsed Lua data structure.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if the file cannot be opened or read.
--- - Throws a Lua error if file contents contain invalid JSON syntax.
---
--- @see krsnvim.json.save
--- @see krsnvim.json.decode
--- @see krsnvim.fs.read
---
--- @example
--- local config = json.load(".krsnvim/tasks.json")
--- print("Default task:", config.default_task)
function M.load(filepath)
	local f = io.open(filepath, "r")
	if not f then
		error("krsnvim.json: Cannot open file: " .. tostring(filepath))
	end
	local content = f:read("*a")
	f:close()
	return M.decode(content)
end

--- Serializes a Lua table/data structure and writes it directly to a JSON file on disk.
---
--- @param filepath string Target path for the output JSON file.
--- @param obj table|any Data structure to serialize and save.
--- @return boolean success Returns `true` upon successful save.
---
--- @note Edge Cases & Errors:
--- - Overwrites target file content completely.
--- - Throws a Lua error if the target directory does not exist or lacks write permissions.
---
--- @see krsnvim.json.load
--- @see krsnvim.json.encode
--- @see krsnvim.fs.write
---
--- @example
--- json.save(".krsnvim/launch.json", { profiles = {} })
function M.save(filepath, obj)
	local str = M.encode(obj)
	local f = io.open(filepath, "w")
	if not f then
		error("krsnvim.json: Cannot write file: " .. tostring(filepath))
	end
	f:write(str)
	f:close()
	return true
end

return M
