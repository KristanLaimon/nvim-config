-- ============================================================================
-- PLUGINS: conform.nvim -- formatting on save, with the project's own tools.
-- ============================================================================
-- THE RULE THIS FILE FOLLOWS
--   A formatter only runs when the PROJECT asks for it. prettier and prettierd
--   are skipped unless a prettier config file exists somewhere above the file;
--   pint and php-cs-fixer need the binary or a `vendor/bin` copy. Otherwise
--   opening someone else's repository would silently reformat it on save.
--
--   `stop_after_first` means the list is a preference order, not a pipeline:
--   prettierd (daemon, fast) then prettier then biome.
--
-- WHERE TO CHANGE THINGS
--   Which tool formats which filetype, and any formatter-specific condition/args
--   (prettier's astro handling, PHP's vendor/bin detection, ...), lives in the
--   owning language's lua/krs/langs/<lang>/init.lua (`M.formatters_by_ft` /
--   `M.conform_formatters`), NOT here. This file only merges those into conform's
--   `opts.formatters_by_ft` / `opts.formatters`.
--   format_on_save     Timeout and LSP fallback.
--
-- MANUAL FORMAT
--   <leader>ff (see lua/config/keymaps/lsp.lua).
-- ============================================================================

local langs = require("krs.langs").langs

--- Merges every language module's `formatters_by_ft` into one table.
local function build_formatters_by_ft()
	local by_ft = {}
	for _, lang in pairs(langs) do
		if lang.formatters_by_ft then
			for ft, spec in pairs(lang.formatters_by_ft) do
				by_ft[ft] = spec
			end
		end
	end
	return by_ft
end

--- Merges every language module's `conform_formatters` (per-formatter condition/args
--- overrides) into one table.
local function build_conform_formatters()
	local formatters = {}
	for _, lang in pairs(langs) do
		if lang.conform_formatters then
			for name, spec in pairs(lang.conform_formatters) do
				formatters[name] = spec
			end
		end
	end
	return formatters
end

return {
	{
		"stevearc/conform.nvim",
		event = { "BufReadPre", "BufNewFile" },
		cmd = { "ConformInfo" },
		opts = {
			formatters_by_ft = build_formatters_by_ft(),
			formatters = build_conform_formatters(),
			format_on_save = {
				timeout_ms = 1000,
				lsp_fallback = true,
			},
			default_format_opts = {
				lsp_format = "fallback",
				-- biome mangles Astro and Svelte components; let their own LSP do it.
				filter = function(client)
					return not (client.name == "biome" and vim.tbl_contains({ "astro", "svelte" }, vim.bo.filetype))
				end,
			},
		},
		config = function(_, opts)
			require("conform").setup(opts)

			vim.api.nvim_create_user_command("FormatDocument", function()
				require("conform").format({ async = true, lsp_fallback = true })
			end, { desc = "Format current buffer using Pint / PHP-CS-Fixer / blade-formatter / project formatter" })

			vim.api.nvim_create_user_command("ConformFormat", function()
				require("conform").format({ async = true, lsp_fallback = true })
			end, { desc = "Format current buffer using Pint / PHP-CS-Fixer / blade-formatter / project formatter" })
		end,
	},
	{
		"zapling/mason-conform.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "williamboman/mason.nvim", "stevearc/conform.nvim" },
		config = function()
			local env_ok, env_mod = pcall(require, "krs.core.environment")
			local is_mobile = false
			if env_ok then
				local env = env_mod.detect()
				is_mobile = env.is_mobile or env.is_termux or env.is_proot
			else
				is_mobile = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
			end

			local ok, installer = pcall(require, "krs.core.installer")
			local ignore_list = {}

			local base_list = (ok and type(installer.mason_packages) == "table") and installer.mason_packages
				or {
					"stylua",
					"gofumpt",
					"goimports",
					"prettierd",
					"prettier",
					"blade-formatter",
					"beautysh",
					"protolint",
					"biome",
					"eslint",
				}

			for _, pkg in ipairs(base_list) do
				table.insert(ignore_list, pkg)
			end

			-- Conditional & project-specific formatters MUST NOT be auto-installed by mason-conform on any platform
			local extra_ignores = {
				"pint",
				"php_cs_fixer",
				"php-cs-fixer",
				"dockerfmt",
			}

			for _, pkg in ipairs(extra_ignores) do
				if not vim.tbl_contains(ignore_list, pkg) then
					table.insert(ignore_list, pkg)
				end
			end

			-- On mobile / Termux, ignore ALL formatters from background auto-install on file open to prevent hangs/freezes
			if is_mobile then
				local all_formatters = {
					"goimports",
					"gofumpt",
					"stylua",
					"protolint",
					"prettierd",
					"prettier",
					"biome",
					"dockerfmt",
					"pint",
					"php_cs_fixer",
					"php-cs-fixer",
					"blade-formatter",
					"beautysh",
					"eslint",
				}
				for _, fmt in ipairs(all_formatters) do
					if not vim.tbl_contains(ignore_list, fmt) then
						table.insert(ignore_list, fmt)
					end
				end
			end

			require("mason-conform").setup({
				ignore_install = ignore_list,
			})
		end,
	},
}
