-- ============================================================================
-- tests/spec/workspaces_spec.lua -- Workspaces manager tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local ws = require("plugins.krs.tools.workspaces")

describe("plugins.krs.tools.workspaces", function()
	local temp_dir
	local orig_storage_dir

	beforeEach(function()
		temp_dir = vim.fn.tempname()
		orig_storage_dir = ws.settings.storage_dir
		ws.settings.storage_dir = temp_dir
	end)

	afterEach(function()
		ws.settings.storage_dir = orig_storage_dir
		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end
	end)

	it("creates a new workspace via M.new_workspace", function()
		local orig_input = vim.ui.input
		vim.ui.input = function(_, on_confirm)
			on_confirm("My Custom Workspace")
		end

		local called = false
		ws.new_workspace(function()
			called = true
		end)

		vim.ui.input = orig_input

		expect(called).toBe(true)
		-- save_workspace notifies and saves file
		local index_path = temp_dir .. "/index.json"
		expect(vim.fn.filereadable(index_path)).toBe(1)
	end)

	it("overwrites existing workspace when save_workspace is called with a name", function()
		ws.save_workspace("Original Name")
		ws.save_workspace("Original Name")

		local store = require("krs.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(#index).toBe(1)
		expect(index[1].name).toBe("Original Name")
	end)

	it("renames an existing workspace", function()
		ws.save_workspace("Old Workspace Name")

		local orig_input = vim.ui.input
		vim.ui.input = function(_, on_confirm)
			on_confirm("Renamed Workspace Name")
		end

		ws.rename_workspace("Old Workspace Name")

		vim.ui.input = orig_input

		local store = require("krs.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(#index).toBe(1)
		expect(index[1].name).toBe("Renamed Workspace Name")
	end)

	it("deletes a workspace when confirmed", function()
		ws.save_workspace("To Delete")

		local orig_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			return 1 -- Yes
		end

		local called = false
		ws.delete_workspace("To Delete", function()
			called = true
		end)

		vim.fn.confirm = orig_confirm

		expect(called).toBe(true)
		local store = require("krs.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(#index).toBe(0)
	end)
end)
