-- ============================================================================
-- tests/spec/garrysmod_types_spec.lua -- Garry's Mod type injector schema test suite.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local type_injector = require("plugins.krs.tools.type_injector")

describe("plugins.krs.tools.type_injector.garrysmod_types", function()
	it("discovers 'garrysmod' as an available Lua schema", function()
		local schemas = type_injector.scan_available_schemas("lua")
		local found = false
		for _, name in ipairs(schemas) do
			if name == "garrysmod" then
				found = true
				break
			end
		end
		expect(found).toBe(true)
	end)

	it("resolves the garrysmod schema directory and globals.lua file", function()
		local dir = type_injector.resolve_schema_dir("lua", "garrysmod")
		expect(dir ~= nil).toBe(true)
		local file = dir .. "/globals.lua"
		expect(vim.fn.filereadable(file)).toBe(1)
	end)

	it("parses garrysmod globals.lua without syntax errors", function()
		local dir = type_injector.resolve_schema_dir("lua", "garrysmod")
		local file = dir .. "/globals.lua"
		local fn, err = loadfile(file)
		expect(err).toBe(nil)
		expect(type(fn)).toBe("function")
	end)

	it("ignores garrysmod schema directory when not activated in project", function()
		local root = vim.fn.stdpath("config")
		local ignored = type_injector.get_ignored_lua_directories(root)
		local found = false
		for _, p in ipairs(ignored) do
			if p:match("garrysmod") then
				found = true
				break
			end
		end
		expect(found).toBe(true)
	end)
end)
