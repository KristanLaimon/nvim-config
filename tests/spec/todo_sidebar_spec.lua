-- ============================================================================
-- tests/spec/todo_sidebar_spec.lua -- Todo & comments right sidebar test suite.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local todo = require("plugins.krs.tools.todo_sidebar")
local cp = require("plugins.krs.tools.command_palette")

describe("plugins.krs.tools.todo_sidebar", function()
	beforeEach(function()
		todo.setup()
	end)

	afterEach(function()
		if todo.is_open() then
			todo.close()
		end
	end)

	it("registers user commands upon setup", function()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["TodoSidebar"]).toBeDefined()
		expect(cmds["TodoToggle"]).toBeDefined()
		expect(cmds["TodoRefresh"]).toBeDefined()
		expect(cmds["TodoSearch"]).toBeDefined()
		expect(cmds["TodoFilter"]).toBeDefined()
	end)

	it("registers keymaps <leader>td and <C-S-o>", function()
		local map_td = vim.fn.maparg("<leader>td", "n", false, true)
		local map_cso = vim.fn.maparg("<C-S-o>", "n", false, true)
		expect(map_td).toBeDefined()
		expect(map_td.lhs:match("td$")).toBe("td")
		expect(map_cso).toBeDefined()
	end)

	it("parses single-line // TODO comments across languages", function()
		local line = "  // TODO: implement user authentication"
		local item = todo.parse_comment_line(line, "src/auth.ts", 12)
		expect(item).toBeDefined()
		expect(item.tag).toBe("TODO")
		expect(item.file).toBe("src/auth.ts")
		expect(item.line).toBe(12)
		expect(item.text).toBe("implement user authentication")
	end)

	it("parses multi-line /* FIXME */ comments with author", function()
		local line = "  /* FIXME(kristan): memory leak when buffer closes */"
		local item = todo.parse_comment_line(line, "src/engine.c", 45)
		expect(item).toBeDefined()
		expect(item.tag).toBe("FIXME")
		expect(item.extra).toBe("(kristan)")
		expect(item.text).toBe("memory leak when buffer closes")
	end)

	it("parses multi-line continuation lines starting with *", function()
		local line = "   * NOTE: required for Windows WSL path translation"
		local item = todo.parse_comment_line(line, "src/wsl.cpp", 89)
		expect(item).toBeDefined()
		expect(item.tag).toBe("NOTE")
		expect(item.text).toBe("required for Windows WSL path translation")
	end)

	it("parses HTML / XML <!-- HACK --> comments", function()
		local line = "  <!-- HACK: override Tailwind grid template columns -->"
		local item = todo.parse_comment_line(line, "templates/index.html", 30)
		expect(item).toBeDefined()
		expect(item.tag).toBe("HACK")
		expect(item.text).toBe("override Tailwind grid template columns")
	end)

	it("parses Python # WARN and docstring comments", function()
		local line = "  # WARN: do not call before database connection"
		local item = todo.parse_comment_line(line, "app/db.py", 102)
		expect(item).toBeDefined()
		expect(item.tag).toBe("WARN")
		expect(item.text).toBe("do not call before database connection")

		local doc_line = '  """ PERF: vectorize calculation with numpy """'
		local doc_item = todo.parse_comment_line(doc_line, "app/math.py", 55)
		expect(doc_item).toBeDefined()
		expect(doc_item.tag).toBe("PERF")
		expect(doc_item.text).toBe("vectorize calculation with numpy")
	end)

	it("parses Lua -- BUG and block comments", function()
		local line = "  -- BUG: nil index on empty array"
		local item = todo.parse_comment_line(line, "lua/core.lua", 67)
		expect(item).toBeDefined()
		expect(item.tag).toBe("BUG")
		expect(item.text).toBe("nil index on empty array")
	end)

	it("parses SAFETY, TEST, and REVIEW tags", function()
		local line_safety = "  // SAFETY: pointer dereference is bounds-checked"
		local item_safety = todo.parse_comment_line(line_safety, "src/mem.rs", 15)
		expect(item_safety).toBeDefined()
		expect(item_safety.tag).toBe("SAFETY")
		expect(item_safety.text).toBe("pointer dereference is bounds-checked")

		local line_test = "  // TEST: add unit test for negative numbers"
		local item_test = todo.parse_comment_line(line_test, "src/calc.go", 24)
		expect(item_test).toBeDefined()
		expect(item_test.tag).toBe("TEST")
		expect(item_test.text).toBe("add unit test for negative numbers")

		local line_review = "  // REVIEW: should we use a channel instead?"
		local item_review = todo.parse_comment_line(line_review, "src/worker.go", 80)
		expect(item_review).toBeDefined()
		expect(item_review.tag).toBe("REVIEW")
		expect(item_review.text).toBe("should we use a channel instead?")
	end)

	it("ignores regular code lines without comment tags", function()
		local code = "  local info = header:sub(4)"
		local item = todo.parse_comment_line(code, "lua/test.lua", 1)
		expect(item).toBeNil()

		local code2 = "  local total_todo = #items + 1"
		local item2 = todo.parse_comment_line(code2, "lua/test.lua", 2)
		expect(item2).toBeNil()
	end)

	it("toggles the right sidebar window open and closed cleanly", function()
		expect(todo.is_open()).toBe(false)
		todo.toggle()
		expect(todo.is_open()).toBe(true)

		local win = todo.state.win
		expect(vim.api.nvim_win_is_valid(win)).toBe(true)
		local buf = todo.state.buf
		expect(vim.bo[buf].filetype).toBe("krs_todo_sidebar")

		todo.toggle()
		expect(todo.is_open()).toBe(false)
	end)

	it("includes Todo Sidebar in Command Palette", function()
		local found = false
		for _, cmd in ipairs(cp.commands) do
			if cmd.cmd == "TodoToggle" or cmd.cmd == "TodoSidebar" then
				found = true
				break
			end
		end
		expect(found).toBe(true)
	end)
end)
