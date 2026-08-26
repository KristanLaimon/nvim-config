-- ============================================================================
-- tests/integration/telescope_spec.lua -- Telescope plugin wiring & commands.
-- ============================================================================

require("lazy").load({ plugins = { "telescope.nvim" } })

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

--- True when a user command exists.
--- @param name string Command name, without the colon.
--- @return boolean
local function has_command(name)
	return vim.fn.exists(":" .. name) > 0
end

--- True when a mapping exists in any of the given modes.
--- @param lhs string Key sequence.
--- @param modes string[]|nil Defaults to normal mode.
--- @return boolean
local function has_keymap(lhs, modes)
	for _, mode in ipairs(modes or { "n" }) do
		if vim.fn.maparg(lhs, mode) ~= "" then
			return true
		end
	end
	return false
end

describe("telescope plugin configuration", function()
	it("loads telescope and exports global finder functions", function()
		expect(type(_G.FindFilesGitignore)).toBe("function")
		expect(type(_G.FindFilesNoIgnore)).toBe("function")
	end)

	it("registers all telescope commands", function()
		for _, name in ipairs({
			"Telescope",
			"TelescopeOpenFolder",
			"TelescopeFindFilesGitignore",
			"TelescopeFindFilesNoIgnore",
			"TelescopeFileBrowserDesktop",
			"TelescopeFindFilesSplitLeft",
			"TelescopeFindFilesSplitBelow",
			"TelescopeFindFilesSplitAbove",
			"TelescopeFindFilesSplitRight",
		}) do
			expect({ name, has_command(name) }).toEqual({ name, true })
		end
	end)

	it("binds telescope search and navigation keys", function()
		for _, key in ipairs({ "<C-f>", "<C-S-y>", "<C-S-f>", "<C-/>", "<C-k>", "<C-K>" }) do
			expect({ key, has_keymap(key, { "n", "i" }) }).toEqual({ key, true })
		end
	end)
end)
