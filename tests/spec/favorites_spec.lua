-- ============================================================================
-- tests/spec/favorites_spec.lua -- Starred paths shared by explorer & projects.
-- ============================================================================
-- The storage KEY is the contract: existing favorites files were written with
-- forward slashes, no trailing slash and a lowercased drive letter. Change that
-- rule and every saved favorite silently disappears from the UI.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local favorites = require("krs.projects.favorites")

local original_file

describe("krs.projects.favorites", function()
	beforeEach(function()
		original_file = favorites.file
		favorites.file = vim.fn.tempname() .. ".json"
	end)

	afterEach(function()
		vim.fn.delete(favorites.file)
		favorites.file = original_file
	end)

	it("normalizes separators and trailing slashes in the key", function()
		expect(favorites.key([[C:\Users\me\project\]])).toBe(favorites.key("C:/Users/me/project"))
	end)

	it("keeps the key stable across drive letter case", function()
		if favorites.key("C:/proj") ~= "c:/proj" then
			-- Not Windows or WSL: the drive rule does not apply.
			return
		end
		expect(favorites.key("C:/proj")).toBe(favorites.key("c:/proj"))
	end)

	it("returns an empty key for nil or empty input", function()
		expect(favorites.key(nil)).toBe("")
		expect(favorites.key("")).toBe("")
	end)

	it("starts with nothing starred", function()
		expect(favorites.load()).toEqual({})
		expect(favorites.is("C:/proj")).toBeFalsy()
	end)

	it("toggles a path on and off, reporting the new state", function()
		expect(favorites.toggle("C:/proj")).toBeTruthy()
		expect(favorites.is("C:/proj")).toBeTruthy()

		expect(favorites.toggle("C:/proj")).toBeFalsy()
		expect(favorites.is("C:/proj")).toBeFalsy()
	end)

	it("recognizes the same path written differently", function()
		favorites.toggle([[C:\proj\]])

		expect(favorites.is("C:/proj")).toBeTruthy()
	end)

	it("moves a favorite when a project is renamed", function()
		favorites.toggle("C:/proj/old")
		favorites.move("C:/proj/old", "C:/proj/new")

		expect(favorites.is("C:/proj/old")).toBeFalsy()
		expect(favorites.is("C:/proj/new")).toBeTruthy()
	end)

	it("does not star the target when the source was not a favorite", function()
		favorites.move("C:/proj/old", "C:/proj/new")

		expect(favorites.is("C:/proj/new")).toBeFalsy()
	end)

	it("removes a favorite, and ignores removing one that is absent", function()
		favorites.toggle("C:/proj")
		favorites.remove("C:/proj")
		favorites.remove("C:/proj")

		expect(favorites.load()).toEqual({})
	end)
end)
