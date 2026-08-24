-- ============================================================================
-- KRS PHP: Centralized PHP Language Configuration Entry Point
-- ============================================================================
-- WHAT IT DOES
--   - Sets PSR-12 standard PHP indentation defaults (4 spaces) when no .editorconfig exists.
--   - Integrates Composer vendor bin PATH prepending (`krs.langs.php.composer`).
--   - Integrates PHP/Laravel toolchain check modal (`plugins.krs.php_tools_modal`).
--   - Owns the intelephense LSP server and the pint/php_cs_fixer/blade-formatter
--     formatters: settings, Mason package names, and filetype assignment.
-- ============================================================================

--- @class PHPLangModule : KrsLangModule
--- @field composer table
--- @field modal table

---@type PHPLangModule
local M = {
	composer = require("krs.langs.php.composer"),
	modal = require("plugins.krs.php_tools_modal"),
}

-- M.composer = require("krs.langs.php.composer")
-- M.modal = require("plugins.krs.php_tools_modal")

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "intelephense" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	intelephense = {
		filetypes = { "php", "blade" },
		settings = {
			intelephense = {
				files = {
					maxSize = 1000000,
				},
				stubs = {
					"bcmath",
					"Core",
					"curl",
					"date",
					"hash",
					"json",
					"mbstring",
					"openssl",
					"pcre",
					"PDO",
					"Reflection",
					"SPL",
					"standard",
					"tokenizer",
					"zlib",
					"laravel",
					"phpunit",
				},
			},
		},
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name. pint/php_cs_fixer are
--- intentionally absent: they run from the project's own `vendor/bin` or a system
--- install (see `has_php_tool` below), never auto-installed by Mason.
M.mason = {
	intelephense = { mason = "intelephense", lang = "PHP", type = "lsp", cmd = "intelephense" },
	["blade-formatter"] = {
		mason = "blade-formatter",
		name = "blade-formatter",
		type = "formatter",
		cmd = "blade-formatter",
	},
	["php-debug-adapter"] = {
		mason = "php-debug-adapter",
		lang = "PHP Debugger (Xdebug)",
		type = "dap",
		cmd = "php-debug-adapter",
	},
}

M.mason_order = { "intelephense", "blade-formatter", "php-debug-adapter" }

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "🐘 PHP & Laravel"
M.requires = {
	{ cmd = "php", name = "PHP" },
	{ cmd = "composer", name = "Composer" },
}
M.treesitter = { "php", "phpdoc", "blade" }

--- Xdebug connects to the editor, not the other way round: nvim listens on this
--- port and the request being debugged attaches to it.
M.dap_debug_port = 9003

--- Filetypes the DAP configurations below attach to.
M.dap_filetypes = { "php", "blade" }

--- Static nvim-dap configurations, appended by lua/plugins/editor/dap.lua.
M.dap_configs = {
	{
		type = "php",
		request = "launch",
		name = "🐘 Listen for Xdebug (Vanilla PHP / Laravel Web / Herd)",
		port = M.dap_debug_port,
		stopOnEntry = false,
		log = false,
		pathMappings = {
			["${workspaceFolder}"] = "${workspaceFolder}",
		},
	},
	{
		type = "php",
		request = "launch",
		name = "📄 Launch Current Script (Vanilla PHP CLI)",
		program = "${file}",
		cwd = "${fileDirname}",
		port = M.dap_debug_port,
		runtimeArgs = { "-dxdebug.mode=debug", "-dxdebug.start_with_request=yes" },
	},
	{
		type = "php",
		request = "launch",
		name = "🚀 Debug Laravel Artisan Command",
		program = "${workspaceFolder}/artisan",
		cwd = "${workspaceFolder}",
		args = function()
			local cmd = vim.fn.input("Artisan command args (e.g. migrate, queue:work): ")
			if cmd == "" then
				return {}
			end
			return vim.split(cmd, "%s+")
		end,
		port = M.dap_debug_port,
		runtimeArgs = { "-dxdebug.mode=debug", "-dxdebug.start_with_request=yes" },
	},
	{
		type = "php",
		request = "launch",
		name = "🌐 Debug Laravel App (artisan serve)",
		program = "${workspaceFolder}/artisan",
		args = { "serve" },
		cwd = "${workspaceFolder}",
		port = M.dap_debug_port,
		runtimeArgs = { "-dxdebug.mode=debug", "-dxdebug.start_with_request=yes" },
	},
}

--- Launch-profile runtimes this language owns (see lua/krs/launch/runtimes.lua).
M.launch_runtimes = {
	php = {
		command = "php",
		dap = function(profile, root)
			return {
				type = "php",
				request = "launch",
				name = profile.name,
				port = M.dap_debug_port,
				pathMappings = { ["/var/www/html"] = root },
			}
		end,
	},
}

--- True when a PHP tool is available: on PATH, or vendored by the project.
--- @param executable string Binary name.
--- @param filename string Path of the file being formatted.
--- @return boolean
local function has_php_tool(executable, filename)
	if vim.fn.executable(executable) == 1 then
		return true
	end
	return vim.fs.find({
		"vendor/bin/" .. executable,
		"vendor/bin/" .. executable .. ".bat",
		"vendor/bin/" .. executable .. ".cmd",
		"vendor/bin/" .. executable .. ".exe",
	}, { path = filename, upward = true })[1] ~= nil
end

--- conform.nvim formatter list per filetype. `stop_after_first`: preference order.
M.formatters_by_ft = {
	php = { "pint", "php_cs_fixer", stop_after_first = true },
	blade = { "blade-formatter", "pint", stop_after_first = true },
}

--- conform.nvim per-formatter overrides: pint/php-cs-fixer only run when the tool
--- is actually available (PATH or `vendor/bin`), so opening someone else's PHP
--- repository doesn't silently reformat it on save.
M.conform_formatters = {
	pint = {
		condition = function(_, ctx)
			return has_php_tool("pint", ctx.filename)
		end,
	},
	php_cs_fixer = {
		condition = function(_, ctx)
			return has_php_tool("php-cs-fixer", ctx.filename)
		end,
	},
}

--- Standard PSR-12 defaults for PHP (4 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 4,
	autoindent = true,
}

--- Apply PHP language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize PHP language configurations.
function M.setup()
	M.composer.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "php", "blade" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
