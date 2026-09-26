-- ============================================================================
-- tests/spec/love_types_spec.lua -- LÖVE type injector schema test suite.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local type_injector = require("plugins.krs.tools.type_injector")

describe("plugins.krs.tools.type_injector.love_types", function()
	it("discovers 'love' as an available Lua schema", function()
		local schemas = type_injector.scan_available_schemas("lua")
		local found = false
		for _, name in ipairs(schemas) do
			if name == "love" then
				found = true
				break
			end
		end
		expect(found).toBe(true)
	end)

	it("resolves the love schema directory and love_types.lua file", function()
		local dir = type_injector.resolve_schema_dir("lua", "love")
		expect(dir ~= nil).toBe(true)
		local file = dir .. "/love_types.lua"
		expect(vim.fn.filereadable(file)).toBe(1)
	end)

	it("parses love_types.lua without any syntax errors", function()
		local dir = type_injector.resolve_schema_dir("lua", "love")
		local file = dir .. "/love_types.lua"
		local fn, err = loadfile(file)
		expect(err).toBe(nil)
		expect(type(fn)).toBe("function")
	end)

	it("covers the released LÖVE 11.5 catalog with linked API docs", function()
		local dir = type_injector.resolve_schema_dir("lua", "love")
		local file = assert(io.open(dir .. "/love_types.lua", "r"))
		local source = file:read("*a")
		file:close()

		local _, aliases = source:gsub("---@alias love%.", "")
		local _, links = source:gsub("--- See: https://love2d%.org/wiki/", "")
		local functions = 0
		for line in source:gmatch("[^\n]+") do
			if line:match("^%-%-%-@field ") and line:find("(fun(", 1, true) then
				functions = functions + 1
			end
		end
		expect(functions).toBe(965)
		expect(aliases).toBe(59)
		expect(links >= 1149).toBe(true)
		for _, entry in ipairs({
			"---@class love.Mesh",
			"---@class love.SpriteBatch",
			"---@class love.RevoluteJoint",
			"---@class love.RecordingDevice",
			"---@class love.window_setMode_flags",
			"---@alias love.RenderTargetSetup",
			"---@field getVersion ",
			"---@field gamepadpressed? ",
			"---@field newMesh ",
			"---@field newQueueableSource ",
		}) do
			expect(source:find(entry, 1, true) ~= nil).toBe(true)
		end
	end)
end)
