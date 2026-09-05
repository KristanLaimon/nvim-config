-- ============================================================================
-- tests/spec/lsp_scoping_spec.lua -- LSP server scoping & activation rules.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("LSP server scoping", function()
	local typescript = require("krs.langs.typescript")
	local web_ui = require("krs.langs.web_ui")
	local web = require("krs.langs.web")

	it("only activates ESLint LSP when project has an ESLint config file", function()
		expect(typescript.lsp_config.eslint).toBeDefined()
		expect(typescript.lsp_config.eslint.root_dir).toBeDefined()

		-- Test with a mock buffer in a directory without eslint config
		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		local sample_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(sample_buf, temp_dir .. "/index.ts")

		local called_dir = nil
		typescript.lsp_config.eslint.root_dir(sample_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeNil()

		-- Now create an eslint.config.js file in temp_dir
		local config_path = temp_dir .. "/eslint.config.js"
		local f = io.open(config_path, "w")
		if f then
			f:write("// eslint config")
			f:close()
		end

		typescript.lsp_config.eslint.root_dir(sample_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeDefined()

		vim.fn.delete(temp_dir, "rf")
		vim.api.nvim_buf_delete(sample_buf, { force = true })
	end)

	it("only activates Angular LSP when project has angular.json, project.json, or nx.json", function()
		expect(web_ui.lsp_config.angularls).toBeDefined()
		expect(web_ui.lsp_config.angularls.root_dir).toBeDefined()

		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		local sample_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(sample_buf, temp_dir .. "/app.component.ts")

		local called_dir = nil
		web_ui.lsp_config.angularls.root_dir(sample_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeNil()

		-- Create angular.json in temp_dir
		local config_path = temp_dir .. "/angular.json"
		local f = io.open(config_path, "w")
		if f then
			f:write("{}")
			f:close()
		end

		web_ui.lsp_config.angularls.root_dir(sample_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeDefined()

		vim.fn.delete(temp_dir, "rf")
		vim.api.nvim_buf_delete(sample_buf, { force = true })
	end)

	it("excludes plain TS/JS filetypes and package.json from Tailwind CSS LSP auto-activation", function()
		expect(web.lsp_config.tailwindcss).toBeDefined()
		local filetypes = web.lsp_config.tailwindcss.filetypes or {}
		
		expect(vim.tbl_contains(filetypes, "typescript")).toBe(false)
		expect(vim.tbl_contains(filetypes, "javascript")).toBe(false)
		expect(vim.tbl_contains(filetypes, "html")).toBe(true)
		expect(vim.tbl_contains(filetypes, "css")).toBe(true)

		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		local sample_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(sample_buf, temp_dir .. "/package.json")

		-- package.json alone should NOT trigger tailwindcss root_dir
		local called_dir = nil
		web.lsp_config.tailwindcss.root_dir(sample_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeNil()

		-- Adding tailwind.config.js SHOULD trigger root_dir
		local config_path = temp_dir .. "/tailwind.config.js"
		local f = io.open(config_path, "w")
		if f then
			f:write("// tailwind config")
			f:close()
		end

		web.lsp_config.tailwindcss.root_dir(sample_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeDefined()

		vim.fn.delete(temp_dir, "rf")
		vim.api.nvim_buf_delete(sample_buf, { force = true })
	end)
end)
