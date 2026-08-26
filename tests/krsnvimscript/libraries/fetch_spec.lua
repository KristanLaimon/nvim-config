-- ============================================================================
-- tests/krsnvimscript/libraries/fetch_spec.lua -- Spec tests for krsnvim.fetch module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local fetch = require("krs.lib.krsnvim.fetch")

describe("krsnvim.fetch module", function()
	it("exposes HTTP request methods", function()
		expect(type(fetch)).toBe("table")
		expect(type(fetch.get)).toBe("function")
		expect(type(fetch.post)).toBe("function")
		expect(type(fetch.put)).toBe("function")
		expect(type(fetch.delete)).toBe("function")
	end)
end)
