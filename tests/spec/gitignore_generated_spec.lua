-- ============================================================================
-- tests/spec/gitignore_generated_spec.lua -- .gitignore insertion test suite.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local type_injector = require("plugins.krs.tools.type_injector")

describe("plugins.krs.tools.type_injector.gitignore_generated", function()
	local temp_dir
	local gitignore_path

	beforeEach(function()
		temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		gitignore_path = temp_dir .. "/.gitignore"
	end)

	afterEach(function()
		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end
	end)

	it("creates .gitignore if missing and includes .krsnvim patterns", function()
		type_injector.gitignore_generated(temp_dir)

		expect(vim.fn.filereadable(gitignore_path)).toBe(1)
		local lines = vim.fn.readfile(gitignore_path)
		expect(lines).toEqual({
			".krsnvim/types.d.ts",
			".krsnvim/",
			"*.krsnvim",
		})
	end)

	it("prepends new entries at the beginning of an existing .gitignore", function()
		vim.fn.writefile({ "node_modules/", "dist/" }, gitignore_path)

		type_injector.gitignore_generated(temp_dir)

		local lines = vim.fn.readfile(gitignore_path)
		expect(lines).toEqual({
			".krsnvim/types.d.ts",
			".krsnvim/",
			"*.krsnvim",
			"",
			"node_modules/",
			"dist/",
		})
	end)

	it("does not duplicate entries already present in .gitignore", function()
		vim.fn.writefile({ "*.krsnvim", "node_modules/" }, gitignore_path)

		type_injector.gitignore_generated(temp_dir)

		local lines = vim.fn.readfile(gitignore_path)
		expect(lines).toEqual({
			".krsnvim/types.d.ts",
			".krsnvim/",
			"",
			"*.krsnvim",
			"node_modules/",
		})
	end)
end)
