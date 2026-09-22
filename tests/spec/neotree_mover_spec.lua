-- ============================================================================
-- tests/spec/neotree_mover_spec.lua -- Neo-tree Mover ("En la mano") tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local mover = require("plugins.krs.editor.neotree_mover")

describe("plugins.krs.editor.neotree_mover", function()
	local test_root = nil

	beforeEach(function()
		test_root = vim.fn.tempname()
		vim.fn.mkdir(test_root .. "/src/components", "p")
		vim.fn.mkdir(test_root .. "/src/utils", "p")
		vim.fn.mkdir(test_root .. "/docs", "p")

		-- Create dummy files
		local f1 = io.open(test_root .. "/src/components/Button.tsx", "w")
		if f1 then
			f1:write("// button")
			f1:close()
		end

		local f2 = io.open(test_root .. "/src/components/Card.tsx", "w")
		if f2 then
			f2:write("// card")
			f2:close()
		end

		local f3 = io.open(test_root .. "/src/utils/helpers.ts", "w")
		if f3 then
			f3:write("// helpers")
			f3:close()
		end

		mover.reset()
	end)

	afterEach(function()
		mover.reset()
		if test_root then
			vim.fn.delete(test_root, "rf")
		end
	end)

	it("normalizes paths properly", function()
		expect(mover.normalize_path("/foo/bar/")).toBe("/foo/bar")
		expect(mover.normalize_path("/foo//bar")).toBe("/foo/bar")
		expect(mover.normalize_path("")).toBe("")
		expect(mover.normalize_path(nil)).toBe("")
	end)

	it("resolves target directory from directory nodes and file nodes", function()
		local dir_node = {
			path = test_root .. "/src/utils",
			type = "directory",
		}
		expect(mover.resolve_target_dir(dir_node, nil)).toBe(mover.normalize_path(test_root .. "/src/utils"))

		local file_node = {
			path = test_root .. "/src/components/Button.tsx",
			type = "file",
		}
		expect(mover.resolve_target_dir(file_node, nil)).toBe(mover.normalize_path(test_root .. "/src/components"))
	end)

	it("picks up an item on first press (holding in hand)", function()
		expect(mover.is_holding()).toBe(false)

		local file_node = {
			path = test_root .. "/src/components/Button.tsx",
			name = "Button.tsx",
			type = "file",
		}

		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(true)

		local held = mover.get_held_item()
		expect(held ~= nil).toBe(true)
		expect(held.name).toBe("Button.tsx")
		expect(held.is_dir).toBe(false)
		expect(held.parent).toBe(mover.normalize_path(test_root .. "/src/components"))
	end)

	it("cancels pending move via cancel()", function()
		local file_node = {
			path = test_root .. "/src/components/Button.tsx",
			name = "Button.tsx",
			type = "file",
		}

		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(true)

		local cancelled = mover.cancel()
		expect(cancelled).toBe(true)
		expect(mover.is_holding()).toBe(false)
		expect(mover.get_held_item()).toBe(nil)
	end)

	it("cancels move when target is the same file or directory (same place)", function()
		local file_node = {
			path = test_root .. "/src/components/Button.tsx",
			name = "Button.tsx",
			type = "file",
		}

		-- 1st press: pick up
		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(true)

		-- 2nd press on the same file
		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(false)

		-- 1st press again
		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(true)

		-- 2nd press on another file in the same folder (Card.tsx)
		local same_folder_node = {
			path = test_root .. "/src/components/Card.tsx",
			name = "Card.tsx",
			type = "file",
		}
		mover.handle_move(same_folder_node, nil)
		expect(mover.is_holding()).toBe(false)

		-- Verify file was not deleted or moved
		expect(vim.fn.filereadable(test_root .. "/src/components/Button.tsx") == 1).toBe(true)
	end)

	it("prevents moving a directory into itself or its descendant", function()
		local dir_node = {
			path = test_root .. "/src",
			name = "src",
			type = "directory",
		}

		-- 1st press: pick up src
		mover.handle_move(dir_node, nil)
		expect(mover.is_holding()).toBe(true)

		-- 2nd press: target is a child of src (src/components)
		local child_node = {
			path = test_root .. "/src/components",
			name = "components",
			type = "directory",
		}
		mover.handle_move(child_node, nil)
		expect(mover.is_holding()).toBe(false)

		-- Verify src still exists
		expect(vim.fn.isdirectory(test_root .. "/src") == 1).toBe(true)
	end)

	it("prevents overwriting when destination has conflict", function()
		-- Create Button.tsx inside utils as well
		local f = io.open(test_root .. "/src/utils/Button.tsx", "w")
		if f then
			f:write("// existing")
			f:close()
		end

		local file_node = {
			path = test_root .. "/src/components/Button.tsx",
			name = "Button.tsx",
			type = "file",
		}

		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(true)

		-- Target is utils directory
		local target_dir_node = {
			path = test_root .. "/src/utils",
			type = "directory",
		}

		mover.handle_move(target_dir_node, nil)
		expect(mover.is_holding()).toBe(false)

		-- Verify original still exists
		expect(vim.fn.filereadable(test_root .. "/src/components/Button.tsx") == 1).toBe(true)
	end)

	it("successfully moves a file to another folder", function()
		local source_file = test_root .. "/src/components/Button.tsx"
		local dest_file = test_root .. "/src/utils/Button.tsx"

		local file_node = {
			path = source_file,
			name = "Button.tsx",
			type = "file",
		}

		-- 1st press: pick up
		mover.handle_move(file_node, nil)
		expect(mover.is_holding()).toBe(true)

		-- 2nd press: target is helpers.ts (which is inside utils)
		local target_node = {
			path = test_root .. "/src/utils/helpers.ts",
			name = "helpers.ts",
			type = "file",
		}
		mover.handle_move(target_node, nil)
		expect(mover.is_holding()).toBe(false)

		-- Check destination file exists and source is gone
		expect(vim.fn.filereadable(dest_file) == 1).toBe(true)
		expect(vim.fn.filereadable(source_file) == 0).toBe(true)
	end)

	it("successfully moves a folder to another folder", function()
		local source_dir = test_root .. "/src/components"
		local dest_dir = test_root .. "/docs/components"

		local dir_node = {
			path = source_dir,
			name = "components",
			type = "directory",
		}

		-- 1st press: pick up
		mover.handle_move(dir_node, nil)
		expect(mover.is_holding()).toBe(true)

		-- 2nd press: target is docs
		local target_node = {
			path = test_root .. "/docs",
			name = "docs",
			type = "directory",
		}
		mover.handle_move(target_node, nil)
		expect(mover.is_holding()).toBe(false)

		-- Check destination folder and contents exist
		expect(vim.fn.isdirectory(dest_dir) == 1).toBe(true)
		expect(vim.fn.filereadable(dest_dir .. "/Button.tsx") == 1).toBe(true)
		expect(vim.fn.isdirectory(source_dir) == 0).toBe(true)
	end)
end)
