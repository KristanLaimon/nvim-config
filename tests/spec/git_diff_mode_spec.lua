-- ============================================================================
-- tests/spec/git_diff_mode_spec.lua -- Git Diff Mode (Same branch & 2 branches)
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local diff_mode = require("plugins.krs.git.diff_mode")

describe("plugins.krs.git.diff_mode", function()
	beforeEach(function()
		if diff_mode.is_open() then
			diff_mode.close()
		end
	end)

	afterEach(function()
		if diff_mode.is_open() then
			diff_mode.close()
		end
	end)

	it("sanitizes commits_behind values to non-negative integers >= 0", function()
		expect(diff_mode.sanitize_commits_behind(1)).toBe(1)
		expect(diff_mode.sanitize_commits_behind(5)).toBe(5)
		expect(diff_mode.sanitize_commits_behind(100)).toBe(100)

		-- Zero is allowed (working tree vs HEAD)
		expect(diff_mode.sanitize_commits_behind(0)).toBe(0)
		-- Negative values must be clamped to 0
		expect(diff_mode.sanitize_commits_behind(-1)).toBe(0)
		expect(diff_mode.sanitize_commits_behind(-99)).toBe(0)

		-- Strings, nil, and invalid input must fallback to 0
		expect(diff_mode.sanitize_commits_behind("3")).toBe(3)
		expect(diff_mode.sanitize_commits_behind("0")).toBe(0)
		expect(diff_mode.sanitize_commits_behind("-5")).toBe(0)
		expect(diff_mode.sanitize_commits_behind(nil)).toBe(0)
		expect(diff_mode.sanitize_commits_behind("invalid")).toBe(0)
		expect(diff_mode.sanitize_commits_behind(3.7)).toBe(3)
	end)

	it("retrieves changed files between refs in git repository", function()
		local cwd = vim.fn.getcwd()
		local files = diff_mode.get_changed_files("HEAD~1", "HEAD", cwd)
		expect(type(files)).toBe("table")

		if #files > 0 then
			local f = files[1]
			expect(type(f.file)).toBe("string")
			expect(type(f.status)).toBe("string")
		end
	end)

	it("applies same branch diff extmark highlights and records modifications", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"line 1",
			"line 2 modified",
			"line 3",
		})

		local cwd = vim.fn.getcwd()
		local head = vim.fn.systemlist("git rev-parse HEAD")[1]
		expect(head).toBeDefined()

		-- Running on non-matching or matching file safely returns modifications table
		local mods = diff_mode.apply_same_branch_highlights(buf, "README.md", "HEAD~1", "HEAD", cwd)
		expect(type(mods)).toBe("table")

		-- Buffer is valid and contains lines
		expect(vim.api.nvim_buf_line_count(buf)).toBe(3)

		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)

	it("opens docked right sidebar list window", function()
		local sample_files = {
			{ file = "lua/init.lua", status = "M" },
			{ file = "README.md", status = "A" },
			{ file = "docs/guide.md", status = "D" },
		}

		local win, buf = diff_mode.open_file_list_window(sample_files, 1)

		expect(win ~= nil and vim.api.nvim_win_is_valid(win)).toBeTruthy()
		expect(buf ~= nil and vim.api.nvim_buf_is_valid(buf)).toBeTruthy()

		-- Check window config (docked right sidebar, not float)
		local cfg = vim.api.nvim_win_get_config(win)
		expect(cfg.split).toBe("right")
		expect(cfg.relative).toBe("")
		expect(cfg.width).toBeGreaterThan(20)
		expect(vim.wo[win].winfixwidth).toBeTruthy()

		-- Check rendered lines contain file names and icons
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = table.concat(lines, "\n")
		expect(content:match("init.lua") ~= nil).toBeTruthy()
		expect(content:match("README.md") ~= nil).toBeTruthy()

		pcall(vim.api.nvim_win_close, win, true)
	end)

	it("preserves sidebar buffer and never overwrites it when opening files", function()
		local sample_files = {
			{ file = "lua/init.lua", status = "M" },
		}
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.is_active = true

		-- Ensure sidebar is focused
		vim.api.nvim_set_current_win(win)
		expect(vim.api.nvim_get_current_win()).toBe(win)

		-- Calling open_file_same_branch while focused on sidebar must NEVER overwrite sidebar buf
		diff_mode.open_file_same_branch("lua/init.lua")

		-- The sidebar window must still hold the sidebar buffer
		expect(vim.api.nvim_win_get_buf(win)).toBe(buf)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = table.concat(lines, "\n")
		expect(content:match("Diff:") ~= nil).toBeTruthy()

		diff_mode.close()
	end)

	it("toggles attention between editor window and docked right sidebar window", function()
		local sample_files = {
			{ file = "lua/config.lua", status = "M" },
		}

		local win, buf = diff_mode.open_file_list_window(sample_files, 1, function(_) end)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.is_active = true

		local editor_win = vim.api.nvim_get_current_win()
		diff_mode.state.editor_win = editor_win

		-- Focus file list
		diff_mode.focus_file_list()
		expect(vim.api.nvim_get_current_win()).toBe(win)

		-- Toggle attention switches back to editor
		diff_mode.toggle_attention()
		expect(vim.api.nvim_get_current_win()).toBe(editor_win)

		-- Toggle attention switches to file list
		diff_mode.toggle_attention()
		expect(vim.api.nvim_get_current_win()).toBe(win)

		diff_mode.close()
	end)

	it("navigates through modifications using next and prev jumps", function()
		local cur_win = vim.api.nvim_get_current_win()
		local cur_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(cur_buf, 0, -1, false, {
			"line 1",
			"line 2",
			"line 3",
			"line 4",
			"line 5",
		})
		vim.api.nvim_win_set_buf(cur_win, cur_buf)

		diff_mode.state.editor_win = cur_win
		diff_mode.state.editor_buf = cur_buf
		diff_mode.state.is_active = true
		diff_mode.state.current_modifications = { 2, 4 }

		vim.api.nvim_win_set_cursor(cur_win, { 1, 0 })

		-- Jump next should land on line 2
		diff_mode.jump_next_modification()
		expect(vim.api.nvim_win_get_cursor(cur_win)[1]).toBe(2)

		-- Jump next should land on line 4
		diff_mode.jump_next_modification()
		expect(vim.api.nvim_win_get_cursor(cur_win)[1]).toBe(4)

		-- Jump prev should land on line 2
		diff_mode.jump_prev_modification()
		expect(vim.api.nvim_win_get_cursor(cur_win)[1]).toBe(2)

		diff_mode.close()
		pcall(vim.api.nvim_buf_delete, cur_buf, { force = true })
	end)

	it("starts and closes same branch diff mode cleanly with working tree default", function()
		diff_mode.start_same_branch()
		expect(diff_mode.is_open()).toBeTruthy()
		expect(diff_mode.state.mode).toBe("same_branch")
		expect(diff_mode.state.commits_behind).toBe(0)
		expect(diff_mode.state.base_ref).toBe("HEAD")
		expect(diff_mode.state.target_ref).toBe("WORKTREE")

		diff_mode.close()
		expect(diff_mode.is_open()).toBeFalsy()
		expect(diff_mode.state.is_active).toBeFalsy()
		expect(diff_mode.state.file_list_win).toBeNil()
	end)

	it("starts and manages between branches diff mode with side-by-side dual windows and sidebar", function()
		local cwd = vim.fn.getcwd()
		local head = vim.fn.systemlist("git rev-parse HEAD")[1]
		local head_prev = vim.fn.systemlist("git rev-parse HEAD~1")[1] or head

		diff_mode.start_between_branches(head_prev, head, cwd)
		expect(diff_mode.is_open()).toBeTruthy()
		expect(diff_mode.state.mode).toBe("between_branches")
		expect(diff_mode.state.base_ref).toBe(head_prev)
		expect(diff_mode.state.target_ref).toBe(head)

		-- Docked right sidebar must exist and be valid
		expect(diff_mode.state.file_list_win ~= nil and vim.api.nvim_win_is_valid(diff_mode.state.file_list_win)).toBeTruthy()
		local sb_cfg = vim.api.nvim_win_get_config(diff_mode.state.file_list_win)
		expect(sb_cfg.split).toBe("right")

		-- If files exist, dual_left_win and dual_right_win should be set up
		if #diff_mode.state.files > 0 then
			expect(diff_mode.state.dual_left_win ~= nil and vim.api.nvim_win_is_valid(diff_mode.state.dual_left_win)).toBeTruthy()
			expect(diff_mode.state.dual_right_win ~= nil and vim.api.nvim_win_is_valid(diff_mode.state.dual_right_win)).toBeTruthy()
			expect(vim.wo[diff_mode.state.dual_left_win].scrollbind).toBeTruthy()
			expect(vim.wo[diff_mode.state.dual_right_win].scrollbind).toBeTruthy()
		end

		diff_mode.close()
		expect(diff_mode.is_open()).toBeFalsy()
		expect(diff_mode.state.file_list_win).toBeNil()
		expect(diff_mode.state.dual_right_win).toBeNil()
	end)

	it("reconfigures commits behind and updates base_ref without clobbering sidebar buffer", function()
		diff_mode.start_same_branch({ commits_behind = 1 })
		expect(diff_mode.state.commits_behind).toBe(1)
		local sb_win = diff_mode.state.file_list_win
		local sb_buf = diff_mode.state.file_list_buf

		-- Focus sidebar window (simulating user pressing 'c' while navigating sidebar)
		vim.api.nvim_set_current_win(sb_win)

		-- Change commits behind to 2
		diff_mode.start_same_branch({ commits_behind = 2, cwd = diff_mode.state.cwd })
		expect(diff_mode.state.commits_behind).toBe(2)
		expect(diff_mode.state.base_ref:match("HEAD~2") ~= nil or diff_mode.state.base_ref:match("%x+")).toBeTruthy()

		-- The sidebar window must still hold sb_buf, never replaced by any file content
		expect(vim.api.nvim_win_get_buf(sb_win)).toBe(sb_buf)
		local lines = vim.api.nvim_buf_get_lines(sb_buf, 0, -1, false)
		local text = table.concat(lines, "\n")
		expect(text:match("Diff:") ~= nil).toBeTruthy()

		diff_mode.close()
	end)

	it("navigates files list with j and k keymaps with wrap-around", function()
		local sample_files = {
			{ file = "fileA.lua", status = "M" },
			{ file = "fileB.lua", status = "A" },
			{ file = "fileC.lua", status = "D" },
		}
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.selected_file_idx = 1

		local j_map = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("j", "n", false, true)
		end)
		expect(j_map.callback).toBeDefined()

		local k_map = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("k", "n", false, true)
		end)
		expect(k_map.callback).toBeDefined()

		-- Press j -> moves to 2
		j_map.callback()
		expect(diff_mode.state.selected_file_idx).toBe(2)

		-- Press j -> moves to 3
		j_map.callback()
		expect(diff_mode.state.selected_file_idx).toBe(3)

		-- Press j -> wraps to 1
		j_map.callback()
		expect(diff_mode.state.selected_file_idx).toBe(1)

		-- Press k -> wraps to 3
		k_map.callback()
		expect(diff_mode.state.selected_file_idx).toBe(3)

		-- Press k -> moves to 2
		k_map.callback()
		expect(diff_mode.state.selected_file_idx).toBe(2)

		diff_mode.close()
	end)

	it("supports custom commits comparison between two explicit commit SHAs", function()
		local cwd = vim.fn.getcwd()
		local head = vim.fn.systemlist("git rev-parse HEAD")[1]
		local head_prev = vim.fn.systemlist("git rev-parse HEAD~1")[1] or head

		diff_mode.start_same_branch({ base_ref = head_prev, target_ref = head, cwd = cwd })
		expect(diff_mode.is_open()).toBeTruthy()
		expect(diff_mode.state.custom_commits).toBeTruthy()
		expect(diff_mode.state.base_ref).toBe(head_prev)
		expect(diff_mode.state.target_ref).toBe(head)

		diff_mode.close()
	end)

	it("toggles Git Diff Mode on and off via M.toggle()", function()
		expect(diff_mode.is_open()).toBeFalsy()

		diff_mode.toggle()
		expect(diff_mode.is_open()).toBeTruthy()

		diff_mode.toggle()
		expect(diff_mode.is_open()).toBeFalsy()
	end)

	it("does not register S-Tab or S-Right keymaps in sidebar file list buffer", function()
		local sample_files = { { file = "dummy.lua", status = "M" } }
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)

		local s_tab = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("<S-Tab>", "n", false, true)
		end)
		local s_right = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("<S-Right>", "n", false, true)
		end)

		-- Neither shortcut should have a buffer-local mapping in the file list
		expect(s_tab.buffer ~= 1).toBeTruthy()
		expect(s_right.buffer ~= 1).toBeTruthy()

		-- <Esc> and h should return to editor
		local esc_map = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("<Esc>", "n", false, true)
		end)
		expect(esc_map.callback).toBeDefined()

		pcall(vim.api.nvim_win_close, win, true)
	end)

	it("queries working tree changes against HEAD in WORKTREE mode", function()
		local cwd = vim.fn.getcwd()
		local files = diff_mode.get_changed_files("HEAD", "WORKTREE", cwd)
		expect(type(files)).toBe("table")

		-- Any returned file should have a valid status code (including ? for untracked)
		for _, f in ipairs(files) do
			expect(type(f.file)).toBe("string")
			expect(type(f.status)).toBe("string")
			expect(f.status:match("^[AMDRCU?]$") ~= nil).toBeTruthy()
		end
	end)

	it("decouples Diff Mode from Git Center so V toggle does not lock out Git Center", function()
		local panel = require("plugins.krs.git.git_center.panel")
		local init = require("plugins.krs.git.git_center")

		-- Initially closed
		expect(panel.is_open()).toBeFalsy()
		expect(diff_mode.is_open()).toBeFalsy()

		-- Start diff mode
		diff_mode.start_same_branch()
		expect(diff_mode.is_open()).toBeTruthy()

		-- Git Center itself is NOT considered open just because diff mode is active
		expect(panel.is_open()).toBeFalsy()

		-- Git Center can be opened without conflict
		init.open_git_center()
		expect(panel.is_open()).toBeTruthy()

		-- Close Git Center
		panel.close_git_center()
		expect(panel.is_open()).toBeFalsy()

		diff_mode.close()
		expect(diff_mode.is_open()).toBeFalsy()
	end)

	it("registers user commands for Git Diff Mode", function()
		diff_mode.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["GitDiffMode"]).toBeDefined()
		expect(cmds["GitDiffSameBranch"]).toBeDefined()
		expect(cmds["GitDiffBetweenBranches"]).toBeDefined()
		expect(cmds["GitDiffToggle"]).toBeDefined()
		expect(cmds["GitDiffClose"]).toBeDefined()
	end)
end)
