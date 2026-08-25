-- ============================================================================
-- tests/spec/git_submodules_spec.lua -- Submodule parsing, discovery and listing.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local submodules = require("krs.git.submodules")

describe("git submodules parse_submodules", function()
	it("parses submodule status lines with various status prefixes", function()
		local lines = {
			" 68b5a03bf18274a2b130e9d57a91176b91176b91 lua/plugins/foo (v1.0.0)",
			"+1234567890abcdef1234567890abcdef12345678 themes/bar",
			"-abcdef1234567890abcdef1234567890abcdef12 libs/baz",
			"U9999999999999999999999999999999999999999 core/qux (heads/main)",
		}

		local parsed = submodules.parse_submodules(lines)
		expect(parsed).toEqual({
			"lua/plugins/foo",
			"themes/bar",
			"libs/baz",
			"core/qux",
		})
	end)

	it("parses git config format for .gitmodules", function()
		local lines = {
			"submodule.libA.path deps/libA",
			"submodule.libB.path deps/libB",
		}

		local parsed = submodules.parse_submodules(lines)
		expect(parsed).toEqual({
			"deps/libA",
			"deps/libB",
		})
	end)

	it("handles empty or malformed lines gracefully", function()
		local lines = {
			"",
			"   ",
			"fatal: not a git repository",
		}

		local parsed = submodules.parse_submodules(lines)
		expect(parsed).toEqual({})
	end)

	it("deduplicates repeated submodule paths", function()
		local lines = {
			" 1111111111111111111111111111111111111111 plugins/foo",
			"+2222222222222222222222222222222222222222 plugins/foo",
		}

		local parsed = submodules.parse_submodules(lines)
		expect(parsed).toEqual({ "plugins/foo" })
	end)
end)

describe("git submodules discover", function()
	it("skips both git calls when the repo has no .gitmodules file", function()
		local tmp_dir = vim.fn.tempname()
		vim.fn.mkdir(tmp_dir .. "/.git", "p")

		local git = require("krs.git.cmd")
		local original_lines = git.lines
		local calls = 0
		git.lines = function(...)
			calls = calls + 1
			return original_lines(...)
		end

		local paths = submodules.discover(tmp_dir)

		git.lines = original_lines
		vim.fn.delete(tmp_dir, "rf")

		expect(paths).toEqual({})
		expect(calls).toBe(0)
	end)
end)

describe("git submodules caching", function()
	--- A fake repo directory whose `.gitmodules` is real, so the git-config
	--- fallback (which reads the file directly, no real repository needed)
	--- resolves the submodule list even though `.git` is just an empty dir.
	local function make_repo_with_gitmodules(paths)
		local tmp_dir = vim.fn.tempname()
		vim.fn.mkdir(tmp_dir .. "/.git", "p")

		local lines = {}
		for _, p in ipairs(paths) do
			table.insert(lines, string.format('[submodule "%s"]', p))
			table.insert(lines, "\tpath = " .. p)
			table.insert(lines, "\turl = https://example.com/" .. p .. ".git")
		end
		vim.fn.writefile(lines, tmp_dir .. "/.gitmodules")
		return tmp_dir
	end

	it("caches the discovered paths and makes zero git calls on the next discover()", function()
		local tmp_dir = make_repo_with_gitmodules({ "libs/a", "libs/b" })

		local first = submodules.discover(tmp_dir)
		expect(first).toEqual({ "libs/a", "libs/b" })

		local git = require("krs.git.cmd")
		local original_spawn, original_lines = git.spawn, git.lines
		local spawn_calls, lines_calls = 0, 0
		git.spawn = function(...)
			spawn_calls = spawn_calls + 1
			return original_spawn(...)
		end
		git.lines = function(...)
			lines_calls = lines_calls + 1
			return original_lines(...)
		end

		local second = submodules.discover(tmp_dir)

		git.spawn = original_spawn
		git.lines = original_lines
		vim.fn.delete(tmp_dir, "rf")

		expect(second).toEqual({ "libs/a", "libs/b" })
		expect(spawn_calls).toBe(0)
		expect(lines_calls).toBe(0)
	end)

	it("invalidates the cache when .gitmodules changes size, even from outside Git Center", function()
		local tmp_dir = make_repo_with_gitmodules({ "libs/a" })
		expect(submodules.discover(tmp_dir)).toEqual({ "libs/a" })

		-- Simulate a plain `git submodule add` run from a terminal, not Git
		-- Center: the file is rewritten by something else entirely.
		local lines = {
			'[submodule "libs/a"]',
			"\tpath = libs/a",
			"\turl = https://example.com/a.git",
			'[submodule "libs/b"]',
			"\tpath = libs/b",
			"\turl = https://example.com/b.git",
		}
		vim.fn.writefile(lines, tmp_dir .. "/.gitmodules")

		local second = submodules.discover(tmp_dir)
		vim.fn.delete(tmp_dir, "rf")

		expect(second).toEqual({ "libs/a", "libs/b" })
	end)

	it("discover_start returns an immediate result with no finisher on a cache hit", function()
		local tmp_dir = make_repo_with_gitmodules({ "libs/a" })
		submodules.discover(tmp_dir) -- warm the cache

		local immediate, finish = submodules.discover_start(tmp_dir)
		vim.fn.delete(tmp_dir, "rf")

		expect(immediate).toEqual({ "libs/a" })
		expect(finish).toBeNil()
	end)

	it("discover_start returns a finisher, not an immediate result, on a cache miss", function()
		local tmp_dir = make_repo_with_gitmodules({ "libs/a" })

		local immediate, finish = submodules.discover_start(tmp_dir)

		expect(immediate).toBeNil()
		expect(type(finish)).toBe("function")
		expect(finish()).toEqual({ "libs/a" })

		vim.fn.delete(tmp_dir, "rf")
	end)
end)

describe("git submodules list", function()
	it("returns root repo as first entry", function()
		local list = submodules.list("C:/dev/my-project")
		expect(#list >= 1).toBeTruthy()
		expect(list[1].is_root).toBe(true)
		expect(list[1].path).toBe(".")
		expect(list[1].name).toBe("📦 my-project (Root)")
		expect(list[1].full_path).toBe("C:/dev/my-project")
	end)
end)
