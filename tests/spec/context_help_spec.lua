-- ============================================================================
-- tests/spec/context_help_spec.lua -- Which help `?` shows where.
-- ============================================================================
-- The important case is the LAST one: in an ordinary buffer `?` must stay the
-- native backwards search, so the detection has to fall through to "editor"
-- rather than matching something loosely.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach
local help = require("plugins.krs.context_help")

local scratch_buffers = {}

--- Opens a scratch buffer with the given filetype and name, and focuses it.
--- @param filetype string
--- @param name string|nil Buffer name.
local function open_buffer(filetype, name)
	local buf = vim.api.nvim_create_buf(false, true)
	if name then
		vim.api.nvim_buf_set_name(buf, name)
	end
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = filetype

	table.insert(scratch_buffers, buf)
end

describe("context_help.get_context", function()
	afterEach(function()
		for _, buf in ipairs(scratch_buffers) do
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
		scratch_buffers = {}
	end)

	it("detects the file tree", function()
		open_buffer("neo-tree")

		expect(help.get_context()).toBe("neotree")
	end)

	it("detects git surfaces by filetype", function()
		open_buffer("NeogitStatus")

		expect(help.get_context()).toBe("git")
	end)

	it("detects a picker prompt", function()
		open_buffer("TelescopePrompt")

		expect(help.get_context()).toBe("telescope")
	end)

	it("detects a task output window", function()
		open_buffer("TaskRunner")

		expect(help.get_context()).toBe("telescope")
	end)

	it("falls back to the editor for an ordinary buffer", function()
		open_buffer("lua", vim.fn.tempname() .. ".lua")

		expect(help.get_context()).toBe("editor")
	end)

	it("gives every context a title and at least one line", function()
		for _, context in ipairs(help.settings.contexts) do
			expect(context.title).toBeDefined()
			expect(#context.lines).toBeGreaterThan(0)
		end
	end)

	it("ends with a fallback context that matches everything", function()
		local last = help.settings.contexts[#help.settings.contexts]

		expect(last.detect).toBeNil()
		expect(last.name).toBe(help.settings.passthrough_context)
	end)
end)
