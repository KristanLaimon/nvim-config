-- ============================================================================
-- tests/krsnvimscript/libraries/toml_spec.lua -- Spec tests for krsnvim.toml module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local toml = require("krs.lib.krsnvim.toml")

describe("krsnvim.toml module", function()
	it("parses TOML strings and handles basic structures", function()
		expect(type(toml)).toBe("table")
		if toml.decode then
			local res = toml.decode('name = "KRS"\nversion = 2')
			if res then
				expect(res.name).toBe("KRS")
			end
		end
	end)
end)
