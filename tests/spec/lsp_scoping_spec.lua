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

	it("only activates Tailwind CSS LSP on Blade files when Tailwind classes are present", function()
		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		local config_path = temp_dir .. "/tailwind.config.js"
		local f = io.open(config_path, "w")
		if f then
			f:write("// tailwind config")
			f:close()
		end

		-- 1. Plain Blade buffer with no Tailwind classes
		local plain_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(plain_buf, temp_dir .. "/plain.blade.php")
		vim.api.nvim_buf_set_lines(plain_buf, 0, -1, false, {
			"<div>",
			"  <h1>No Tailwind Here</h1>",
			"</div>",
		})
		vim.bo[plain_buf].filetype = "blade"

		local called_dir = nil
		web.lsp_config.tailwindcss.root_dir(plain_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeNil()

		-- 2. Blade buffer WITH Tailwind classes
		local tw_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(tw_buf, temp_dir .. "/styled.blade.php")
		vim.api.nvim_buf_set_lines(tw_buf, 0, -1, false, {
			'<div class="flex items-center p-4 bg-white">',
			'  <h1 class="text-xl font-bold">With Tailwind</h1>',
			"</div>",
		})
		vim.bo[tw_buf].filetype = "blade"

		called_dir = nil
		web.lsp_config.tailwindcss.root_dir(tw_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeDefined()

		vim.fn.delete(temp_dir, "rf")
		vim.api.nvim_buf_delete(plain_buf, { force = true })
		vim.api.nvim_buf_delete(tw_buf, { force = true })
	end)

	it("only activates JavaScript LSP on HTML files when inline <script> with content exists", function()
		expect(typescript.lsp_config.vtsls).toBeDefined()
		expect(vim.tbl_contains(typescript.lsp_config.vtsls.filetypes, "html")).toBe(true)

		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")

		-- 1. HTML buffer with only external script <script src="...">
		local ext_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(ext_buf, temp_dir .. "/external.html")
		vim.api.nvim_buf_set_lines(ext_buf, 0, -1, false, {
			"<!DOCTYPE html>",
			"<html>",
			"<head>",
			'  <script src="app.js"></script>',
			'  <script src="vendor.js">',
			"  </script>",
			"</head>",
			"<body><h1>No inline script</h1></body>",
			"</html>",
		})
		vim.bo[ext_buf].filetype = "html"

		local called_dir = nil
		typescript.lsp_config.vtsls.root_dir(ext_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeNil()

		-- 2. HTML buffer WITH inline script content
		local inline_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(inline_buf, temp_dir .. "/inline.html")
		vim.api.nvim_buf_set_lines(inline_buf, 0, -1, false, {
			"<!DOCTYPE html>",
			"<html>",
			"<body>",
			"  <script>",
			"    const app = 'my-app';",
			"    console.log(app);",
			"  </script>",
			"</body>",
			"</html>",
		})
		vim.bo[inline_buf].filetype = "html"

		called_dir = nil
		typescript.lsp_config.vtsls.root_dir(inline_buf, function(dir)
			called_dir = dir
		end)
		expect(called_dir).toBeDefined()

		vim.fn.delete(temp_dir, "rf")
		vim.api.nvim_buf_delete(ext_buf, { force = true })
		vim.api.nvim_buf_delete(inline_buf, { force = true })
	end)
end)
