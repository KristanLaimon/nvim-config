-- ============================================================================
-- PLUGINS: PHP & Laravel support.
-- ============================================================================
-- 1. vim-blade      Syntax highlighting for `.blade.php` templates.
-- 2. blade-nav      Jump to and complete Blade components and routes.
-- 3. krs_php_tools  Registers `:PHPCheckTools`, which reports whether PHP and
--                   Composer are actually installed (on Windows or in WSL) and
--                   how to install what is missing.
-- 4. PATH vendor/bin  Prepends project `./vendor/bin` to `PATH` for local Composer binaries.
--
-- The heavy lifting -- intelephense, pint formatting, the blade filetype pattern
-- -- lives in lsp.lua and formatting.lua.
-- ============================================================================

return {
	-- Blade filetype syntax highlighting
	{
		"jwalton512/vim-blade",
		ft = { "blade" },
	},

	-- Laravel Blade component navigation & completion
	{
		"ricardoramirezr/blade-nav.nvim",
		dependencies = {
			"saghen/blink.cmp",
		},
		ft = { "blade", "php" },
		opts = {
			close_tag_on_complete = true,
			-- Blink is registered below as a direct source provider. Disable the
			-- optional nvim-cmp/coq integrations so blade-nav does not emit a
			-- misleading "nvim-cmp not found" warning on every Blade buffer.
			integrations = {
				gf = true,
				cmp = false,
				coq = false,
			},
		},
	},

	-- Register blade-nav autocompletion provider in blink.cmp
	{
		"saghen/blink.cmp",
		opts = function(_, opts)
			opts.sources = opts.sources or {}
			opts.sources.providers = opts.sources.providers or {}
			opts.sources.providers["blade-nav"] = {
				name = "blade-nav",
				module = "blade-nav.integrations.blink",
				score_offset = 100,
				enabled = function()
					local ft = vim.bo.filetype
					return ft == "blade" or ft == "php"
				end,
			}
			opts.sources.default = opts.sources.default or {}
			if not vim.tbl_contains(opts.sources.default, "blade-nav") then
				table.insert(opts.sources.default, "blade-nav")
			end
		end,
	},

	-- PHP & Laravel Environment Check Modal Hook
	{
		name = "krs_php_tools",
		dir = vim.fn.stdpath("config") .. "/lua/plugins/krs",
		ft = { "php", "blade" },
		cmd = "PHPCheckTools",
		config = function()
			local php = require("krs.langs.php")
			local modal = php.modal

			vim.api.nvim_create_user_command("PHPCheckTools", function()
				modal.check_tools(false, true)
			end, { desc = "Check PHP & Laravel CLI environment status" })

			local checked = false
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "php", "blade" },
				callback = function()
					if not checked then
						checked = true
						-- Defer slightly to allow buffer layout to settle
						vim.defer_fn(function()
							modal.check_tools(false)
						end, 300)
					end
				end,
			})
		end,
	},
}
