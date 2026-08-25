-- ============================================================================
-- tests/spec/transpiler_commands_spec.lua -- Spec tests for KrsTranspile commands
-- ============================================================================
local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("krsnvim.fs")

-- Ensure keymaps and user commands are loaded
require("config.keymaps.krs")

describe("KrsTranspile commands and file resolution", function()
	it("registers user commands for transpilation", function()
		expect(vim.fn.exists(":KrsTranspile")).toBe(2)
		expect(vim.fn.exists(":KrsTranspileBoth")).toBe(2)
		expect(vim.fn.exists(":KrsTranspileSh")).toBe(2)
		expect(vim.fn.exists(":KrsTranspilePs1")).toBe(2)
		expect(vim.fn.exists(":KrsExport")).toBe(2)
	end)

	it("transpiles active .krsnvim buffer next to the file", function()
		local tmp = vim.fn.tempname() .. "_test.krsnvim"
		fs.write(tmp, 'local x = 10\nprint("Value:", x)')

		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp)
		vim.api.nvim_set_current_buf(buf)

		vim.cmd("KrsTranspileBoth")

		local sh_path = tmp:gsub("%.krsnvim$", ".sh")
		local ps1_path = tmp:gsub("%.krsnvim$", ".ps1")

		expect(fs.exists(sh_path)).toBe(true)
		expect(fs.exists(ps1_path)).toBe(true)

		-- Cleanup
		os.remove(tmp)
		if fs.exists(sh_path) then
			os.remove(sh_path)
		end
		if fs.exists(ps1_path) then
			os.remove(ps1_path)
		end
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("rejects non-krsnvim files without transpiling", function()
		local tmp = vim.fn.tempname() .. "_test.lua"
		fs.write(tmp, 'print("Lua file")')

		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp)
		vim.api.nvim_set_current_buf(buf)

		vim.cmd("KrsTranspileBoth")

		local sh_path = tmp:gsub("%.lua$", ".sh")
		expect(fs.exists(sh_path)).toBe(false)

		os.remove(tmp)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
