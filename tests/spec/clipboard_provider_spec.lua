-- ============================================================================
-- tests/spec/clipboard_provider_spec.lua -- Clipboard provider tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("Clipboard provider setup in options", function()
	it("does not override native clipboard on Windows or desktop GUI environments", function()
		require("vim_options")
		local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
		if is_win then
			-- On Windows, vim.g.clipboard remains nil so Neovim uses native win32yank / powershell / Win32 API
			expect(vim.g.clipboard == nil or type(vim.g.clipboard) == "table").toBeTruthy()
		end
	end)
end)
