-- ============================================================================
-- tests/spec/command_palette_spec.lua -- Command palette MRU history tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local cp = require("plugins.krs.tools.command_palette")

local original_history_file

describe("plugins.krs.tools.command_palette MRU history", function()
	beforeEach(function()
		original_history_file = cp.settings.history_file
		cp.settings.history_file = vim.fn.tempname() .. ".json"
	end)

	afterEach(function()
		if cp.settings.history_file then
			vim.fn.delete(cp.settings.history_file)
		end
		cp.settings.history_file = original_history_file
	end)

	it("starts with an empty history", function()
		expect(cp.load_history()).toEqual({})
	end)

	it("records command usage and persists to file", function()
		cp.record_command_use("Cmd A")
		expect(cp.load_history()).toEqual({ "Cmd A" })

		cp.record_command_use("Cmd B")
		expect(cp.load_history()).toEqual({ "Cmd B", "Cmd A" })

		-- Re-using Cmd A moves it back to top
		cp.record_command_use("Cmd A")
		expect(cp.load_history()).toEqual({ "Cmd A", "Cmd B" })
	end)

	it("sorts commands with most recent at top while preserving unvisited order", function()
		-- Setup dummy commands for testing order
		local saved_commands = vim.deepcopy(cp.commands)
		while #cp.commands > 0 do
			table.remove(cp.commands)
		end
		table.insert(cp.commands, { name = "Cmd 1", cmd = "Cmd1" })
		table.insert(cp.commands, { name = "Cmd 2", cmd = "Cmd2" })
		table.insert(cp.commands, { name = "Cmd 3", cmd = "Cmd3" })
		table.insert(cp.commands, { name = "Cmd 4", cmd = "Cmd4" })

		-- Initial sort matches declared order
		local names = {}
		for _, item in ipairs(cp.get_sorted_commands()) do
			table.insert(names, item.name)
		end
		expect(names).toEqual({ "Cmd 1", "Cmd 2", "Cmd 3", "Cmd 4" })

		-- Record usage of Cmd 3 and Cmd 2
		cp.record_command_use("Cmd 3")
		cp.record_command_use("Cmd 2")

		names = {}
		for _, item in ipairs(cp.get_sorted_commands()) do
			table.insert(names, item.name)
		end
		-- Expect Cmd 2 first (most recent), then Cmd 3, then Cmd 1, Cmd 4 (unvisited order)
		expect(names).toEqual({ "Cmd 2", "Cmd 3", "Cmd 1", "Cmd 4" })

		-- Clean up
		while #cp.commands > 0 do
			table.remove(cp.commands)
		end
		for _, cmd in ipairs(saved_commands) do
			table.insert(cp.commands, cmd)
		end
	end)

	it("clears history cleanly", function()
		cp.record_command_use("Cmd X")
		cp.clear_history()
		expect(cp.load_history()).toEqual({})
	end)
end)
