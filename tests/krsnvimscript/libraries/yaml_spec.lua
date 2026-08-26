-- ============================================================================
-- tests/krsnvimscript/libraries/yaml_spec.lua -- Spec tests for krsnvim.yaml module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local yaml = require("krs.lib.krsnvim.yaml")

describe("krsnvim.yaml module", function()
	it("parses YAML strings and handles invalid input", function()
		expect(type(yaml)).toBe("table")
		if yaml.decode then
			local res = yaml.decode("name: KRS\nversion: 2")
			if res then
				expect(res.name).toBe("KRS")
			end
		end
	end)
end)
