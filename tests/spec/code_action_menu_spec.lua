-- ============================================================================
-- tests/spec/code_action_menu_spec.lua -- Ordering of the <C-.> dropdown.
-- ============================================================================
-- Raw LSP code action order is close to arbitrary, and the first entry is the one
-- reached by muscle memory. This pins the ranking: preferred first, then
-- quickfixes, then refactors, then whole-file sources -- ties keeping their
-- original order so the list does not shuffle between identical requests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local menu = require("krs.lsp.code_action_menu")

--- Names of the actions, in the order the menu would show them.
--- @param items table[] Raw items.
--- @return string[] titles
local function order_of(items)
	local titles = {}
	for _, item in ipairs(menu.sort_items(items)) do
		titles[#titles + 1] = (item.action or item).title
	end
	return titles
end

describe("code_action_menu.sort_items", function()
	it("puts a preferred action first, whatever its kind", function()
		local titles = order_of({
			{ title = "organize", kind = "source.organizeImports" },
			{ title = "the one", kind = "refactor", isPreferred = true },
		})

		expect(titles[1]).toBe("the one")
	end)

	it("ranks quickfix above refactor above source", function()
		local titles = order_of({
			{ title = "source", kind = "source" },
			{ title = "refactor", kind = "refactor" },
			{ title = "quickfix", kind = "quickfix" },
		})

		expect(titles).toEqual({ "quickfix", "refactor", "source" })
	end)

	it("puts refactor.rewrite ahead of plain refactor", function()
		local titles = order_of({
			{ title = "plain", kind = "refactor" },
			{ title = "rewrite", kind = "refactor.rewrite" },
		})

		expect(titles).toEqual({ "rewrite", "plain" })
	end)

	it("sends unknown kinds to the end", function()
		local titles = order_of({
			{ title = "mystery", kind = "something.new" },
			{ title = "fix", kind = "quickfix" },
		})

		expect(titles).toEqual({ "fix", "mystery" })
	end)

	it("keeps the original order for equal ranks", function()
		local titles = order_of({
			{ title = "first", kind = "quickfix" },
			{ title = "second", kind = "quickfix" },
			{ title = "third", kind = "quickfix" },
		})

		expect(titles).toEqual({ "first", "second", "third" })
	end)

	it("reads the nested `action` table used by nvim's LSP client", function()
		local titles = order_of({
			{ action = { title = "wrapped source", kind = "source" } },
			{ action = { title = "wrapped fix", kind = "quickfix" } },
		})

		expect(titles).toEqual({ "wrapped fix", "wrapped source" })
	end)

	it("returns an empty list unchanged", function()
		expect(menu.sort_items({})).toEqual({})
	end)
end)
