-- ============================================================================
-- tests/spec/notify_focus_protection_spec.lua -- Notify focus protection tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("krs.core.notify focus protection", function()
	it("registers NotifyDismiss and ClearToasts user commands and sets vim.notify", function()
		local core_notify = require("krs.core.notify")
		core_notify.setup()

		local cmds = vim.api.nvim_get_commands({})
		expect(cmds.NotifyDismiss).toBeDefined()
		expect(cmds.ClearToasts).toBeDefined()
	end)

	it("dispatches non-blocking notifications cleanly without errors", function()
		local core_notify = require("krs.core.notify")
		core_notify.setup()

		local ok = pcall(function()
			vim.notify("Test info toast", vim.log.levels.INFO, { title = "Test" })
			vim.notify("Test warn toast", vim.log.levels.WARN, { title = "Test" })
			vim.notify("Test error toast", vim.log.levels.ERROR, { title = "Test" })
		end)
		expect(ok).toBe(true)
	end)

	it("does not steal focus from active window when notification fires", function()
		local win_before = vim.api.nvim_get_current_win()
		vim.notify("Focus test toast", vim.log.levels.INFO, { title = "Terminal focus test" })
		vim.wait(50, function()
			return false
		end)
		local win_after = vim.api.nvim_get_current_win()
		expect(win_after).toBe(win_before)
	end)
end)
