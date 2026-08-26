-- ============================================================================
-- tests/spec/theme_picker_spec.lua -- Nagatoro theme discovery & picker.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local theme_picker = require("plugins.krs.ui.theme_picker")

describe("plugins.krs.ui.theme_picker", function()
	it("discovers all -krs and nagatoro-* formatted themes in colors/", function()
		local themes = theme_picker.discover_themes()
		expect(themes).toContain("nagatoro-krs")
		expect(themes).toContain("nagatoro-light")
		expect(themes).toContain("onedark-krs")
		expect(themes).toContain("catppuccin-krs")
		expect(themes).toContain("nord-krs")
	end)

	it("registers KrsThemePicker user command", function()
		theme_picker.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["KrsThemePicker"]).toBeDefined()
	end)

	it("retrieves current saved theme or fallback", function()
		local current = theme_picker.get_current_theme()
		expect(type(current)).toBe("string")
		expect(#current).toBeGreaterThan(0)
	end)
end)
