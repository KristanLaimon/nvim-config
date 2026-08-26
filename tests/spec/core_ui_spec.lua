-- ============================================================================
-- tests/spec/core_ui_spec.lua -- Contract tests for krs.core.ui.
-- ============================================================================
-- Geometry is the part that used to break: fractional sizes, tiny terminals and
-- floats drifting off-screen. Those rules are pinned here; visual styling is not
-- tested because it carries no logic.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach
local ui = require("krs.core.ui")

local opened = {}

--- Opens a float and remembers it so afterEach can clean up.
local function open(opts)
	local buf, win = ui.float(opts)
	table.insert(opened, win)
	return buf, win
end

describe("krs.core.ui.resolve_size", function()
	it("treats values below 1 as a fraction of the editor", function()
		expect(ui.resolve_size(0.5, 100)).toBe(50)
	end)

	it("treats values of 1 or more as absolute cells", function()
		expect(ui.resolve_size(64, 100)).toBe(64)
	end)

	it("never resolves to zero", function()
		expect(ui.resolve_size(0.001, 10)).toBe(1)
	end)
end)

describe("krs.core.ui.center", function()
	it("centers within the editor", function()
		local row, col = ui.center(vim.o.columns - 10, vim.o.lines - 10)

		expect(row).toBe(math.max(math.floor(10 / 2), ui.min_offset))
		expect(col).toBe(math.max(math.floor(10 / 2), ui.min_offset))
	end)

	it("clamps to min_offset when the float is larger than the editor", function()
		local row, col = ui.center(vim.o.columns * 4, vim.o.lines * 4)

		expect(row).toBe(ui.min_offset)
		expect(col).toBe(ui.min_offset)
	end)
end)

describe("krs.core.ui.scratch_buffer", function()
	it("creates an unlisted throwaway buffer", function()
		local buf = ui.scratch_buffer({ lines = { "a", "b" }, filetype = "krstest" })

		expect(vim.bo[buf].buftype).toBe("nofile")
		expect(vim.bo[buf].bufhidden).toBe("wipe")
		expect(vim.bo[buf].filetype).toBe("krstest")
		expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "a", "b" })
	end)

	it("locks the buffer unless modifiable is requested", function()
		expect(vim.bo[ui.scratch_buffer({})].modifiable).toBeFalsy()
		expect(vim.bo[ui.scratch_buffer({ modifiable = true })].modifiable).toBeTruthy()
	end)
end)

describe("krs.core.ui.float", function()
	afterEach(function()
		for _, win in ipairs(opened) do
			ui.close(win)
		end
		opened = {}
	end)

	it("opens a floating window sized from its content", function()
		local _, win = open({ lines = { "1", "2", "3" }, width = 20 })
		local cfg = vim.api.nvim_win_get_config(win)

		expect(cfg.relative).toBe("editor")
		expect(cfg.width).toBe(20)
		expect(cfg.height).toBe(3)
	end)

	it("accepts fractional sizes", function()
		local _, win = open({ lines = { "x" }, width = 0.5, height = 0.5 })
		local cfg = vim.api.nvim_win_get_config(win)

		expect(cfg.width).toBe(math.floor(vim.o.columns * 0.5))
		expect(cfg.height).toBe(math.floor(vim.o.lines * 0.5))
	end)

	it("reuses a buffer when one is passed in", function()
		local existing = ui.scratch_buffer({ lines = { "keep" } })
		local buf = open({ buf = existing, width = 10, height = 2 })

		expect(buf).toBe(existing)
	end)

	it("close is a no-op on an already closed window", function()
		local _, win = open({ lines = { "x" }, width = 10 })
		ui.close(win)

		-- `not_` because `not` is a Lua keyword and cannot be indexed with a dot.
		expect(function()
			ui.close(win)
		end).not_.toThrow()
	end)
end)

describe("krs.core.ui.close_on_keys", function()
	it("maps every configured dismiss key in the buffer", function()
		local buf, win = open({ lines = { "x" }, width = 10 })
		ui.close_on_keys(buf, win)

		local mapped = {}
		for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
			mapped[map.lhs] = true
		end

		for _, key in ipairs(ui.close_keys) do
			expect(mapped[key]).toBeTruthy()
		end

		ui.close(win)
	end)
end)

describe("krs.core.ui.compute_dual_panel & resize_dual_panel", function()
	it("computes synchronous side-by-side panel geometry", function()
		local geo = ui.compute_dual_panel({ left_ratio = 0.35, width_ratio = 0.80, height_ratio = 0.80, gap = 2 })

		expect(geo.left_ratio).toBe(0.35)
		expect(geo.left_width + geo.right_width + 2).toBe(geo.total_width)
		expect(geo.right_col).toBe(geo.left_col + geo.left_width + 2)
	end)

	it("adjusts split ratio and resizes dual floating windows synchronously", function()
		local b1 = ui.scratch_buffer({ lines = { "left" } })
		local b2 = ui.scratch_buffer({ lines = { "right" } })
		local w1 = vim.api.nvim_open_win(b1, false, { relative = "editor", row = 2, col = 2, width = 20, height = 10 })
		local w2 = vim.api.nvim_open_win(b2, false, { relative = "editor", row = 2, col = 24, width = 40, height = 10 })

		local new_ratio = ui.resize_dual_panel({
			left_win = w1,
			right_win = w2,
			delta = 0.05,
			left_ratio = 0.35,
			width_ratio = 0.80,
			height_ratio = 0.80,
			gap = 2,
		})

		expect(new_ratio).toBe(0.40)

		local cfg1 = vim.api.nvim_win_get_config(w1)
		local cfg2 = vim.api.nvim_win_get_config(w2)

		expect(cfg2.col).toBe(cfg1.col + cfg1.width + 2)

		pcall(vim.api.nvim_win_close, w1, true)
		pcall(vim.api.nvim_win_close, w2, true)
	end)
end)
