-- ============================================================================
-- tests/spec/koreader_types_spec.lua -- KOReader type injector schema test suite.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local type_injector = require("plugins.krs.tools.type_injector")

describe("plugins.krs.tools.type_injector.koreader_types", function()
	it("discovers 'koreader' as an available Lua schema", function()
		local schemas = type_injector.scan_available_schemas("lua")
		local found = false
		for _, name in ipairs(schemas) do
			if name == "koreader" then
				found = true
				break
			end
		end
		expect(found).toBe(true)
	end)

	it("resolves the koreader schema directory and koreader_types.lua file", function()
		local dir = type_injector.resolve_schema_dir("lua", "koreader")
		expect(dir ~= nil).toBe(true)
		local file = dir .. "/koreader_types.lua"
		expect(vim.fn.filereadable(file)).toBe(1)
	end)

	it("parses koreader_types.lua without any syntax errors", function()
		local dir = type_injector.resolve_schema_dir("lua", "koreader")
		local file = dir .. "/koreader_types.lua"
		local fn, err = loadfile(file)
		expect(err).toBe(nil)
		expect(type(fn)).toBe("function")
	end)
end)
