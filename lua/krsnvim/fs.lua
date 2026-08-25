--- @module "krsnvim.fs"
--- High-performance File System and Path Manipulation Suite for `krsnvimscript`.
--- Provides cross-platform file reading, writing, directory creation, listing, and validation.
---
--- @example
--- local fs = import("krsnvim.fs")
--- if not fs.exists("output") then
---     fs.mkdir("output")
--- end
--- fs.write("output/log.txt", "Build completed successfully")
--- local content = fs.read("output/log.txt")
--- print(content)
local M = {}

--- Checks whether a file or directory exists at the specified path.
--- Supports wildcards, relative paths, absolute paths, and symlinks.
---
--- @param path string The file or directory path to check.
--- @return boolean exists `true` if the file or directory exists and is accessible, `false` otherwise.
---
--- @note Edge Cases:
--- - Returns `false` for `nil` or empty string `""` without throwing an error.
--- - Inspects regular files, directories, sockets, and glob patterns.
---
--- @see krsnvim.fs.read
--- @see krsnvim.fs.mkdir
---
--- @example
--- if fs.exists(".krsnvim/tasks.json") then
---     print("Tasks file found!")
--- end
function M.exists(path)
	if not path or path == "" then
		return false
	end
	return vim.fn.empty(vim.fn.glob(path)) == 0 or vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

--- Reads the entire text content of a file into a single string.
---
--- @param path string Absolute or relative path to the file to read.
--- @return string content The complete text content of the file.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if the file does not exist or permissions prevent reading.
--- - Always closes file handles safely before returning or throwing.
---
--- @see krsnvim.fs.write
--- @see krsnvim.fs.exists
--- @see krsnvim.json.load
---
--- @example
--- local text = fs.read("config.txt")
--- print("File size in bytes: " .. #text)
function M.read(path)
	local f = io.open(path, "r")
	if not f then
		error("krsnvim.fs: Cannot read file: " .. tostring(path))
	end
	local content = f:read("*a")
	f:close()
	return content
end

--- Writes content to a file at the specified path (overwriting existing content).
--- Missing parent directories should be created prior to writing using `krsnvim.fs.mkdir`.
---
--- @param path string Absolute or relative target file path.
--- @param content string|nil Text content to write into the file. Passes empty string if `nil`.
--- @return boolean success Returns `true` upon successful write.
---
--- @note Edge Cases & Errors:
--- - Throws a Lua error if the directory does not exist or path is unwritable.
--- - Safe file handle closure guaranteed on write completion.
---
--- @see krsnvim.fs.read
--- @see krsnvim.fs.mkdir
--- @see krsnvim.json.save
---
--- @example
--- fs.mkdir("dist")
--- fs.write("dist/bundle.js", "console.log('Hello');")
function M.write(path, content)
	local f = io.open(path, "w")
	if not f then
		error("krsnvim.fs: Cannot write file: " .. tostring(path))
	end
	f:write(content or "")
	f:close()
	return true
end

--- Recursively creates a directory path if it does not already exist (equivalent to `mkdir -p`).
---
--- @param path string Path of directory to create.
--- @return boolean success `true` if directory exists or was created successfully, `false` otherwise.
---
--- @note Edge Cases:
--- - If the directory already exists, returns `true` immediately without error.
--- - Safely creates intermediate nested directories automatically.
---
--- @see krsnvim.fs.exists
--- @see krsnvim.fs.write
---
--- @example
--- fs.mkdir(".krsnvim/cache/logs")
function M.mkdir(path)
	if vim.fn.isdirectory(path) == 0 then
		return vim.fn.mkdir(path, "p") == 1
	end
	return true
end

--- Lists all files and subdirectories directly contained within a directory path.
---
--- @param dir_path string Directory path to inspect.
--- @return string[] paths Table array containing absolute/relative paths of matched items.
---
--- @note Edge Cases:
--- - Returns an empty table `{}` if directory is empty or does not exist.
--- - Excludes hidden dotfiles unless specified in path glob pattern.
---
--- @see krsnvim.fs.exists
---
--- @example
--- local files = fs.list("src")
--- for _, file_path in ipairs(files) do
---     print("Found file:", file_path)
--- end
function M.list(dir_path)
	return vim.fn.glob(dir_path .. "/*", false, true)
end

return M
