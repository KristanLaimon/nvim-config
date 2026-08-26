-- ============================================================================
-- tests/spec/git_diff_spec.lua -- Diff formatting for the preview pane.
-- ============================================================================
-- Two invariants matter here: the noise never reaches the buffer, and every
-- emitted line carries a kind, because the highlighter indexes them in parallel.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local diff = require("krs.git.diff")

local SAMPLE = {
	"diff --git a/init.lua b/init.lua",
	"index 1234567..89abcde 100644",
	"--- a/init.lua",
	"+++ b/init.lua",
	"@@ -1,3 +1,4 @@ local M = {}",
	" context line",
	"-removed line",
	"+added line",
}

describe("git diff format", function()
	it("drops the machine header lines", function()
		local lines = diff.format(SAMPLE, false)

		for _, line in ipairs(lines) do
			expect(line:match("^diff %-%-git")).toBeNil()
			expect(line:match("^index %x+")).toBeNil()
			expect(line:match("^%+%+%+ b/")).toBeNil()
		end
	end)

	it("keeps the content lines and tags each one", function()
		local lines, kinds = diff.format(SAMPLE, false)

		expect(#lines).toBe(#kinds)
		expect(lines).toContain(" context line")
		expect(lines).toContain("-removed line")
		expect(lines).toContain("+added line")
		expect(kinds).toContain("add")
		expect(kinds).toContain("delete")
		expect(kinds).toContain("context")
	end)

	it("replaces the @@ header with a labelled separator", function()
		local lines, kinds = diff.format(SAMPLE, false)

		expect(kinds[1]).toBe("header")
		expect(lines[2]).toContain("Hunk 1")
		expect(lines[2]).toContain("local M = {}")
	end)

	it("numbers multiple hunks", function()
		local lines = diff.format({
			"@@ -1,1 +1,1 @@",
			"+one",
			"@@ -9,1 +9,1 @@",
			"+two",
		}, false)

		expect(lines[1]).toContain("Hunk 1")
		expect(lines[3]).toContain("Hunk 2")
	end)

	it("renders an untracked file as all additions", function()
		local lines, kinds = diff.format({ "first", "second" }, true)

		expect(lines[2]).toBe("+ first")
		expect(lines[3]).toBe("+ second")
		expect(kinds[2]).toBe("add")
	end)

	it("splits embedded newlines, which nvim_buf_set_lines rejects", function()
		local lines = diff.format({ "one\ntwo" }, true)

		for _, line in ipairs(lines) do
			expect(line:find("\n")).toBeNil()
		end
	end)

	it("says so when a diff carries no visible change", function()
		local lines, kinds = diff.format({ "diff --git a/x b/x", "old mode 100644" }, false)

		expect(lines[2]).toBe(diff.empty_message)
		expect(kinds[2]).toBe("context")
	end)
end)

describe("git diff highlighting", function()
	it("marks each line with the group for its kind", function()
		diff.setup_highlights()

		local buf = vim.api.nvim_create_buf(false, true)
		local lines, kinds = diff.format(SAMPLE, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		diff.apply_highlights(buf, kinds)

		-- header gets one mark; add/delete get two (line background + prefix glyph);
		-- context gets none since it relies on the buffer's own syntax colours.
		local expected_marks = 0
		for _, kind in ipairs(kinds) do
			if kind == "header" then
				expected_marks = expected_marks + 1
			elseif kind == "add" or kind == "delete" then
				expected_marks = expected_marks + 2
			end
		end

		local marks = vim.api.nvim_buf_get_extmarks(buf, diff.namespace, 0, -1, {})
		expect(#marks).toBe(expected_marks)

		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)

describe("git diff language resolution", function()
	it("maps a filename to its tree-sitter language", function()
		expect(diff.get_file_language("init.lua")).toBe("lua")
		expect(diff.get_file_language("main.py")).toBe("python")
	end)

	it("returns nil for unknown or missing filenames", function()
		expect(diff.get_file_language(nil)).toBeNil()
		expect(diff.get_file_language("")).toBeNil()
		expect(diff.get_file_language("noext_weirdname_xyz")).toBeNil()
	end)
end)

describe("git diff tree-sitter highlighting", function()
	it("applies @-prefixed captures on top of diff highlights for a known language", function()
		diff.setup_highlights()

		local buf = vim.api.nvim_create_buf(false, true)
		local lines, kinds = diff.format({
			"@@ -1,1 +1,2 @@",
			"+local x = 1",
		}, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		diff.apply_highlights(buf, kinds, "init.lua")

		local marks = vim.api.nvim_buf_get_extmarks(buf, diff.ts_namespace, 0, -1, {})
		expect(#marks > 0).toBeTruthy()

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("skips tree-sitter highlighting when the filename has no known language", function()
		diff.setup_highlights()

		local buf = vim.api.nvim_create_buf(false, true)
		local lines, kinds = diff.format(SAMPLE, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		diff.apply_highlights(buf, kinds, "noext_weirdname_xyz")

		local marks = vim.api.nvim_buf_get_extmarks(buf, diff.ts_namespace, 0, -1, {})
		expect(#marks).toBe(0)

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("clears previous tree-sitter marks before applying new ones", function()
		diff.setup_highlights()

		local buf = vim.api.nvim_create_buf(false, true)
		local lines, kinds = diff.format({
			"@@ -1,1 +1,2 @@",
			"+local x = 1",
		}, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		diff.apply_highlights(buf, kinds, "init.lua")
		diff.apply_highlights(buf, kinds, nil)

		local marks = vim.api.nvim_buf_get_extmarks(buf, diff.ts_namespace, 0, -1, {})
		expect(#marks).toBe(0)

		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)

describe("side-by-side git diff format", function()
	it("formats raw diff into dual left (before) and right (after) lines", function()
		local left_lines, left_kinds, right_lines, right_kinds = diff.format_side_by_side_dual(SAMPLE, false)

		expect(#left_lines).toBe(#right_lines)
		expect(#left_kinds).toBe(#right_kinds)

		-- Hunk header
		expect(left_kinds[1]).toBe("header")
		expect(right_kinds[1]).toBe("header")

		-- Deletions on left side (kind "delete"), additions on right side (kind "add")
		expect(left_lines).toContain("-removed line")
		expect(right_lines).toContain("+added line")

		local del_idx, add_idx
		for idx, k in ipairs(left_kinds) do
			if k == "delete" then
				del_idx = idx
			end
		end
		for idx, k in ipairs(right_kinds) do
			if k == "add" then
				add_idx = idx
			end
		end

		expect(del_idx).toBeDefined()
		expect(add_idx).toBeDefined()
		expect(left_kinds[del_idx]).toBe("delete")
		expect(right_kinds[add_idx]).toBe("add")
	end)

	it("formats untracked file as filler on left and additions on right", function()
		local left_lines, left_kinds, right_lines, right_kinds = diff.format_side_by_side_dual({ "line1", "line2" }, true)

		expect(#left_lines).toBe(#right_lines)
		expect(left_kinds[2]).toBe("filler")
		expect(right_kinds[2]).toBe("add")
		expect(right_lines[2]).toBe("+ line1")
	end)

	it("formats side-by-side dual column into single combined buffer lines", function()
		local combined, l_kinds, r_kinds, col_w = diff.format_side_by_side_single(SAMPLE, false, 80)

		expect(#combined).toBeGreaterThan(0)
		expect(col_w).toBeGreaterThan(15)
		local has_sep = false
		for _, line in ipairs(combined) do
			if line:find("│") then
				has_sep = true
				break
			end
		end
		expect(has_sep).toBeTruthy()
	end)

	it("applies highlights for side-by-side dual buffers", function()
		diff.setup_highlights()
		local left_buf = vim.api.nvim_create_buf(false, true)
		local right_buf = vim.api.nvim_create_buf(false, true)

		local l_lines, l_kinds, r_lines, r_kinds = diff.format_side_by_side_dual(SAMPLE, false)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, l_lines)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, r_lines)

		diff.apply_highlights_side_by_side_dual(left_buf, l_kinds, right_buf, r_kinds, "init.lua")

		local l_marks = vim.api.nvim_buf_get_extmarks(left_buf, diff.namespace, 0, -1, {})
		local r_marks = vim.api.nvim_buf_get_extmarks(right_buf, diff.namespace, 0, -1, {})

		expect(#l_marks).toBeGreaterThan(0)
		expect(#r_marks).toBeGreaterThan(0)

		vim.api.nvim_buf_delete(left_buf, { force = true })
		vim.api.nvim_buf_delete(right_buf, { force = true })
	end)

	it("formats multi-file diffs with file header banners for each file", function()
		local MULTI_SAMPLE = {
			"diff --git a/foo.lua b/foo.lua",
			"index 1111111..2222222 100644",
			"--- a/foo.lua",
			"+++ b/foo.lua",
			"@@ -1,1 +1,1 @@",
			"-foo old",
			"+foo new",
			"diff --git a/bar.lua b/bar.lua",
			"index 3333333..4444444 100644",
			"--- a/bar.lua",
			"+++ b/bar.lua",
			"@@ -1,1 +1,1 @@",
			"-bar old",
			"+bar new",
		}

		local l_lines, _, r_lines, _ = diff.format_side_by_side_dual(MULTI_SAMPLE, false)
		local found_foo, found_bar = false, false
		for _, line in ipairs(r_lines) do
			if line:find("foo.lua", 1, true) then
				found_foo = true
			end
			if line:find("bar.lua", 1, true) then
				found_bar = true
			end
		end

		expect(found_foo).toBeTruthy()
		expect(found_bar).toBeTruthy()
	end)
end)
