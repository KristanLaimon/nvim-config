-- ============================================================================
-- tests/spec/lazy_specs_spec.lua -- Validates lazy plugin specs for well-formedness.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("lazy plugin specs integrity", function()
	it("ensures no plugin spec has a nil, empty, or invalid LHS in its keys table", function()
		local root = vim.fn.stdpath("config")
		local plugin_files = vim.fn.glob(root .. "/lua/plugins/**/*.lua", false, true)

		expect(#plugin_files > 0).toBe(true)

		for _, filepath in ipairs(plugin_files) do
			local spec_module = dofile(filepath)
			local specs = type(spec_module) == "table" and spec_module or {}
			if specs[1] and type(specs[1]) == "string" then
				specs = { specs }
			end

			for _, spec in ipairs(specs) do
				if type(spec) == "table" and spec.keys then
					local keys = spec.keys
					if type(keys) == "table" then
						for i, k in ipairs(keys) do
							if type(k) == "table" then
								local lhs = k[1]
								local file_basename = vim.fn.fnamemodify(filepath, ":t")
								expect(type(lhs) == "string" and lhs ~= "").toBe(
									true,
									string.format("Plugin spec in '%s' (key #%d) has invalid LHS: %s", file_basename, i, vim.inspect(lhs))
								)
							end
						end
					end
				end
			end
		end
	end)
end)
