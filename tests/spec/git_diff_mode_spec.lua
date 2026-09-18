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

	it("completely clears diff extmark highlights and virtual lines from all open buffers when closing", function()
		local b1 = vim.api.nvim_create_buf(false, true)
		local b2 = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "line1", "line2", "line3" })
		vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "code1", "code2", "code3" })

		-- Apply mock highlights using M.namespace on both buffers
		vim.api.nvim_buf_set_extmark(b1, diff_mode.namespace, 0, 0, {
			line_hl_group = "GitCenterDiffAdd",
			virt_lines = { { { "  - deleted line", "GitCenterDiffDelete" } } },
		})
		vim.api.nvim_buf_set_extmark(b2, diff_mode.namespace, 1, 0, {
			line_hl_group = "GitCenterDiffAdd",
			virt_lines = { { { "  - deleted line 2", "GitCenterDiffDelete" } } },
		})

		diff_mode.state.highlighted_bufs = { [b1] = true, [b2] = true }

		expect(#vim.api.nvim_buf_get_extmarks(b1, diff_mode.namespace, 0, -1, {})).toBe(1)
		expect(#vim.api.nvim_buf_get_extmarks(b2, diff_mode.namespace, 0, -1, {})).toBe(1)

		diff_mode.close()

		-- Must be completely purged from all buffers
		expect(#vim.api.nvim_buf_get_extmarks(b1, diff_mode.namespace, 0, -1, {})).toBe(0)
		expect(#vim.api.nvim_buf_get_extmarks(b2, diff_mode.namespace, 0, -1, {})).toBe(0)

		pcall(vim.api.nvim_buf_delete, b1, { force = true })
		pcall(vim.api.nvim_buf_delete, b2, { force = true })
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

	it("keeps focus in diff sidebar window when selecting a file from list", function()
		local sample_files = {
			{ file = "lua/plugins/krs/git/diff_mode.lua", status = "M" },
			{ file = "README.md", status = "M" },
		}
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.is_active = true
		diff_mode.state.cwd = vim.fn.getcwd()

		local editor_win = vim.api.nvim_get_current_win()
		diff_mode.state.editor_win = editor_win

		-- Focus sidebar window
		vim.api.nvim_set_current_win(win)
		expect(vim.api.nvim_get_current_win()).toBe(win)

		-- Trigger <CR> map in sidebar
		local cr_map = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("<CR>", "n", false, true)
		end)
		expect(cr_map.callback).toBeDefined()
		cr_map.callback()

		-- Must remain focused on the diff sidebar window, NOT automatically jumping to code center
		expect(vim.api.nvim_get_current_win()).toBe(win)
		expect(diff_mode.state.active_file).toBe("lua/plugins/krs/git/diff_mode.lua")

		diff_mode.close()
	end)

	it("registers diff jump shortcuts available only in diff sidebar buffer", function()
		local sample_files = {
			{ file = "test_jump.lua", status = "M" },
		}
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.is_active = true

		-- Check buffer-local keymaps for next diff
		for _, key in ipairs({ "J", "n", "]c", "]d", "]" }) do
			local map = vim.api.nvim_buf_call(buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			expect(map.buffer).toBe(1)
			expect(map.callback).toBeDefined()
		end

		-- Check buffer-local keymaps for prev diff
		for _, key in ipairs({ "K", "p", "N", "[c", "[d", "[" }) do
			local map = vim.api.nvim_buf_call(buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			expect(map.buffer).toBe(1)
			expect(map.callback).toBeDefined()
		end

		diff_mode.close()
	end)

	it("jumps modifications in editor window from sidebar without losing sidebar focus", function()
		local editor_win = vim.api.nvim_get_current_win()
		local editor_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, {
			"line 1",
			"line 2",
			"line 3",
			"line 4",
			"line 5",
		})
		vim.api.nvim_win_set_buf(editor_win, editor_buf)

		local sample_files = { { file = "dummy.lua", status = "M" } }
		local sb_win, sb_buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = sb_win
		diff_mode.state.file_list_buf = sb_buf
		diff_mode.state.editor_win = editor_win
		diff_mode.state.is_active = true
		diff_mode.state.current_modifications = { 2, 4 }

		-- Focus sidebar
		vim.api.nvim_set_current_win(sb_win)
		expect(vim.api.nvim_get_current_win()).toBe(sb_win)
		vim.api.nvim_win_set_cursor(editor_win, { 1, 0 })

		-- Trigger J (jump next) from sidebar
		local j_map = vim.api.nvim_buf_call(sb_buf, function()
			return vim.fn.maparg("J", "n", false, true)
		end)
		j_map.callback()

		-- Editor cursor must move to line 2, but current window must STAY sb_win!
		expect(vim.api.nvim_win_get_cursor(editor_win)[1]).toBe(2)
		expect(vim.api.nvim_get_current_win()).toBe(sb_win)

		-- Trigger J again -> moves to line 4
		j_map.callback()
		expect(vim.api.nvim_win_get_cursor(editor_win)[1]).toBe(4)
		expect(vim.api.nvim_get_current_win()).toBe(sb_win)

		-- Trigger K (jump prev) from sidebar -> moves back to line 2
		local k_map = vim.api.nvim_buf_call(sb_buf, function()
			return vim.fn.maparg("K", "n", false, true)
		end)
		k_map.callback()
		expect(vim.api.nvim_win_get_cursor(editor_win)[1]).toBe(2)
		expect(vim.api.nvim_get_current_win()).toBe(sb_win)

		diff_mode.close()
		pcall(vim.api.nvim_buf_delete, editor_buf, { force = true })
	end)

	it("computes diff stats including total diffs and file subtotals", function()
		local cwd = vim.fn.getcwd()
		local files = {
			{ file = "lua/plugins/krs/git/diff_mode.lua", status = "M" },
		}
		local stats = diff_mode.compute_diff_stats("HEAD~1", "HEAD", cwd, files)
		expect(type(stats)).toBe("table")
		expect(type(stats.total_add)).toBe("number")
		expect(type(stats.total_del)).toBe("number")
		expect(type(stats.per_file)).toBe("table")

		-- Get file subtotal stat
		local file_stat = diff_mode.get_file_stat(stats, "lua/plugins/krs/git/diff_mode.lua", cwd)
		expect(type(file_stat.add)).toBe("number")
		expect(type(file_stat.del)).toBe("number")
	end)

	it("renders total diffs and viewing file subtotal in diff bar bottom side", function()
		local sample_files = {
			{ file = "fileA.lua", status = "M" },
			{ file = "fileB.lua", status = "A" },
		}
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.is_active = true
		diff_mode.state.active_file = "fileA.lua"

		-- Inject stats into state
		diff_mode.state.stats = {
			total_add = 42,
			total_del = 15,
			per_file = {
				["fileA.lua"] = { add = 30, del = 10 },
				["fileB.lua"] = { add = 12, del = 5 },
			},
		}

		-- Re-render
		diff_mode.open_file_list_window(sample_files, 1)

		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = table.concat(lines, "\n")

		-- Check Total stats rendered
		expect(content:match("Total:%s+%+42%s+%-15") ~= nil).toBeTruthy()
		-- Check Subtotal stats rendered for active file (fileA.lua)
		expect(content:match("Subtotal:%s+%+30%s+%-10") ~= nil).toBeTruthy()
		expect(content:match("fileA.lua") ~= nil).toBeTruthy()

		-- Check window statusline
		local stl = vim.wo[win].statusline
		expect(stl:match("Total: %+42 %-15") ~= nil).toBeTruthy()
		expect(stl:match("Subtotal: %+30 %-10") ~= nil).toBeTruthy()

		diff_mode.close()
	end)

	it("computes change counts across diff hunks", function()
		local cwd = vim.fn.getcwd()
		local files = {
			{ file = "lua/plugins/krs/git/diff_mode.lua", status = "M" },
		}
		local counts = diff_mode.compute_change_counts("HEAD~1", "HEAD", cwd, files)
		expect(type(counts)).toBe("table")
		expect(type(counts.total)).toBe("number")
		expect(type(counts.per_file)).toBe("table")
		expect(counts.total >= 0).toBeTruthy()
	end)

	it("renders <1/# Changes in file> and <1/# Changes in total> in diff sidebar without toasts", function()
		local sample_files = {
			{ file = "fileA.lua", status = "M" },
			{ file = "fileB.lua", status = "A" },
		}
		local win, buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = win
		diff_mode.state.file_list_buf = buf
		diff_mode.state.is_active = true
		diff_mode.state.active_file = "fileA.lua"

		diff_mode.state.stats = {
			total_add = 20,
			total_del = 5,
			per_file = {
				["fileA.lua"] = { add = 12, del = 3 },
				["fileB.lua"] = { add = 8, del = 2 },
			},
		}

		diff_mode.state.change_counts = {
			total = 5,
			per_file = {
				["fileA.lua"] = 3,
				["fileB.lua"] = 2,
			},
		}
		diff_mode.state.current_modifications = { 10, 25, 40 }
		diff_mode.state.current_mod_idx = 1

		diff_mode.render_file_list()

		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = table.concat(lines, "\n")

		-- Check message format: <1/# Changes in file> and <1/# Changes in total>
		expect(content:match("<1/3 Changes in file>") ~= nil).toBeTruthy()
		expect(content:match("<1/5 Changes in total>") ~= nil).toBeTruthy()

		-- Statusline should also include file and total counts
		local stl = vim.wo[win].statusline
		expect(stl:match("<1/3 file> <1/5 total>") ~= nil).toBeTruthy()

		diff_mode.close()
	end)

	it("updates change counter in sidebar when jumping modifications and never triggers notifications", function()
		local editor_win = vim.api.nvim_get_current_win()
		local editor_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, {
			"line 1",
			"line 2",
			"line 3",
			"line 4",
			"line 5",
			"line 6",
		})
		vim.api.nvim_win_set_buf(editor_win, editor_buf)

		local sample_files = {
			{ file = "fileA.lua", status = "M" },
			{ file = "fileB.lua", status = "M" },
		}
		local sb_win, sb_buf = diff_mode.open_file_list_window(sample_files, 1)
		diff_mode.state.file_list_win = sb_win
		diff_mode.state.file_list_buf = sb_buf
		diff_mode.state.editor_win = editor_win
		diff_mode.state.is_active = true
		diff_mode.state.active_file = "fileA.lua"

		diff_mode.state.change_counts = {
			total = 4,
			per_file = {
				["fileA.lua"] = 2,
				["fileB.lua"] = 2,
			},
		}
		diff_mode.state.current_modifications = { 2, 5 }
		diff_mode.state.current_mod_idx = 1
		diff_mode.render_file_list()

		-- Focus sidebar
		vim.api.nvim_set_current_win(sb_win)
		vim.api.nvim_win_set_cursor(editor_win, { 1, 0 })

		-- Spy on vim.notify to ensure NO toasts are triggered
		local notify_called = false
		local orig_notify = vim.notify
		vim.notify = function()
			notify_called = true
		end

		-- Jump next from sidebar
		local j_map = vim.api.nvim_buf_call(sb_buf, function()
			return vim.fn.maparg("J", "n", false, true)
		end)
		j_map.callback()

		-- Must NOT create toast notification
		expect(notify_called).toBe(false)
		-- Must have updated current_mod_idx to 1 (cursor moved to line 2)
		expect(diff_mode.state.current_mod_idx).toBe(1)
		expect(vim.api.nvim_win_get_cursor(editor_win)[1]).toBe(2)

		-- Jump next again -> moves to line 5, idx 2
		j_map.callback()
		expect(notify_called).toBe(false)
		expect(diff_mode.state.current_mod_idx).toBe(2)
		expect(vim.api.nvim_win_get_cursor(editor_win)[1]).toBe(5)

		-- Check sidebar contents reflect <2/2 Changes in file> and <2/4 Changes in total>
		local lines = vim.api.nvim_buf_get_lines(sb_buf, 0, -1, false)
		local content = table.concat(lines, "\n")
		expect(content:match("<2/2 Changes in file>") ~= nil).toBeTruthy()
		expect(content:match("<2/4 Changes in total>") ~= nil).toBeTruthy()

		-- Restore vim.notify
		vim.notify = orig_notify
		diff_mode.close()
		pcall(vim.api.nvim_buf_delete, editor_buf, { force = true })
	end)
end)
