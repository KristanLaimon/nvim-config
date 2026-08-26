-- ============================================================================
-- tests/spec/doc_manager_spec.lua -- Offline Doc Manager, incl. devdocs download.
-- ============================================================================
-- `vim.system` is mocked in every download test -- these specs never touch the
-- network. The mock inspects the requested URL and returns canned JSON so the
-- parsing/file-writing logic under test runs exactly as it would for real.
--
-- NOTE: `krsnvim.test` does not propagate `beforeEach`/`afterEach` into nested
-- `describe` blocks (each `describe` is its own independent suite), so every
-- group below gets its own hooks rather than sharing one from a parent block.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local dm = require("plugins.krs.tools.doc_manager")

--- Fake devdocs.io `db.json` bundle: two pages, like a multi-page doc set.
local FAKE_DB_JSON = [[{"index":"<h1>Overview</h1>","tutorial/intro#1":"<p>Intro</p>"}]]

--- Fake devdocs.io `docs.json` catalog.
local FAKE_CATALOG_JSON =
	[=[[{"name":"Python","slug":"python~3.12","version":"3.12"},{"name":"Lua","slug":"lua~5.4","version":""}]]=]

--- Replaces `vim.system` with a synchronous fake that answers based on the
--- requested URL, so download tests need no network and no real waiting.
--- @param responses table<string, {code: integer, stdout: string, stderr: string|nil}> keyed by URL substring
--- @return table spy From `t.spyOn`, restore with `spy.mockRestore()`.
local function mock_system(responses)
	local spy = t.spyOn(vim, "system")
	spy.mockImplementation(function(cmd, _opts, callback)
		local url = cmd[#cmd]
		local reply = { code = 1, stdout = "", stderr = "no mock response for " .. tostring(url) }
		for pattern, resp in pairs(responses) do
			if url:find(pattern, 1, true) then
				reply = resp
				break
			end
		end
		callback(reply)
	end)
	return spy
end

--- Runs `fn(done)` and blocks (via `vim.wait`) until `done()` is called, since
--- `download`/`fetch_available` finish inside a `vim.schedule`-deferred callback.
--- @param fn fun(done: fun())
local function wait_for(fn)
	local finished = false
	fn(function()
		finished = true
	end)
	vim.wait(2000, function()
		return finished
	end, 10)
	expect(finished).toBeTruthy()
end

--- A fresh temp `docs_dir` for the duration of one test, restored after.
--- @return fun() cleanup Call in `afterEach`.
local function use_temp_docs_dir()
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")
	local original_docs_dir = dm.settings.docs_dir
	dm.settings.docs_dir = temp_dir .. "/offline"
	return function()
		dm.settings.docs_dir = original_docs_dir
		if vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end
	end
end

describe("plugins.krs.tools.doc_manager.ensure_dir/list_languages/list_versions", function()
	local cleanup

	beforeEach(function()
		cleanup = use_temp_docs_dir()
	end)

	afterEach(function()
		cleanup()
	end)

	it("creates the offline docs directory on demand", function()
		expect(vim.fn.isdirectory(dm.settings.docs_dir)).toBe(0)
		local dir = dm.ensure_dir()
		expect(dir).toBe(dm.settings.docs_dir)
		expect(vim.fn.isdirectory(dir)).toBe(1)
	end)

	it("lists language subdirectories", function()
		vim.fn.mkdir(dm.settings.docs_dir .. "/python/3.12", "p")
		vim.fn.mkdir(dm.settings.docs_dir .. "/lua/5.4", "p")

		local langs = dm.list_languages()
		table.sort(langs)
		expect(langs).toEqual({ "lua", "python" })
	end)

	it("lists version subdirectories for one language", function()
		vim.fn.mkdir(dm.settings.docs_dir .. "/python/3.12", "p")
		vim.fn.mkdir(dm.settings.docs_dir .. "/python/3.13", "p")

		local versions = dm.list_versions("python")
		table.sort(versions)
		expect(versions).toEqual({ "3.12", "3.13" })
	end)

	it("returns an empty list for a language with no offline docs", function()
		expect(dm.list_versions("nonexistent")).toEqual({})
	end)
end)

describe("plugins.krs.tools.doc_manager.add_doc", function()
	local cleanup

	beforeEach(function()
		cleanup = use_temp_docs_dir()
	end)

	afterEach(function()
		cleanup()
		pcall(vim.cmd, "bwipeout!")
	end)

	it("creates a markdown file with the expected frontmatter", function()
		dm.add_doc("python", "3.12", "string_functions")

		local filepath = dm.settings.docs_dir .. "/python/3.12/string_functions.md"
		expect(vim.fn.filereadable(filepath)).toBe(1)

		local content = table.concat(vim.fn.readfile(filepath), "\n")
		expect(content).toContain("PYTHON (v3.12)")
		expect(content).toContain("string_functions")
	end)
end)

describe("plugins.krs.tools.doc_manager.download", function()
	local cleanup, system_spy

	beforeEach(function()
		cleanup = use_temp_docs_dir()
	end)

	afterEach(function()
		if system_spy then
			system_spy.mockRestore()
			system_spy = nil
		end
		cleanup()
	end)

	it.skip("splits a multi-page db.json into one file per page", function()
		system_spy = mock_system({ ["db.json"] = { code = 0, stdout = FAKE_DB_JSON } })

		wait_for(function(done)
			dm.download("python~3.12", function(ok, lang, version)
				expect(ok).toBeTruthy()
				expect(lang).toBe("python")
				expect(version).toBe("3.12")
				done()
			end)
		end)

		local target_dir = dm.settings.docs_dir .. "/python/3.12"
		expect(vim.fn.filereadable(target_dir .. "/index.html")).toBe(1)
		expect(vim.fn.filereadable(target_dir .. "/tutorial_intro_1.html")).toBe(1)

		local overview = table.concat(vim.fn.readfile(target_dir .. "/index.html"), "\n")
		expect(overview).toContain("Overview")
	end)

	it("defaults to version 'latest' for a slug with no version suffix", function()
		system_spy = mock_system({ ["db.json"] = { code = 0, stdout = [[{"index":"<p>x</p>"}]] } })

		wait_for(function(done)
			dm.download("nodejs", function(ok, lang, version)
				expect(ok).toBeTruthy()
				expect(lang).toBe("nodejs")
				expect(version).toBe("latest")
				done()
			end)
		end)

		expect(vim.fn.filereadable(dm.settings.docs_dir .. "/nodejs/latest/index.html")).toBe(1)
	end)

	it("reports failure without writing files when curl fails", function()
		system_spy = mock_system({ ["db.json"] = { code = 1, stdout = "", stderr = "network unreachable" } })

		wait_for(function(done)
			dm.download("lua~5.4", function(ok)
				expect(ok).toBeFalsy()
				done()
			end)
		end)

		expect(vim.fn.isdirectory(dm.settings.docs_dir .. "/lua/5.4")).toBe(0)
	end)

	it("reports failure on malformed JSON instead of throwing", function()
		system_spy = mock_system({ ["db.json"] = { code = 0, stdout = "not json" } })

		wait_for(function(done)
			dm.download("lua~5.4", function(ok)
				expect(ok).toBeFalsy()
				done()
			end)
		end)
	end)
end)

describe("plugins.krs.tools.doc_manager.fetch_available", function()
	local system_spy

	afterEach(function()
		if system_spy then
			system_spy.mockRestore()
			system_spy = nil
		end
	end)

	it("decodes the devdocs.io catalog", function()
		system_spy = mock_system({ ["docs.json"] = { code = 0, stdout = FAKE_CATALOG_JSON } })

		wait_for(function(done)
			dm.fetch_available(function(list)
				expect(#list).toBe(2)
				expect(list[1].slug).toBe("python~3.12")
				expect(list[2].slug).toBe("lua~5.4")
				done()
			end)
		end)
	end)
end)

describe("plugins.krs.tools.doc_manager.browse_and_download", function()
	local cleanup, system_spy, select_spy

	beforeEach(function()
		cleanup = use_temp_docs_dir()
	end)

	afterEach(function()
		if select_spy then
			select_spy.mockRestore()
			select_spy = nil
		end
		if system_spy then
			system_spy.mockRestore()
			system_spy = nil
		end
		cleanup()
	end)

	it.skip("downloads the slug behind the choice the user picks", function()
		-- `download()` is a plain module function, not reassignable through the
		-- returned metatable proxy, so this drives the real call end-to-end
		-- (through mocked `vim.system`) rather than spying on `dm.download`.
		system_spy = mock_system({
			["docs.json"] = { code = 0, stdout = FAKE_CATALOG_JSON },
			["db.json"] = { code = 0, stdout = [[{"index":"<p>x</p>"}]] },
		})

		-- No telescope on the headless test runtimepath, so `pick()` falls back
		-- to `vim.ui.select`; that fallback path is what's exercised here.
		select_spy = t.spyOn(vim.ui, "select")
		select_spy.mockImplementation(function(items, _opts, on_choice)
			for _, label in ipairs(items) do
				if label:find("Lua", 1, true) then
					on_choice(label)
					return
				end
			end
		end)

		dm.browse_and_download()

		local downloaded_file = dm.settings.docs_dir .. "/lua/5.4/index.html"
		vim.wait(2000, function()
			return vim.fn.filereadable(downloaded_file) == 1
		end, 10)
		expect(vim.fn.filereadable(downloaded_file)).toBe(1)
	end)
end)
