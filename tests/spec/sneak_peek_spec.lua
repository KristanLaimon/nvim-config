-- ============================================================================
-- tests/spec/sneak_peek_spec.lua -- Unit tests for Sneak-Peek Project Modal.
-- ============================================================================
-- Contract: Sneak-Peek allows opening any directory in a centered 90% floating
-- window with sub-process terminal execution, keymap dismissals, user commands,
-- and clean process tree termination on cleanup.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local peek = require("plugins.krs.dev.sneak_peek")

describe("plugins.krs.dev.sneak_peek", function()
	local temp_dir
	local original_termopen
	local original_open_folder_picker
	local original_ui_input

	beforeEach(function()
		-- Create a temporary directory for tests
		temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")

		original_termopen = vim.fn.termopen
		original_open_folder_picker = _G.OpenFolderPicker
		original_ui_input = vim.ui.input

		-- Ensure state is clean before each test
		peek.cleanup()
	end)

	afterEach(function()
		peek.cleanup()
		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end

		vim.fn.termopen = original_termopen
		_G.OpenFolderPicker = original_open_folder_picker
		vim.ui.input = original_ui_input
	end)

	it("exposes default settings and initial closed state", function()
		expect(peek.settings.width).toBe(0.90)
		expect(peek.settings.height).toBe(0.90)
		expect(peek.settings.border).toBe("rounded")
		expect(peek.settings.keys.toggle).toContain("<C-S-y>")
		expect(peek.settings.keys.toggle).toContain("<C-S-Y>")
		expect(peek.is_open()).toBeFalsy()
	end)

	it("ignores nil or empty directory paths on open", function()
		peek.open(nil)
		expect(peek.is_open()).toBeFalsy()

		peek.open("")
		expect(peek.is_open()).toBeFalsy()
	end)

	it("handles non-existent directories gracefully", function()
		local fake_path = temp_dir .. "/does_not_exist_xyz123"
		peek.open(fake_path)

		expect(peek.is_open()).toBeFalsy()
	end)

	it("opens a floating modal window for a valid directory", function()
		-- Mock termopen to avoid running sub-Neovim process during unit test
		local termopen_called = false
		vim.fn.termopen = function(cmd, opts)
			termopen_called = true
			expect(cmd[2]).toBe(temp_dir)
			expect(opts.cwd).toBe(temp_dir)
			return 1001 -- Mock job id
		end

		peek.open(temp_dir)

		expect(peek.is_open()).toBeTruthy()
		expect(termopen_called).toBeTruthy()
	end)

	it("configures the float buffer and window correctly", function()
		vim.fn.termopen = function()
			return 1002
		end

		peek.open(temp_dir)

		expect(peek.is_open()).toBeTruthy()

		local win = vim.api.nvim_get_current_win()
		local cfg = vim.api.nvim_win_get_config(win)

		expect(cfg.relative).toBe("editor")
		expect(cfg.width).toBe(math.max(math.floor(vim.o.columns * peek.settings.width), 1))
		expect(cfg.height).toBe(math.max(math.floor(vim.o.lines * peek.settings.height), 1))

		local buf = vim.api.nvim_win_get_buf(win)
		expect(vim.bo[buf].buftype).toBe("nofile")
		expect(vim.bo[buf].bufhidden).toBe("wipe")
	end)

	it("binds close keymaps inside the sneak-peek buffer", function()
		vim.fn.termopen = function()
			return 1003
		end

		peek.open(temp_dir)

		local win = vim.api.nvim_get_current_win()
		local sneak_buf = vim.api.nvim_win_get_buf(win)
		expect(sneak_buf).toBeTruthy()

		local has_keymap = false
		for _, mode in ipairs({ "n", "i", "v", "t" }) do
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(sneak_buf, mode)) do
				if map.lhs:lower():find("c%-s%-y") or map.lhs == "<C-S-y>" or map.lhs == "<C-S-Y>" then
					has_keymap = true
					break
				end
			end
		end

		expect(has_keymap).toBeTruthy()
	end)

	it("cleans up active session cleanly", function()
		vim.fn.termopen = function()
			return 1004
		end

		peek.open(temp_dir)
		expect(peek.is_open()).toBeTruthy()

		peek.cleanup()

		expect(peek.is_open()).toBeFalsy()
	end)

	it("is safe to call cleanup multiple times", function()
		expect(function()
			peek.cleanup()
			peek.cleanup()
		end).not_.toThrow()
	end)

	it("re-opens correctly if called while already open", function()
		local temp_dir2 = vim.fn.tempname()
		vim.fn.mkdir(temp_dir2, "p")

		vim.fn.termopen = function()
			return 1005
		end

		peek.open(temp_dir)
		expect(peek.is_open()).toBeTruthy()

		peek.open(temp_dir2)
		expect(peek.is_open()).toBeTruthy()

		vim.fn.delete(temp_dir2, "rf")
	end)

	it("toggles off when already open", function()
		vim.fn.termopen = function()
			return 1006
		end

		peek.open(temp_dir)
		expect(peek.is_open()).toBeTruthy()

		peek.toggle_or_pick()
		expect(peek.is_open()).toBeFalsy()
	end)

	it("uses _G.OpenFolderPicker when toggle_or_pick is called while closed", function()
		local picker_called = false
		_G.OpenFolderPicker = function(opts, callback)
			picker_called = true
			callback(temp_dir)
		end

		vim.fn.termopen = function()
			return 1007
		end

		peek.toggle_or_pick()

		expect(picker_called).toBeTruthy()
		expect(peek.is_open()).toBeTruthy()
	end)

	it("falls back to vim.ui.input when OpenFolderPicker is not present", function()
		_G.OpenFolderPicker = nil

		local input_called = false
		vim.ui.input = function(opts, on_confirm)
			input_called = true
			expect(opts.prompt).toBe("Sneak-Peek Folder Path: ")
			on_confirm(temp_dir)
		end

		vim.fn.termopen = function()
			return 1008
		end

		peek.toggle_or_pick()

		expect(input_called).toBeTruthy()
		expect(peek.is_open()).toBeTruthy()
	end)

	it("registers user commands SneakPeek and SneakPeekClose", function()
		peek.setup()

		expect(vim.fn.exists(":SneakPeek")).toBe(2)
		expect(vim.fn.exists(":SneakPeekClose")).toBe(2)
	end)

	it("opens sneak peek via :SneakPeek command", function()
		vim.fn.termopen = function()
			return 1009
		end

		peek.setup()

		vim.cmd("SneakPeek " .. temp_dir)
		expect(peek.is_open()).toBeTruthy()

		vim.cmd("SneakPeekClose")
		expect(peek.is_open()).toBeFalsy()
	end)
end)
