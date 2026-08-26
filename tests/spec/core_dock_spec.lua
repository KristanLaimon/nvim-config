-- ============================================================================
-- tests/spec/core_dock_spec.lua -- The bottom dock shared by terminals & tasks.
-- ============================================================================
-- The rule under test: a task output is a terminal buffer too, so the task check
-- has to win, or every task output would be classified as a plain terminal and
-- the two panes would fight over the same side of the dock.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach
local dock = require("krs.core.dock")

local opened_windows = {}

--- Opens a scratch window in a split and tags its buffer.
--- @param tag "task"|"terminal"|"plain"
--- @return integer win
local function open_window(tag)
	vim.cmd("botright split")
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)

	if tag == "task" then
		vim.b[buf].krs_is_task = true
		vim.bo[buf].filetype = dock.task_filetype
	elseif tag == "terminal" then
		vim.b[buf].krs_is_multi_term = true
	end

	table.insert(opened_windows, win)
	return win
end

describe("krs.core.dock.classify", function()
	afterEach(function()
		for _, win in ipairs(opened_windows) do
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
		opened_windows = {}
	end)

	it("recognizes a task output window", function()
		local is_task, is_term = dock.classify(open_window("task"))

		expect(is_task).toBeTruthy()
		expect(is_term).toBeFalsy()
	end)

	it("recognizes a multi-terminal window", function()
		local is_task, is_term = dock.classify(open_window("terminal"))

		expect(is_task).toBeFalsy()
		expect(is_term).toBeTruthy()
	end)

	it("reports an ordinary window as neither", function()
		local is_task, is_term = dock.classify(open_window("plain"))

		expect(is_task).toBeFalsy()
		expect(is_term).toBeFalsy()
	end)

	it("reports an invalid window as neither instead of throwing", function()
		local win = open_window("plain")
		pcall(vim.api.nvim_win_close, win, true)

		local is_task, is_term = dock.classify(win)
		expect(is_task).toBeFalsy()
		expect(is_term).toBeFalsy()
	end)

	it("finds the task and terminal panes independently", function()
		open_window("task")
		open_window("terminal")

		local task_win, term_win = dock.find()
		expect(task_win).toBeDefined()
		expect(term_win).toBeDefined()
		expect(task_win == term_win).toBeFalsy()
	end)

	it("reports no panes when the dock is empty", function()
		local task_win, term_win = dock.find()

		expect(task_win).toBeNil()
		expect(term_win).toBeNil()
	end)
end)
