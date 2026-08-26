-- tests/spec/leader_keymaps_spec.lua -- Enforces leader keymaps non-triggerability in insert & terminal modes.

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("leader keymaps scoping and protection", function()
	it("ensures leader keymaps are NOT bound in insert or terminal modes", function()
		require("keymaps")
		local registry = require("krs.core.keymap_registry")
		registry.install()

		-- Test setting a leader mapping for all modes
		vim.keymap.set({ "n", "i", "t", "v" }, "<leader>test_leader_cmd", function() end, { desc = "Test Leader" })

		local in_normal = vim.fn.maparg("<leader>test_leader_cmd", "n") ~= ""
		local in_insert = vim.fn.maparg("<leader>test_leader_cmd", "i") ~= ""
		local in_term = vim.fn.maparg("<leader>test_leader_cmd", "t") ~= ""
		local in_visual = vim.fn.maparg("<leader>test_leader_cmd", "v") ~= ""

		expect(in_normal).toBe(true)
		expect(in_visual).toBe(true)
		expect(in_insert).toBe(false)
		expect(in_term).toBe(false)
	end)

	it("verifies global leader mappings (e.g. <leader>fw, <leader>ta) do not exist in insert mode", function()
		require("keymaps")

		local wsl_insert = vim.fn.maparg("<leader>fw", "i") ~= ""
		local wsl_term = vim.fn.maparg("<leader>fw", "t") ~= ""

		expect(wsl_insert).toBe(false)
		expect(wsl_term).toBe(false)
	end)
end)
