-- ============================================================================
-- tests/spec/search_keymaps_spec.lua -- Unit tests for search keymappings.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("search keymaps configuration", function()
	it("configures <C-k> and <C-K> for find_files (respecting .gitignore)", function()
		local search = require("keymaps.search")
		local find_files = search.settings.keys.find_files

		local has_ck, has_ck_upper = false, false
		for _, key in ipairs(find_files) do
			if key == "<C-k>" then
				has_ck = true
			end
			if key == "<C-K>" then
				has_ck_upper = true
			end
		end

		expect(has_ck).toBe(true)
		expect(has_ck_upper).toBe(true)
	end)

	it("configures <C-A-k> and <C-A-K> for find_all_files (ignoring .gitignore)", function()
		local search = require("keymaps.search")
		local find_all = search.settings.keys.find_all_files

		local has_cak, has_cak_upper = false, false
		for _, key in ipairs(find_all) do
			if key == "<C-A-k>" then
				has_cak = true
			end
			if key == "<C-A-K>" then
				has_cak_upper = true
			end
		end

		expect(has_cak).toBe(true)
		expect(has_cak_upper).toBe(true)
	end)
end)
