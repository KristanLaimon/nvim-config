-- ============================================================================
-- tests/spec/startup_notification_spec.lua -- Startup toast notification test.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("KrsStartupNotification", function()
	it("executes lazy setup and verifies startup stats formatting", function()
		pcall(require, "lazy_init")
		local autocmds = vim.api.nvim_get_autocmds({ group = "KrsStartupNotification" })
		expect(#autocmds > 0).toBe(true)

		local ok, lazy = pcall(require, "lazy")
		if ok then
			local stats = lazy.stats()
			expect(type(stats.count)).toBe("number")
			expect(type(stats.loaded)).toBe("number")
			expect(stats.count >= stats.loaded).toBe(true)
		end
	end)
end)
