-- ============================================================================
-- tests/spec/clipboard_provider_spec.lua -- Clipboard provider tests.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("Clipboard provider setup in options", function()
	it("configures OSC 52 / Termux clipboard provider when in Termux/PRoot or no X display", function()
		require("config.options")
		expect(vim.g.clipboard).toBeDefined()
		expect(type(vim.g.clipboard)).toBe("table")
		expect(vim.g.clipboard.name).toBe("OSC 52 / Termux Clipboard")
		expect(type(vim.g.clipboard.copy)).toBe("table")
		expect(type(vim.g.clipboard.paste)).toBe("table")
		expect(type(vim.g.clipboard.copy["+"])).toBe("function")
		expect(type(vim.g.clipboard.paste["+"])).toBe("function")
	end)
end)
