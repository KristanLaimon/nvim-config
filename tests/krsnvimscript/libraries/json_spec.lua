-- ============================================================================
-- tests/krsnvimscript/libraries/json_spec.lua -- Spec tests for krsnvim.json module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local json = require("krs.lib.krsnvim.json")

describe("krsnvim.json module", function()
	it("encodes and decodes JSON objects", function()
		local tbl = { name = "KRS", version = 2 }
		local encoded = json.encode(tbl)
		expect(type(encoded)).toBe("string")
		expect(encoded).toContain("KRS")

		local decoded = json.decode(encoded)
		expect(decoded.name).toBe("KRS")
		expect(decoded.version).toBe(2)
	end)

	it("handles nil and empty inputs gracefully", function()
		expect(json.encode(nil)).toBe("null")
		expect(json.decode(nil)).toBe(nil)
	end)
end)
