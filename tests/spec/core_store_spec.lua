-- ============================================================================
-- tests/spec/core_store_spec.lua -- Contract tests for krs.core.store.
-- ============================================================================
-- The store is the persistence layer for tasks, launch profiles, breakpoints and
-- workspaces. Its promise is "reads never throw": a corrupt file must degrade to
-- the caller's fallback instead of breaking the editor at startup.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local store = require("krs.core.store")

local tmp_dir

describe("krs.core.store", function()
	beforeEach(function()
		tmp_dir = vim.fn.tempname()
		vim.fn.mkdir(tmp_dir, "p")
	end)

	afterEach(function()
		vim.fn.delete(tmp_dir, "rf")
	end)

	it("round-trips a table through save and load", function()
		local file = tmp_dir .. "/data.json"
		local ok = store.save(file, { name = "krs", count = 3 })

		expect(ok).toBeTruthy()
		expect(store.load(file)).toEqual({ name = "krs", count = 3 })
	end)

	it("creates missing parent directories on save", function()
		local file = tmp_dir .. "/nested/deep/data.json"
		expect(store.save(file, { a = 1 })).toBeTruthy()
		expect(vim.fn.filereadable(file)).toBe(1)
	end)

	it("returns the fallback for a missing file", function()
		expect(store.load(tmp_dir .. "/absent.json", { default = true })).toEqual({ default = true })
	end)

	it("returns an empty table when no fallback is given", function()
		expect(store.load(tmp_dir .. "/absent.json")).toEqual({})
	end)

	it("returns the fallback for malformed JSON instead of throwing", function()
		local file = tmp_dir .. "/broken.json"
		vim.fn.writefile({ "{ this is not json" }, file)

		expect(store.load(file, { safe = true })).toEqual({ safe = true })
	end)

	it("returns the fallback for an empty file", function()
		local file = tmp_dir .. "/empty.json"
		vim.fn.writefile({}, file)

		expect(store.load(file, { safe = true })).toEqual({ safe = true })
	end)

	it("refuses to serialize non-table values", function()
		local ok, err = store.save(tmp_dir .. "/bad.json", "not a table")

		expect(ok).toBeFalsy()
		expect(err).toContain("expects a table")
	end)

	it("read_file returns nil for a missing file", function()
		expect(store.read_file(tmp_dir .. "/nope.txt")).toBeNil()
	end)

	it("write_file then read_file preserves content", function()
		local file = tmp_dir .. "/note.txt"
		store.write_file(file, "hello\nworld")

		expect(store.read_file(file)).toBe("hello\nworld")
	end)

	it("serializes object keys in sorted order regardless of insertion order", function()
		local file = tmp_dir .. "/order.json"

		local first = {}
		first.font_size = 14
		first.font_name = "JetBrainsMono"
		store.save(file, first)
		local encoded_a = store.read_file(file)

		local second = {}
		second.font_name = "JetBrainsMono"
		second.font_size = 14
		store.save(file, second)
		local encoded_b = store.read_file(file)

		expect(encoded_a).toBe(encoded_b)
		expect(encoded_a).toBe('{"font_name":"JetBrainsMono","font_size":14}')
	end)

	it("keeps array element order stable while sorting nested object keys", function()
		local file = tmp_dir .. "/nested.json"
		store.save(file, { list = { 3, 1, 2 }, z = 1, a = 2 })

		expect(store.read_file(file)).toBe('{"a":2,"list":[3,1,2],"z":1}')
	end)
end)
