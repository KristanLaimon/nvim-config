-- ============================================================================
-- tests/krsnvimscript/libraries/terminal_spec.lua -- Spec tests for krsnvim.terminal module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local terminal = require("krs.lib.krsnvim.terminal")

describe("krsnvim.terminal module", function()
	it("executes basic echo command", function()
		local res = terminal.exec("echo hello_krs")
		expect(res.ok).toBe(true)
		expect(res.code).toBe(0)
		expect(res.output).toContain("hello_krs")
	end)

	it("supports callable $ syntax", function()
		local res = terminal("echo krs_dollar")
		expect(res.ok).toBe(true)
		expect(res.output).toContain("krs_dollar")
	end)

	it("returns current working directory", function()
		local cwd = terminal.cwd()
		expect(type(cwd)).toBe("string")
		expect(#cwd > 0).toBe(true)
	end)
end)
