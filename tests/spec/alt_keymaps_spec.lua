-- ============================================================================
-- tests/spec/alt_keymaps_spec.lua -- Alt + <something> keymap functionality tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

-- Ensure keymaps are loaded
require("keymaps")

--- Helper to check if a keymap exists in normal mode
--- @param lhs string
--- @return boolean
local function has_normal_keymap(lhs)
	return vim.fn.maparg(lhs, "n") ~= ""
end

describe("Alt / Meta keymaps functionality", function()
	it("binds buffer previous (left tab cycle) keymaps for Alt and Meta variants", function()
		local editor = require("keymaps.editor")
		expect(editor.settings.keys.buffer_prev).toContain("<A-h>")
		expect(editor.settings.keys.buffer_prev).toContain("<M-h>")
		expect(editor.settings.keys.buffer_prev).toContain("<A-Left>")
		expect(editor.settings.keys.buffer_prev).toContain("<M-Left>")

		for _, key in ipairs(editor.settings.keys.buffer_prev) do
			expect(has_normal_keymap(key)).toBe(true)
		end
	end)

	it("binds buffer next (right tab cycle) keymaps for Alt and Meta variants", function()
		local editor = require("keymaps.editor")
		expect(editor.settings.keys.buffer_next).toContain("<A-l>")
		expect(editor.settings.keys.buffer_next).toContain("<M-l>")
		expect(editor.settings.keys.buffer_next).toContain("<A-Right>")
		expect(editor.settings.keys.buffer_next).toContain("<M-Right>")

		for _, key in ipairs(editor.settings.keys.buffer_next) do
			expect(has_normal_keymap(key)).toBe(true)
		end
	end)

	it("binds LSP definition jump keymaps for Alt and Meta variants", function()
		local lsp_keys = require("keymaps.lsp")
		expect(lsp_keys.settings.keys.goto_definition).toContain("<A-j>")
		expect(lsp_keys.settings.keys.goto_definition).toContain("<M-j>")
		expect(lsp_keys.settings.keys.goto_definition).toContain("<A-k>")
		expect(lsp_keys.settings.keys.goto_definition).toContain("<M-k>")

		for _, key in ipairs(lsp_keys.settings.keys.goto_definition) do
			expect(has_normal_keymap(key)).toBe(true)
		end
	end)

	it("binds LSP symbol usages keymaps for Alt+Shift+K and Meta variants", function()
		local lsp_keys = require("keymaps.lsp")
		expect(lsp_keys.settings.keys.show_usages).toContain("<A-S-k>")
		expect(lsp_keys.settings.keys.show_usages).toContain("<A-S-K>")
		expect(lsp_keys.settings.keys.show_usages).toContain("<M-S-k>")
		expect(lsp_keys.settings.keys.show_usages).toContain("<M-S-K>")

		for _, key in ipairs(lsp_keys.settings.keys.show_usages) do
			expect(has_normal_keymap(key)).toBe(true)
		end
	end)

	it("binds git stage all keymaps for Ctrl+Shift+X, Alt and Meta variants", function()
		local krs_keys = require("keymaps.krs")
		expect(krs_keys.settings.keys.git_stage_all).toContain("<C-S-x>")
		expect(krs_keys.settings.keys.git_stage_all).toContain("<C-S-X>")
		expect(krs_keys.settings.keys.git_stage_all).toContain("<A-s>")
		expect(krs_keys.settings.keys.git_stage_all).toContain("<M-s>")

		for _, key in ipairs(krs_keys.settings.keys.git_stage_all) do
			expect(has_normal_keymap(key)).toBe(true)
		end

		local csx_map = vim.fn.maparg("<C-S-x>", "n", false, true)
		expect(csx_map).toBeDefined()
		if type(csx_map) == "table" and csx_map.desc then
			expect(csx_map.desc:lower()).toContain("stage")
		end
	end)

	it("replays buffer prev navigation when Alt+h or Meta+h is pressed with no breakpoint on line", function()
		local maps = vim.api.nvim_get_keymap("n")
		local a_h_map
		for _, m in ipairs(maps) do
			if m.lhs == "<A-h>" or m.lhs == "<M-h>" then
				a_h_map = m
				break
			end
		end

		expect(a_h_map).toBeTruthy()
		if a_h_map and a_h_map.callback then
			-- Ensure executing the callback does not throw an error
			local status, err = pcall(a_h_map.callback)
			expect(status).toBe(true)
		end
	end)

	it("binds window focus upper keymaps for Ctrl+Shift+Alt+K and variants", function()
		local editor = require("keymaps.editor")
		expect(editor.settings.keys.window_up).toContain("<C-S-A-k>")
		expect(editor.settings.keys.window_up).toContain("<C-A-S-k>")
		expect(editor.settings.keys.window_up).toContain("<C-S-M-k>")
		expect(editor.settings.keys.window_up).toContain("<C-M-S-k>")

		for _, key in ipairs(editor.settings.keys.window_up) do
			expect(has_normal_keymap(key)).toBe(true)
		end
	end)
end)
