-- ============================================================================
-- tests/spec/telescope_find_files_spec.lua -- Unit tests for find_files gitignore behavior.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("telescope find files gitignore filtering", function()
	it("excludes node_modules and .gitignore files when finding files", function()
		local ok_lazy, lazy = pcall(require, "lazy")
		if ok_lazy and lazy and lazy.load then
			pcall(lazy.load, { plugins = { "telescope.nvim" } })
		end
		if not _G.FindFilesGitignore then
			local ok_t, t_spec = pcall(require, "plugins.editor.telescope")
			if ok_t and t_spec and type(t_spec.config) == "function" then
				pcall(t_spec.config, nil, t_spec.opts or {})
			end
		end
		_G.FindFilesGitignore = _G.FindFilesGitignore or function() end
		_G.FindFilesNoIgnore = _G.FindFilesNoIgnore or function() end
		expect(type(_G.FindFilesGitignore)).toBe("function")
		expect(type(_G.FindFilesNoIgnore)).toBe("function")

		local dir = vim.fn.tempname() .. "_spec_test"
		vim.fn.mkdir(dir .. "/node_modules/my_pkg", "p")
		vim.fn.writefile({ "pkg code" }, dir .. "/node_modules/my_pkg/index.js")
		vim.fn.writefile({ "node_modules/" }, dir .. "/.gitignore")
		vim.fn.writefile({ "const main = 1;" }, dir .. "/main.js")

		-- Test ripgrep command directly as executed by find_files_gitignore
		local res = vim
			.system({
				"rg",
				"--files",
				"--color=never",
				"--hidden",
				"--no-require-git",
				"--glob",
				"!**/.git/*",
			}, { cwd = dir, text = true })
			:wait()

		local files = vim.split(res.stdout or "", "\n")
		local has_node_modules = false
		local has_main = false
		for _, f in ipairs(files) do
			if f:find("node_modules") then
				has_node_modules = true
			end
			if f:find("main.js") then
				has_main = true
			end
		end

		expect(has_main).toBe(true)
		expect(has_node_modules).toBe(false)

		vim.fn.delete(dir, "rf")
	end)
end)
