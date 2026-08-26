-- ============================================================================
-- tests/spec/mobile_keymaps_spec.lua -- Mobile & Phone term keymap tests.
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

describe("Mobile & Phone Termux keymap aliases", function()
	it("binds Command Palette shortcuts for Ctrl+Shift+P and leader aliases", function()
		local palette = require("plugins.krs.tools.command_palette")
		palette.setup()
		expect(palette.settings.keys.open).toContain("<C-S-p>")
		expect(palette.settings.keys.open).toContain("<leader>cp")
	end)

	it("binds Integrated Terminal toggle shortcuts for Ctrl+t, Ctrl+\\, leader+t, and leader+ft", function()
		local term = require("plugins.krs.dev.terminal")
		term.setup()
		expect(term.settings.keys.toggle).toContain("<C-t>")
		expect(term.settings.keys.toggle).toContain("<C-T>")
		expect(term.settings.keys.toggle).toContain("<C-\\>")
		expect(term.settings.keys.toggle).toContain("<leader>t")
		expect(term.settings.keys.toggle).toContain("<leader>ft")
	end)

	it("binds File Explorer toggle shortcuts for Ctrl+e, Ctrl+E, leader+e, and leader+fe", function()
		local editor = require("keymaps.editor")
		expect(editor.settings.keys.explorer).toContain("<C-e>")
		expect(editor.settings.keys.explorer).toContain("<C-E>")
		expect(editor.settings.keys.explorer).toContain("<leader>e")
		expect(editor.settings.keys.explorer).toContain("<leader>fe")
	end)

	it("has ZERO keymap collisions across all mobile shortcut aliases", function()
		local registry = require("krs.core.keymap_registry")
		expect(#registry.collisions).toBe(0)
	end)
end)
