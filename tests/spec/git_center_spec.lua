-- ============================================================================
-- tests/spec/git_center_spec.lua -- Lifecycle, toggle, buffer flags and keys.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local git_center = require("plugins.krs.git_center")

describe("plugins.krs.git_center", function()
	beforeEach(function()
		if git_center.is_open() then
			git_center.close_git_center()
		end
	end)

	afterEach(function()
		if git_center.is_open() then
			git_center.close_git_center()
		end
	end)

	it("exports public API methods and settings", function()
		expect(type(git_center.open_git_center)).toBe("function")
		expect(type(git_center.close_git_center)).toBe("function")
		expect(type(git_center.toggle_git_center)).toBe("function")
		expect(type(git_center.open_file_in_tab)).toBe("function")
		expect(type(git_center.is_open)).toBe("function")
		expect(type(git_center.stage_all_with_modal)).toBe("function")
		expect(type(git_center.settings)).toBe("table")
		expect(type(git_center.settings.keys)).toBe("table")
		expect(type(git_center.settings.keys.open_tab)).toBe("table")
	end)

	it("includes Ctrl+Shift+X in stage_all key settings and spec", function()
		expect(git_center.settings.keys.stage_all).toContain("<C-S-x>")
		expect(git_center.settings.keys.stage_all).toContain("<C-S-X>")
	end)

	it("toggles open and closed cleanly", function()
		expect(git_center.is_open()).toBeFalsy()

		git_center.toggle_git_center()
		expect(git_center.is_open()).toBeTruthy()
		expect(git_center.main_win).toBeDefined()
		expect(git_center.preview_win).toBeDefined()
		expect(vim.api.nvim_win_is_valid(git_center.main_win)).toBeTruthy()
		expect(vim.api.nvim_win_is_valid(git_center.preview_win)).toBeTruthy()

		git_center.toggle_git_center()
		expect(git_center.is_open()).toBeFalsy()
		expect(git_center.main_win).toBeNil()
		expect(git_center.preview_win).toBeNil()
	end)

	it("creates unlisted scratch buffers with nofile and wipe flags", function()
		git_center.open_git_center()

		local main_buf = git_center.main_buf
		local preview_buf = git_center.preview_buf

		expect(vim.bo[main_buf].buftype).toBe("nofile")
		expect(vim.bo[main_buf].bufhidden).toBe("wipe")
		expect(vim.bo[main_buf].modifiable).toBeFalsy()

		expect(vim.bo[preview_buf].buftype).toBe("nofile")
		expect(vim.bo[preview_buf].bufhidden).toBe("wipe")
		expect(vim.bo[preview_buf].modifiable).toBeFalsy()

		git_center.close_git_center()
	end)

	it("binds close keys across normal, visual, insert, and terminal modes in both buffers", function()
		git_center.open_git_center()

		local main_buf = git_center.main_buf
		local preview_buf = git_center.preview_buf

		local close_keys = { "<Esc>", "q", "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>" }
		local modes = { "n", "v", "i", "t" }

		for _, key in ipairs(close_keys) do
			for _, mode in ipairs(modes) do
				local main_map = vim.api.nvim_buf_call(main_buf, function()
					return vim.fn.maparg(key, mode, false, true)
				end)
				expect({ key = key, mode = mode, buf = "main", bound = (main_map.buffer == 1) }).toEqual({
					key = key,
					mode = mode,
					buf = "main",
					bound = true,
				})

				local preview_map = vim.api.nvim_buf_call(preview_buf, function()
					return vim.fn.maparg(key, mode, false, true)
				end)
				expect({ key = key, mode = mode, buf = "preview", bound = (preview_map.buffer == 1) }).toEqual({
					key = key,
					mode = mode,
					buf = "preview",
					bound = true,
				})
			end
		end

		git_center.close_git_center()
	end)

	it("closes all windows when close_git_center is called", function()
		git_center.open_git_center()
		local main_win = git_center.main_win
		local prev_win = git_center.preview_win

		expect(vim.api.nvim_win_is_valid(main_win)).toBeTruthy()
		expect(vim.api.nvim_win_is_valid(prev_win)).toBeTruthy()

		git_center.close_git_center()

		expect(git_center.is_open()).toBeFalsy()
		expect(git_center.main_win).toBeNil()
		expect(git_center.preview_win).toBeNil()
		expect(vim.api.nvim_win_is_valid(main_win)).toBeFalsy()
		expect(vim.api.nvim_win_is_valid(prev_win)).toBeFalsy()
	end)

	it("binds tab switching keys in both main and preview buffers", function()
		git_center.open_git_center()

		local main_buf = git_center.main_buf
		local preview_buf = git_center.preview_buf

		local tab_keys = { "<A-h>", "<A-l>", "<C-h>", "<C-l>" }
		for _, key in ipairs(tab_keys) do
			local main_map = vim.api.nvim_buf_call(main_buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			expect({ key = key, buf = "main", bound = (main_map.buffer == 1) }).toEqual({
				key = key,
				buf = "main",
				bound = true,
			})

			local preview_map = vim.api.nvim_buf_call(preview_buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			expect({ key = key, buf = "preview", bound = (preview_map.buffer == 1) }).toEqual({
				key = key,
				buf = "preview",
				bound = true,
			})
		end

		git_center.close_git_center()
	end)

	it("resizes the split and clamps within the [0.20, 0.80] bounds", function()
		local project = require("krs.core.project")
		local store = require("krs.core.store")
		local root = require("krs.core.path").normalize(project.root() or vim.fn.getcwd())
		local cfg_path = project.config_path(git_center.settings.config_filename, root)
		store.save(cfg_path, { left_ratio = 0.50 })

		git_center.open_git_center()
		expect(git_center.current_left_ratio).toBe(0.50)

		git_center.resize_split(0.03)
		expect(git_center.current_left_ratio).toBe(0.53)

		git_center.resize_split(10)
		expect(git_center.current_left_ratio).toBe(0.80)

		git_center.resize_split(-10)
		expect(git_center.current_left_ratio).toBe(0.20)

		git_center.close_git_center()
		store.save(cfg_path, { left_ratio = 0.50 })
	end)

	it("persists the resized left ratio and restores it on next open", function()
		local project = require("krs.core.project")
		local store = require("krs.core.store")
		local root = require("krs.core.path").normalize(project.root() or vim.fn.getcwd())
		local cfg_path = project.config_path(git_center.settings.config_filename, root)
		store.save(cfg_path, { left_ratio = 0.50 })

		git_center.open_git_center()
		git_center.resize_split(0.03)
		git_center.close_git_center()

		local saved = store.load(cfg_path, {})
		expect(saved.left_ratio).toBe(0.53)

		git_center.open_git_center()
		expect(git_center.current_left_ratio).toBe(0.53)
		git_center.close_git_center()

		store.save(cfg_path, { left_ratio = 0.50 })
	end)

	it("refreshes cleanly when commit fields contain newlines or multiline input", function()
		git_center.open_git_center()

		-- Set title and description with newlines
		git_center.commit_data.title = "feat: add feature\nwith newline"
		git_center.commit_data.description = "Line 1 of description\nLine 2 of description\nLine 3"
		git_center.commit_data.tag = "v1.0.0\n"

		local ok, err = pcall(git_center.refresh)
		expect(ok).toBeTruthy()
		expect(err).toBeNil()

		git_center.close_git_center()
		git_center.commit_data = { title = "", description = "", tag = "" }
	end)

	it("exports open_branch_modal and open_commit_log_modal functions", function()
		expect(type(git_center.open_branch_modal)).toBe("function")
		expect(type(git_center.open_commit_log_modal)).toBe("function")
	end)

	it("binds branch (b) and commit log (l, L) keymaps in main panel", function()
		git_center.open_git_center()
		local main_buf = git_center.main_buf

		for _, key in ipairs({ "b", "l", "L" }) do
			local map = vim.api.nvim_buf_call(main_buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			expect({ key = key, bound = (map.buffer == 1) }).toEqual({
				key = key,
				bound = true,
			})
		end

		local k_map = vim.api.nvim_buf_call(main_buf, function()
			return vim.fn.maparg("k", "n", false, true)
		end)
		expect(k_map.buffer ~= 1).toBeTruthy()

		git_center.close_git_center()
	end)

	it(
		"opens side-by-side diff modal with left (before) and right (after) float windows with elevated zindex and Ctrl+h/l keymaps",
		function()
			local z_index = require("krs.core.z_index")
			git_center.open_git_center()
			git_center.open_diff_modal(nil, nil, vim.fn.getcwd())

			if git_center.diff_modal_win then
				expect(vim.api.nvim_win_is_valid(git_center.diff_modal_win)).toBeTruthy()
				local cfg = vim.api.nvim_win_get_config(git_center.diff_modal_win)
				local expected_z = z_index.get_zindex("git_center_diff", 40)
				expect(cfg.zindex).toBe(expected_z)

				-- Verify Ctrl+h and Ctrl+l keymaps are bound in the diff modal buffer
				local buf = git_center.diff_modal_buf
				local map_h = vim.api.nvim_buf_call(buf, function()
					return vim.fn.maparg("<C-h>", "n", false, true)
				end)
				local map_l = vim.api.nvim_buf_call(buf, function()
					return vim.fn.maparg("<C-l>", "n", false, true)
				end)

				expect(map_h.buffer == 1 or map_h.callback ~= nil).toBeTruthy()
				expect(map_l.buffer == 1 or map_l.callback ~= nil).toBeTruthy()
			end

			git_center.close_git_center()
		end
	)

	it("opens commit log modal with configured left ratio, dynamic zindex and correct keymaps", function()
		local z_index = require("krs.core.z_index")
		git_center.open_git_center()
		git_center.resize_split(0.05) -- Set custom ratio

		git_center.open_commit_log_modal(vim.fn.getcwd())

		local expected_z = z_index.get_zindex("git_center_log", 30)
		local wins = vim.api.nvim_list_wins()
		local log_wins = {}
		for _, w in ipairs(wins) do
			local cfg = vim.api.nvim_win_get_config(w)
			if cfg.zindex == expected_z then
				table.insert(log_wins, w)
			end
		end

		expect(#log_wins).toBeGreaterThanOrEqual(2)

		local found_K = false
		local found_k = false
		for _, w in ipairs(log_wins) do
			if vim.api.nvim_win_is_valid(w) then
				local buf = vim.api.nvim_win_get_buf(w)
				local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
				for _, m in ipairs(keymaps) do
					if m.lhs == "K" then
						found_K = true
					end
					if m.lhs == "k" then
						found_k = true
					end
				end
			end
		end

		expect(found_K).toBe(true)
		expect(found_k).toBe(false)

		-- Close log modal windows
		for _, w in ipairs(log_wins) do
			if vim.api.nvim_win_is_valid(w) then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end

		git_center.close_git_center()
	end)

	it("registers user commands GitLog and GitHistory", function()
		git_center.setup()
		expect(vim.fn.exists(":GitLog")).toBe(2)
		expect(vim.fn.exists(":GitHistory")).toBe(2)
	end)

	it("restores focus to git-center main_win when closing log modal from right pane", function()
		local z_index = require("krs.core.z_index")
		git_center.open_git_center()
		local main_win = git_center.main_win
		expect(vim.api.nvim_get_current_win()).toBe(main_win)

		git_center.open_commit_log_modal(vim.fn.getcwd())

		local expected_z = z_index.get_zindex("git_center_log", 30)
		local log_wins = {}
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local cfg = vim.api.nvim_win_get_config(w)
			if cfg.zindex == expected_z then
				table.insert(log_wins, w)
			end
		end
		expect(#log_wins).toBeGreaterThanOrEqual(2)

		local right_win = nil
		for _, w in ipairs(log_wins) do
			if w ~= vim.api.nvim_get_current_win() then
				right_win = w
				break
			end
		end
		expect(right_win).toBeDefined()

		-- Move focus to right window of log modal
		vim.api.nvim_set_current_win(right_win)
		expect(vim.api.nvim_get_current_win()).toBe(right_win)

		-- Close right window / trigger modal close
		local right_buf = vim.api.nvim_win_get_buf(right_win)
		local esc_map = vim.api.nvim_buf_call(right_buf, function()
			return vim.fn.maparg("<Esc>", "n", false, true)
		end)
		expect(esc_map.rhs or esc_map.callback).toBeDefined()
		if esc_map.callback then
			esc_map.callback()
		end

		expect(vim.api.nvim_get_current_win()).toBe(main_win)

		git_center.close_git_center()
	end)

	it("binds Shift+Enter keymaps to open files in bufferline tab and closes git-center", function()
		git_center.open_git_center()

		local main_buf = git_center.main_buf
		local shift_cr_map = vim.api.nvim_buf_call(main_buf, function()
			return vim.fn.maparg("<S-CR>", "n", false, true)
		end)
		expect(shift_cr_map.rhs or shift_cr_map.callback).toBeDefined()

		local temp_file = vim.fn.tempname() .. ".lua"
		vim.fn.writefile({ "print('hello')" }, temp_file)

		git_center.open_file_in_tab(temp_file)
		expect(git_center.is_open()).toBeFalsy()

		vim.fn.delete(temp_file)
	end)
end)
