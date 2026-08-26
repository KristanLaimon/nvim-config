-- ============================================================================
-- tests/krsnvimscript/libraries/fs_spec.lua -- Spec tests for krsnvim.fs module
-- ============================================================================
local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("krs.lib.krsnvim.fs")

describe("krsnvim.fs module", function()
	it("checks file and directory existence", function()
		expect(fs.exists(nil)).toBe(false)
		expect(fs.exists("")).toBe(false)
		expect(fs.exists("init.lua")).toBe(true)
		expect(fs.exists("non_existent_file_abc999.tmp")).toBe(false)
	end)

	it("creates directories, writes, reads, and lists files", function()
		local tmp_dir = vim.fn.tempname() .. "_krsfs_lib"
		expect(fs.exists(tmp_dir)).toBe(false)

		local ok_mkdir = fs.mkdir(tmp_dir)
		expect(ok_mkdir).toBe(true)
		expect(fs.exists(tmp_dir)).toBe(true)

		local tmp_file = tmp_dir .. "/sample.txt"
		fs.write(tmp_file, "krsnvim fs library content")
		expect(fs.exists(tmp_file)).toBe(true)

		local content = fs.read(tmp_file)
		expect(content).toBe("krsnvim fs library content")

		local list = fs.list(tmp_dir)
		expect(#list > 0).toBe(true)

		vim.fn.delete(tmp_dir, "rf")
	end)
end)
