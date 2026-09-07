-- ============================================================================
-- tests/spec/smart_close_spec.lua -- Buffer cleaner smart tab close tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach
local buffer_cleaner = require("plugins.krs.editor.buffer_cleaner")

describe("plugins.krs.editor.buffer_cleaner tab navigation", function()
	buffer_cleaner.setup()

	local test_files = {}

	local function create_file(name)
		local tmp = vim.fn.tempname() .. "_" .. name
		local f = io.open(tmp, "w")
		if f then
			f:write("test content for " .. name .. "\n")
			f:close()
		end
		table.insert(test_files, tmp)
		return tmp
	end

	local function wipe_all_buffers()
		local scratch = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(scratch)
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if b ~= scratch and vim.api.nvim_buf_is_valid(b) then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end
	end

	afterEach(function()
		wipe_all_buffers()
		for _, f in ipairs(test_files) do
			os.remove(f)
		end
		test_files = {}
	end)

	it("exposes _G.Smart_Close_Tab as a function", function()
		expect(type(_G.Smart_Close_Tab)).toBe("function")
		expect(type(_G.Smart_Close_Buffer)).toBe("function")
	end)

	it("switches to the right tab when closing a middle tab", function()
		local f1 = create_file("tab1.txt")
		local f2 = create_file("tab2.txt")
		local f3 = create_file("tab3.txt")

		vim.cmd("edit " .. vim.fn.fnameescape(f1))
		vim.cmd("edit " .. vim.fn.fnameescape(f2))
		vim.cmd("edit " .. vim.fn.fnameescape(f3))

		-- Navigate to tab2
		vim.cmd("buffer " .. vim.fn.fnameescape(f2))
		expect(vim.fn.expand("%:t")).toContain("tab2.txt")

		_G.Smart_Close_Tab()

		-- Tab 2 closed: should open its right tab (tab3)
		expect(vim.fn.expand("%:t")).toContain("tab3.txt")
	end)

	it("switches to the left tab when closing the rightmost (last) tab", function()
		local f1 = create_file("first.txt")
		local f2 = create_file("last.txt")

		vim.cmd("edit " .. vim.fn.fnameescape(f1))
		vim.cmd("edit " .. vim.fn.fnameescape(f2))
		expect(vim.fn.expand("%:t")).toContain("last.txt")

		_G.Smart_Close_Tab()

		-- Rightmost tab closed: should open the left tab (first)
		expect(vim.fn.expand("%:t")).toContain("first.txt")
	end)

	it("switches to the right tab when closing the first tab", function()
		local f1 = create_file("left.txt")
		local f2 = create_file("right.txt")

		vim.cmd("edit " .. vim.fn.fnameescape(f1))
		vim.cmd("edit " .. vim.fn.fnameescape(f2))

		vim.cmd("buffer " .. vim.fn.fnameescape(f1))
		expect(vim.fn.expand("%:t")).toContain("left.txt")

		_G.Smart_Close_Tab()

		-- First tab closed: should open its right tab
		expect(vim.fn.expand("%:t")).toContain("right.txt")
	end)

	it("shows the dashboard when the only active code tab is closed", function()
		local f1 = create_file("only.txt")
		vim.cmd("edit " .. vim.fn.fnameescape(f1))
		expect(vim.fn.expand("%:t")).toContain("only.txt")

		_G.Smart_Close_Tab()

		local cur_buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[cur_buf].filetype
		expect(ft == "alpha" or ft == "dashboard" or vim.api.nvim_buf_get_name(cur_buf) == "").toBeTruthy()
	end)

	it("does not let neo-tree expand to full width when only tab is closed", function()
		local f1 = create_file("code.txt")
		vim.cmd("edit " .. vim.fn.fnameescape(f1))

		-- Open neo-tree sidebar
		vim.cmd("silent! Neotree show")

		_G.Smart_Close_Tab()

		local wins = vim.api.nvim_tabpage_list_wins(0)
		local neotree_w = nil
		local has_other_win = false
		for _, w in ipairs(wins) do
			local b = vim.api.nvim_win_get_buf(w)
			if vim.bo[b].filetype == "neo-tree" then
				neotree_w = vim.api.nvim_win_get_width(w)
			else
				has_other_win = true
			end
		end

		expect(has_other_win).toBeTruthy()
		if neotree_w then
			expect(neotree_w < vim.o.columns).toBeTruthy()
		end
	end)

	it("does not close code window when a floating window is open", function()
		local f1 = create_file("file_a.txt")
		local f2 = create_file("file_b.txt")
		vim.cmd("edit " .. vim.fn.fnameescape(f1))
		vim.cmd("edit " .. vim.fn.fnameescape(f2))

		local cur_win = vim.api.nvim_get_current_win()

		-- Create a floating window
		local fbuf = vim.api.nvim_create_buf(false, true)
		local fwin = vim.api.nvim_open_win(fbuf, false, {
			relative = "cursor",
			row = 1,
			col = 1,
			width = 10,
			height = 3,
		})

		_G.Smart_Close_Tab()

		-- Code window must still be valid
		expect(vim.api.nvim_win_is_valid(cur_win)).toBeTruthy()
		expect(vim.fn.expand("%:t")).toContain("file_a.txt")

		if vim.api.nvim_win_is_valid(fwin) then
			pcall(vim.api.nvim_win_close, fwin, true)
		end
	end)
end)
