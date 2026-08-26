-- ============================================================================
-- tests/run.lua -- Headless entry point for the KRS test suite.
-- ============================================================================
-- HOW TO RUN
--   nvim -l tests/run.lua              # everything
--   nvim -l tests/run.lua core_path    # only specs whose name contains "core_path"
--   :KrsTest                           # from inside the editor (same runner)
--
-- HOW IT WORKS
--   1. Every `tests/spec/*_spec.lua` file is a module returning nothing; it
--      registers suites through `krsnvim.test` (describe / it / expect).
--   2. This script loads them all, then calls `run()` once so a single summary
--      is printed and the process exits non-zero on failure (CI friendly).
--
-- WRITING A SPEC -- create tests/spec/<module>_spec.lua:
--   local t = require("krs.lib.krsnvim.test")
--   local describe, it, expect = t.describe, t.it, t.expect
--   describe("krs.core.path", function()
--     it("normalizes separators", function()
--       expect(require("krs.core.path").normalize([[C:\a]])).toBe("C:/a")
--     end)
--   end)
--
-- Specs must be side-effect free: no keymaps, no writes outside `vim.fn.tempname()`.
-- ============================================================================

local M = {}

--- Directory holding the spec files, relative to the config root.
M.spec_dir = "tests/spec"

--- Ensures `lua/` and the repository root are on `package.path` when running
--- through `nvim -l`, which does not set up `runtimepath` for us.
---
--- @param root string Config root directory.
local function bootstrap_paths(root)
	local sep = package.config:sub(1, 1)
	local lua_dir = root .. sep .. "lua"
	package.path = table.concat({
		lua_dir .. sep .. "?.lua",
		lua_dir .. sep .. "?" .. sep .. "init.lua",
		package.path,
	}, ";")
	vim.opt.runtimepath:prepend(root)
end

--- Discovers and loads every spec file matching `filter`.
---
--- @param root string Config root directory.
--- @param filter string|nil Substring a spec file name must contain.
--- @return integer count Number of spec files loaded.
--- @return string[] errors Load errors, one per failed spec.
function M.load_specs(root, filter)
	local patterns = {
		root .. "/" .. M.spec_dir .. "/*_spec.lua",
		root .. "/tests/krsnvimscript/libraries/*_spec.lua",
	}
	local files = {}
	for _, pat in ipairs(patterns) do
		for _, f in ipairs(vim.fn.glob(pat, false, true)) do
			table.insert(files, f)
		end
	end
	table.sort(files)

	local loaded, errors = 0, {}
	for _, file in ipairs(files) do
		local name = vim.fn.fnamemodify(file, ":t:r")
		if not filter or name:find(filter, 1, true) then
			local ok, err = pcall(dofile, file)
			if ok then
				loaded = loaded + 1
			else
				table.insert(errors, name .. ": " .. tostring(err))
			end
		end
	end
	return loaded, errors
end

--- Runs the whole suite and returns the exit code.
---
--- @param root string Config root directory.
--- @param filter string|nil Optional spec name filter.
--- @return integer exit_code 0 on success, 1 on any failure.
function M.run(root, filter)
	vim.g.krs_testing = true
	_G.krs_testing = true
	local loaded, errors = M.load_specs(root, filter)

	for _, err in ipairs(errors) do
		print("  Failed to load spec -> " .. err)
	end
	if loaded == 0 then
		print("No specs matched" .. (filter and (" filter '" .. filter .. "'") or "") .. ".")
		return #errors > 0 and 1 or 0
	end

	local ok, result = pcall(require("krs.lib.krsnvim.test").run)
	if not ok or #errors > 0 then
		if not ok then
			print(tostring(result))
		end
		return 1
	end
	return result.failed > 0 and 1 or 0
end

-- Only self-execute when THIS file is the `-l` entry script (not when dofile'd by run_me.lua).
local script_source = debug.getinfo(1, "S").source:sub(2)
if vim.v.argv and #vim.v.argv >= 3 then
	local entry = vim.fn.fnamemodify(vim.v.argv[#vim.v.argv], ":p")
	if vim.fn.fnamemodify(script_source, ":p") == entry then
		local root = vim.fn.fnamemodify(script_source, ":p:h:h")
		bootstrap_paths(root)
		os.exit(M.run(root, _G.arg and _G.arg[1] or nil))
	end
end

return M
