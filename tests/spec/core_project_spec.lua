-- ============================================================================
-- tests/spec/core_project_spec.lua -- Contract tests for krs.core.project.
-- ============================================================================
-- Lookup ORDER is the contract here: `.krsnvim` wins over `.krslocal`, which wins
-- over the legacy `.nvimkrs`. A regression silently loads another directory's
-- settings, so each precedence rule gets its own test.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local project = require("krs.core.project")
local path = require("krs.core.path")

local root

--- Creates `<root>/<dir>/<name>` with placeholder JSON content.
local function touch_config(dir, name)
	local full = path.join(root, dir, name)
	path.ensure_dir(vim.fs.dirname(full))
	vim.fn.writefile({ "{}" }, full)
	return full
end

describe("krs.core.project.config_path", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
	end)

	afterEach(function()
		vim.fn.delete(root, "rf")
	end)

	it("defaults to .krsnvim when nothing exists yet", function()
		local file, exists = project.config_path("tasks.json", root)

		expect(file).toBe(path.join(root, ".krsnvim", "tasks.json"))
		expect(exists).toBeFalsy()
	end)

	it("finds an existing .krsnvim config", function()
		local expected = touch_config(".krsnvim", "launch.json")
		local file, exists = project.config_path("launch.json", root)

		expect(file).toBe(expected)
		expect(exists).toBeTruthy()
	end)

	it("falls back to .krslocal when .krsnvim has no such file", function()
		local expected = touch_config(".krslocal", "launch.json")

		expect(project.config_path("launch.json", root)).toBe(expected)
	end)

	it("falls back to the legacy .nvimkrs directory last", function()
		local expected = touch_config(".nvimkrs", "launch.json")

		expect(project.config_path("launch.json", root)).toBe(expected)
	end)

	it("prefers .krsnvim when several candidates exist", function()
		local expected = touch_config(".krsnvim", "launch.json")
		touch_config(".krslocal", "launch.json")
		touch_config(".nvimkrs", "launch.json")

		expect(project.config_path("launch.json", root)).toBe(expected)
	end)
end)

describe("krs.core.project.config_dir", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
	end)

	afterEach(function()
		vim.fn.delete(root, "rf")
	end)

	it("creates and returns <root>/.krsnvim", function()
		local dir = project.config_dir(root)

		expect(dir).toBe(path.join(root, ".krsnvim"))
		expect(path.is_dir(dir)).toBeTruthy()
	end)
end)

describe("krs.core.project.root", function()
	it("stops at the nearest marker directory", function()
		local base = path.normalize(vim.fn.tempname())
		local nested = path.join(base, "src", "deep")
		path.ensure_dir(nested)
		vim.fn.writefile({ "{}" }, path.join(base, "package.json"))

		local found = path.normalize(vim.fs.dirname(vim.fs.find(project.root_markers, {
			upward = true,
			path = nested,
		})[1]))

		expect(found).toBe(base)
		vim.fn.delete(base, "rf")
	end)

	it("falls back to the cwd when no marker is found", function()
		local orig = project.root_markers
		project.root_markers = { "this-marker-never-exists-krs" }

		expect(path.normalize(project.root())).toBe(path.normalize(vim.fn.getcwd()))

		project.root_markers = orig
	end)
end)
