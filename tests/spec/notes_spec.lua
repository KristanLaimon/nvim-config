-- ============================================================================
-- tests/spec/notes_spec.lua -- Notes manager & dashboard integration tests
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local notes = require("plugins.krs.tools.notes")

describe("plugins.krs.tools.notes", function()
	local original_config_file
	local test_config_file
	local test_dir

	beforeEach(function()
		original_config_file = notes.config_file
		test_config_file = vim.fn.tempname() .. "_notes_config.json"
		notes.config_file = test_config_file

		test_dir = vim.fn.tempname() .. "_test_notes_dir"
		vim.fn.mkdir(test_dir, "p")
	end)

	afterEach(function()
		notes.config_file = original_config_file
		pcall(vim.fn.delete, test_config_file)
		pcall(vim.fn.delete, test_dir, "rf")
	end)

	it("returns nil when notes folder is not set or file is empty", function()
		local dir = notes.get_notes_dir()
		expect(dir).toBeNil()
	end)

	it("rejects non-existent directory when setting notes folder", function()
		local fake_dir = "/non/existent/path/for/krs/notes/12345"
		local ok, err = notes.set_notes_dir(fake_dir)
		expect(ok).toBeFalsy()
		expect(err:match("does not exist") ~= nil).toBeTruthy()
		expect(notes.get_notes_dir()).toBeNil()
	end)

	it("rejects empty directory string", function()
		local ok, err = notes.set_notes_dir("")
		expect(ok).toBeFalsy()
		expect(err:match("empty") ~= nil).toBeTruthy()
	end)

	it("saves valid directory and retrieves it via get_notes_dir()", function()
		local ok, res = notes.set_notes_dir(test_dir)
		expect(ok).toBeTruthy()
		expect(type(res)).toBe("string")

		local loaded = notes.get_notes_dir()
		expect(loaded).toBeDefined()
		-- Normalize path comparisons
		local path_util = require("krs.core.path")
		expect(path_util.equals(loaded, test_dir)).toBeTruthy()
	end)

	it("returns nil if saved directory was deleted on disk", function()
		local ok = notes.set_notes_dir(test_dir)
		expect(ok).toBeTruthy()
		expect(notes.get_notes_dir()).toBeDefined()

		-- Delete the directory from disk
		vim.fn.delete(test_dir, "rf")
		expect(notes.get_notes_dir()).toBeNil()
	end)

	it("clears notes directory on clear_notes_dir()", function()
		notes.set_notes_dir(test_dir)
		expect(notes.get_notes_dir()).toBeDefined()

		notes.clear_notes_dir()
		expect(notes.get_notes_dir()).toBeNil()
	end)

	it("registers Notes, NotesChangeFolder, and NotesSetFolder user commands", function()
		notes.setup()
		expect(vim.fn.exists(":Notes")).toBe(2)
		expect(vim.fn.exists(":NotesChangeFolder")).toBe(2)
		expect(vim.fn.exists(":NotesSetFolder")).toBe(2)
	end)

	it("includes Notes in command palette commands list", function()
		local cp = require("plugins.krs.tools.command_palette")
		local has_notes = false
		local has_change = false
		for _, cmd in ipairs(cp.commands) do
			if cmd.cmd == "Notes" then
				has_notes = true
			end
			if cmd.cmd == "NotesChangeFolder" then
				has_change = true
			end
		end
		expect(has_notes).toBeTruthy()
		expect(has_change).toBeTruthy()
	end)

	it("allows programmatic folder selection callback", function()
		local selected = nil
		local ok_called = false
		notes.select_notes_folder({ initial_dir = test_dir }, function(dir)
			selected = dir
			ok_called = true
		end)

		expect(type(notes.select_notes_folder)).toBe("function")
		expect(selected).toBeNil()
		expect(ok_called).toBeFalsy()
	end)
end)
