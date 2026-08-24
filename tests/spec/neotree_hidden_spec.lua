-- ============================================================================
-- tests/spec/neotree_hidden_spec.lua -- Neo-tree custom hidden items tests.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local neotree_hidden = require("plugins.krs.neotree_hidden")
local project = require("krs.core.project")

describe("plugins.krs.neotree_hidden state management", function()
	local test_root = nil

	beforeEach(function()
		test_root = vim.fn.tempname()
		vim.fn.mkdir(test_root .. "/.krsnvim", "p")
		neotree_hidden.visibility_mode = "hide"
		neotree_hidden.clear_all(test_root)
	end)

	afterEach(function()
		if test_root then
			neotree_hidden.clear_all(test_root)
			vim.fn.delete(test_root, "rf")
		end
	end)

	it("resolves config path inside .krsnvim/", function()
		local conf = neotree_hidden.get_config_path(test_root)
		expect(conf:find(".krsnvim", 1, true) ~= nil).toBe(true)
		expect(conf:find("neotree_hidden.json", 1, true) ~= nil).toBe(true)
	end)

	it("toggles path hidden status", function()
		local path = test_root .. "/src/test_file.txt"
		expect(neotree_hidden.is_path_hidden(path, test_root)).toBe(false)

		local is_hidden = neotree_hidden.toggle_path(path, test_root)
		expect(is_hidden).toBe(true)
		expect(neotree_hidden.is_path_hidden(path, test_root)).toBe(true)

		local is_hidden_again = neotree_hidden.toggle_path(path, test_root)
		expect(is_hidden_again).toBe(false)
		expect(neotree_hidden.is_path_hidden(path, test_root)).toBe(false)
	end)

	it("detects parent folder hidden status for child paths", function()
		local folder = test_root .. "/secret_folder"
		local child_file = folder .. "/sub/nested/file.lua"

		expect(neotree_hidden.is_path_hidden(child_file, test_root)).toBe(false)

		neotree_hidden.toggle_path(folder, test_root)
		expect(neotree_hidden.is_path_hidden(folder, test_root)).toBe(true)
		expect(neotree_hidden.is_path_hidden(child_file, test_root)).toBe(true)
	end)

	it("toggles visibility mode between hide and show", function()
		expect(neotree_hidden.visibility_mode).toBe("hide")

		neotree_hidden.toggle_visibility(test_root)
		expect(neotree_hidden.visibility_mode).toBe("show")

		neotree_hidden.toggle_visibility(test_root)
		expect(neotree_hidden.visibility_mode).toBe("hide")
	end)

	it("clears all hidden paths", function()
		neotree_hidden.toggle_path(test_root .. "/src/one.txt", test_root)
		neotree_hidden.toggle_path(test_root .. "/src/two.txt", test_root)

		expect(neotree_hidden.is_path_hidden(test_root .. "/src/one.txt", test_root)).toBe(true)
		expect(neotree_hidden.is_path_hidden(test_root .. "/src/two.txt", test_root)).toBe(true)

		neotree_hidden.clear_all(test_root)

		expect(neotree_hidden.is_path_hidden(test_root .. "/src/one.txt", test_root)).toBe(false)
		expect(neotree_hidden.is_path_hidden(test_root .. "/src/two.txt", test_root)).toBe(false)
	end)

	it("filters items in hide mode and marks items in show mode", function()
		local file_a = test_root .. "/a.txt"
		local file_b = test_root .. "/b.txt"

		neotree_hidden.toggle_path(file_b, test_root)

		-- Hide mode test
		neotree_hidden.visibility_mode = "hide"
		local items1 = {
			{ path = file_a, name = "a.txt" },
			{ path = file_b, name = "b.txt" },
		}
		neotree_hidden.filter_or_mark_items(items1, test_root)
		expect(#items1).toBe(1)
		expect(items1[1].path).toBe(file_a)

		-- Show mode test
		neotree_hidden.visibility_mode = "show"
		local items2 = {
			{ path = file_a, name = "a.txt" },
			{ path = file_b, name = "b.txt" },
		}
		neotree_hidden.filter_or_mark_items(items2, test_root)
		expect(#items2).toBe(2)
		expect(items2[2].filtered_by.custom_hidden).toBe(true)
	end)
end)
