-- ============================================================================
-- tests/spec/tailwind_organizer_spec.lua -- Class sorting and rewriting.
-- ============================================================================
-- Pure string work, so all of it is testable: which row a utility lands in, the
-- order inside a row, when the output stays on one line, and which attribute
-- forms get rewritten.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local tw = require("plugins.krs.tailwind_organizer")

--- Organizes a class string with multi-line output forced on, so the row
--- structure is visible regardless of length heuristics.
local function rows(classes)
	local previous = tw.settings.min_classes_for_multiline
	tw.settings.min_classes_for_multiline = 1
	tw.settings.force_multiline = true

	local out = tw.organize_classes(classes, "", "")

	tw.settings.min_classes_for_multiline = previous
	tw.settings.force_multiline = false

	local result = {}
	for line in out:gmatch("[^\n]+") do
		table.insert(result, line)
	end
	return result
end

describe("tailwind organize_classes rows", function()
	it("splits layout, aesthetic, hover and responsive classes", function()
		local result = rows("text-red-500 flex hover:bg-blue-500 md:w-10")

		expect(result).toEqual({ "flex", "text-red-500", "hover:bg-blue-500", "md:w-10" })
	end)

	it("puts display and position before dimensions, then the rest", function()
		local result = rows("gap-2 w-10 absolute")

		expect(result[1]).toBe("absolute w-10 gap-2")
	end)

	it("alphabetizes the aesthetic row", function()
		local result = rows("text-white bg-black border")

		expect(result[1]).toBe("bg-black border text-white")
	end)

	it("emits one row per breakpoint, in breakpoint order", function()
		local result = rows("2xl:flex sm:flex lg:flex")

		expect(result).toEqual({ "sm:flex", "lg:flex", "2xl:flex" })
	end)

	it("treats a non-responsive prefix (dark:) as an aesthetic class", function()
		local result = rows("dark:flex sm:flex")

		expect(result).toEqual({ "dark:flex", "sm:flex" })
	end)

	it("drops duplicate classes", function()
		expect(tw.organize_classes("flex flex flex", "", "")).toBe("flex")
	end)

	it("returns an empty string for empty input", function()
		expect(tw.organize_classes("", "", "")).toBe("")
	end)
end)

describe("tailwind single-line heuristic", function()
	it("keeps short class lists on one line", function()
		local out = tw.organize_classes("flex w-10 text-red-500", "  ", "")

		expect(out).toBe("flex w-10 text-red-500")
		expect(out).not_.toContain("\n")
	end)

	it("breaks long class lists into rows", function()
		local long = "flex w-10 h-10 gap-2 p-4 m-2 text-white bg-black border rounded"

		expect(tw.organize_classes(long, "  ", "")).toContain("\n")
	end)
end)

describe("tailwind organize_full_text", function()
	it("rewrites a double-quoted class attribute", function()
		local out = tw.organize_full_text('<div class="text-red-500 flex"></div>')

		expect(out).toBe('<div class="flex text-red-500"></div>')
	end)

	it("rewrites single-quoted and JSX template attributes", function()
		expect(tw.organize_full_text("<div class='text-red-500 flex'></div>")).toBe("<div class='flex text-red-500'></div>")
		expect(tw.organize_full_text("<div className={`text-red-500 flex`}></div>")).toBe(
			"<div className={`flex text-red-500`}></div>"
		)
	end)

	it("handles the framework :class binding form", function()
		expect(tw.organize_full_text('<div :class="text-red-500 flex"></div>')).toBe(
			'<div :class="flex text-red-500"></div>'
		)
	end)

	it("leaves class:list alone -- the attribute pattern stops at the colon", function()
		local source = '<div class:list="text-red-500 flex"></div>'

		expect(tw.organize_full_text(source)).toBe(source)
	end)

	it("collapses an attribute that holds only whitespace", function()
		expect(tw.organize_full_text('<div class="   "></div>')).toBe('<div class=""></div>')
	end)

	it("leaves text with no class attributes untouched", function()
		local source = 'local x = "flex w-10"\nprint(x)'

		expect(tw.organize_full_text(source)).toBe(source)
	end)

	it("reports how many lines were added before the cursor", function()
		local long = "flex w-10 h-10 gap-2 p-4 m-2 text-white bg-black border rounded"
		local _, added = tw.organize_full_text('<div class="' .. long .. '"></div>', math.huge)

		expect(added).toBeGreaterThan(0)
	end)
end)
