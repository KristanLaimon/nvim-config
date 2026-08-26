-- ============================================================================
-- tests/integration/dap_breakpoints_spec.lua -- Enable/disable + persistence.
-- ============================================================================
-- Needs the real nvim-dap, so it lives here rather than in tests/spec.
-- The invariant under test: disabling KEEPS the line but drops the breakpoint
-- from nvim-dap, enabling restores it WITH its condition, and both survive a
-- round trip through breakpoints.json.
-- ============================================================================

require("lazy").load({ plugins = { "nvim-dap" } })

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local dap_bp = require("dap.breakpoints")
local krs = require("plugins.krs.dev.dap_breakpoints")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local file = root .. "/sample.lua"
vim.fn.writefile({ "local a = 1", "local b = 2", "local c = 3" }, file)

vim.cmd.edit(file)
local bufnr = vim.api.nvim_get_current_buf()

--- Live breakpoints in the sample buffer, keyed by line.
local function live_lines()
	local out = {}
	for _, bp in ipairs(dap_bp.get(bufnr)[bufnr] or {}) do
		out[bp.line] = bp
	end
	return out
end

--- Number of disabled signs in the sample buffer.
local function disabled_count()
	local placed = vim.fn.sign_getplaced(bufnr, { group = krs.settings.sign_group })
	return #((placed[1] or {}).signs or {})
end

describe("dap_breakpoints enable/disable", function()
	it("disabling removes the breakpoint from dap but keeps a sign", function()
		dap_bp.set({ condition = "a == 1" }, bufnr, 2)
		expect(live_lines()[2]).toBeDefined()

		expect(krs.disable_at(bufnr, 2)).toBeTruthy()
		expect(live_lines()[2]).toBeNil()
		expect(disabled_count()).toBe(1)
	end)

	it("enabling restores the breakpoint with its condition", function()
		expect(krs.enable_at(bufnr, 2)).toBeTruthy()
		expect(live_lines()[2].condition).toBe("a == 1")
		expect(disabled_count()).toBe(0)
	end)
end)

describe("dap_breakpoints persistence", function()
	it("saves live and disabled breakpoints under a project-relative path", function()
		dap_bp.set({}, bufnr, 3)
		krs.disable_at(bufnr, 3)
		krs.save_breakpoints(root)

		local saved = require("krs.core.store").load(krs.get_breakpoints_filepath(root))
		local entries = saved.breakpoints["sample.lua"]
		expect(entries).toHaveLength(2)

		local by_line = {}
		for _, e in ipairs(entries) do
			by_line[e.line] = e
		end
		expect(by_line[2].enabled).toBe(true)
		expect(by_line[2].condition).toBe("a == 1")
		expect(by_line[3].enabled).toBe(false)
	end)

	it("remove_all clears the buffer and persists the empty set", function()
		local json_path = krs.get_breakpoints_filepath(root)
		local backup = vim.fn.readfile(json_path)

		krs.remove_all()
		expect(vim.tbl_isempty(live_lines())).toBeTruthy()
		expect(disabled_count()).toBe(0)
		expect(require("krs.core.store").load(json_path).breakpoints["sample.lua"]).toBeNil()

		-- Put the file back for the restore test below.
		vim.fn.writefile(backup, json_path)
	end)

	it("restores enabled and disabled breakpoints as they were", function()
		krs.restore_for_buffer(bufnr, root)

		expect(live_lines()[2]).toBeDefined()
		expect(live_lines()[3]).toBeNil()
		expect(disabled_count()).toBe(1)
	end)
end)

describe("dap_breakpoints bulk actions", function()
	it("disable_all moves every breakpoint to the disabled group", function()
		krs.disable_all()

		expect(vim.tbl_isempty(live_lines())).toBeTruthy()
		expect(disabled_count()).toBe(2)
	end)

	it("enable_all brings them all back", function()
		krs.enable_all()

		expect(live_lines()[2]).toBeDefined()
		expect(live_lines()[3]).toBeDefined()
		expect(disabled_count()).toBe(0)
	end)
end)
