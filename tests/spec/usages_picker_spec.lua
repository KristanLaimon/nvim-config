local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("plugins.krs.tools.usages_picker", function()
	it("exposes available styles including bubbles (default), plain, and labels", function()
		local picker = require("plugins.krs.tools.usages_picker")
		expect(picker.available_styles.bubbles ~= nil).toBe(true)
		expect(picker.available_styles.plain ~= nil).toBe(true)
		expect(picker.available_styles.labels ~= nil).toBe(true)
	end)

	it("returns bubbles text_format by default and formats pill badges correctly", function()
		local picker = require("plugins.krs.tools.usages_picker")
		local fmt = picker.get_text_format("bubbles")
		expect(type(fmt)).toBe("function")

		local sample = { references = 3, definition = 1, implementation = 0, stacked_count = 0 }
		local res = fmt(sample)
		expect(type(res)).toBe("table")
		expect(#res > 0).toBe(true)
		-- Verifies pill rounding characters
		expect(res[1][1]).toBe("")
		expect(res[#res][1]).toBe("")
	end)

	it("formats plain text style correctly for single and plural counts", function()
		local picker = require("plugins.krs.tools.usages_picker")
		local fmt = picker.get_text_format("plain")
		expect(type(fmt)).toBe("function")

		local sample_single = { references = 1, definition = 1, implementation = 0, stacked_count = 0 }
		expect(fmt(sample_single)).toBe("1 usage, 1 defs")

		local sample_plural = { references = 5, definition = 2, implementation = 1, stacked_count = 0 }
		expect(fmt(sample_plural)).toBe("5 usages, 2 defs, 1 impls")

		local sample_stacked = { references = 2, definition = 0, implementation = 0, stacked_count = 3 }
		expect(fmt(sample_stacked)).toBe("2 usages | +3")
	end)

	it("formats labels style with badge tag markers", function()
		local picker = require("plugins.krs.tools.usages_picker")
		local fmt = picker.get_text_format("labels")
		expect(type(fmt)).toBe("function")

		local sample = { references = 4, definition = 1, implementation = 0, stacked_count = 0 }
		local res = fmt(sample)
		expect(type(res)).toBe("table")
		expect(#res > 0).toBe(true)
		-- Verifies badge tag start and end markers
		expect(res[1][1]).toBe("󰍞")
		expect(res[3][1]).toBe("󰍟")
	end)

	it("persists theme changes when set_style is called", function()
		local picker = require("plugins.krs.tools.usages_picker")
		local initial = picker.get_current_style()

		picker.set_style("plain")
		expect(picker.get_current_style()).toBe("plain")

		picker.set_style("labels")
		expect(picker.get_current_style()).toBe("labels")

		picker.set_style("bubbles")
		expect(picker.get_current_style()).toBe("bubbles")
	end)

	it("registers KrsUsagesTheme and UsagesThemePicker user commands", function()
		local picker = require("plugins.krs.tools.usages_picker")
		picker.setup()
		local cmd1 = vim.fn.exists(":KrsUsagesTheme")
		local cmd2 = vim.fn.exists(":UsagesThemePicker")
		expect(cmd1 > 0).toBe(true)
		expect(cmd2 > 0).toBe(true)
	end)
end)
