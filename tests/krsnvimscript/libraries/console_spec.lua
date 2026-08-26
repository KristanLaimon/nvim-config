-- ============================================================================
-- tests/krsnvimscript/libraries/console_spec.lua -- Spec tests for krsnvim.console module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local console = require("krs.lib.krsnvim.console")

describe("krsnvim.console module", function()
	it("formats primitive arguments and strings", function()
		local log_out = console.format_args("Hello", 42, true)
		expect(log_out).toBe("Hello 42 true")
	end)

	it("stringifies tables into formatted JSON", function()
		local tbl = { name = "KRS", version = 2 }
		local json_str = console.stringify(tbl)
		expect(json_str).toContain('"name": "KRS"')
		expect(json_str).toContain('"version": 2')
	end)

	it("formats log levels with proper prefixes", function()
		expect(console.info("test info")).toContain("[INFO] test info")
		expect(console.warn("test warn")).toContain("[WARN] test warn")
		expect(console.error("test error")).toContain("[ERROR] test error")
		expect(console.debug("test debug")).toContain("[DEBUG] test debug")
	end)

	it("supports callable console(...) alias", function()
		local res = console("call test", 123)
		expect(res).toBe("call test 123")
	end)
end)
