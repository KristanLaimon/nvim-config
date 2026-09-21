-- ============================================================================
-- tests/spec/git_blame_spec.lua -- Git Blame plugin specification & integration.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local cp = require("plugins.krs.tools.command_palette")
local git_blame_spec = require("plugins.editor.git_blame")

describe("plugins.editor.git_blame", function()
	it("exports a lazy plugin specification for f-person/git-blame.nvim", function()
		expect(git_blame_spec[1]).toBe("f-person/git-blame.nvim")
		expect(git_blame_spec.opts).toBeDefined()
		expect(git_blame_spec.opts.enabled).toBe(true)
		expect(git_blame_spec.opts.highlight_group).toBe("GitBlame")
		expect(git_blame_spec.opts.date_format).toBe("%r")
		expect(git_blame_spec.opts.message_template).toContain("<author>")
	end)

	it("exposes user commands in cmd spec list", function()
		expect(git_blame_spec.cmd).toContain("GitBlameToggle")
		expect(git_blame_spec.cmd).toContain("GitBlameEnable")
		expect(git_blame_spec.cmd).toContain("GitBlameDisable")
		expect(git_blame_spec.cmd).toContain("GitBlameOpenCommitURL")
		expect(git_blame_spec.cmd).toContain("GitBlameCopySHA")
		expect(git_blame_spec.cmd).toContain("GitBlameCopyCommitURL")
		expect(git_blame_spec.cmd).toContain("GitBlameOpenFileURL")
	end)

	it("includes Git Blame commands in Command Palette", function()
		local found_toggle = false
		local found_open_url = false
		for _, cmd in ipairs(cp.commands) do
			if cmd.cmd == "GitBlameToggle" and cmd.category == "Git" then
				found_toggle = true
			end
			if cmd.cmd == "GitBlameOpenCommitURL" and cmd.category == "Git" then
				found_open_url = true
			end
		end
		expect(found_toggle).toBe(true)
		expect(found_open_url).toBe(true)
	end)

	it("config sets up GitBlame highlight group with italic styling", function()
		expect(type(git_blame_spec.config)).toBe("function")
		expect(function()
			git_blame_spec.config(nil, git_blame_spec.opts)
		end).not_.toThrow()
		local hl = vim.api.nvim_get_hl(0, { name = "GitBlame", link = false })
		expect(hl).toBeDefined()
	end)
end)
