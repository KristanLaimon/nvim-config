-- ============================================================================
-- KRS WEB: Vanilla Web Frontend Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Owns the HTML/CSS/Tailwind/Emmet LSP servers, their settings, Mason package
--   names, and formatter assignment. Frameworks and UI libraries live in their
--   own Astro and Web UI bundles so the Tooling Manager can install them
--   independently.
--   the detection lists for those live in lua/krs/langs/typescript (their
--   canonical JS/TS/JSON-ecosystem home) and are reused here.
--   - If project formatter configs (.prettierrc*, biome.json*, .editorconfig) exist,
--     defer to those formatters and skip overriding buffer settings.
--   - If NO project formatter config exists, fallback 2-space defaults are applied.
-- ============================================================================

---@type KrsLangModule
local M = {}

--- The lspconfig/mason server names this language owns.
M.lsp_server = { "html", "cssls", "tailwindcss", "emmet_ls" }

--- Formatter and tool configuration files for Web Frontend projects.
M.formatter_configs = {}

local function build_formatter_configs()
	local ts = require("krs.langs.typescript")
	vim.list_extend(M.formatter_configs, ts.PRETTIER_CONFIG_FILES)
	vim.list_extend(M.formatter_configs, ts.BIOME_CONFIG_FILES)
end

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	html = {
		filetypes = { "html", "templ", "hbs", "php", "blade" },
	},
	cssls = {
		settings = {
			css = { validate = true, lint = { unknownAtRules = "ignore" } },
			scss = { validate = true, lint = { unknownAtRules = "ignore" } },
			less = { validate = true },
		},
	},
	tailwindcss = {
		filetypes = {
			"html",
			"css",
			"scss",
			"sass",
			"less",
			"html.angular",
			"javascriptreact",
			"typescriptreact",
			"svelte",
			"vue",
			"astro",
			"php",
			"blade",
		},
		root_dir = function(bufnr, on_dir)
			local path = vim.api.nvim_buf_get_name(bufnr)
			local root = vim.fs.root(path ~= "" and path or bufnr, {
				"tailwind.config.js",
				"tailwind.config.cjs",
				"tailwind.config.mjs",
				"tailwind.config.ts",
				"postcss.config.js",
				"postcss.config.cjs",
				"postcss.config.mjs",
				"postcss.config.ts",
				"astro.config.mjs",
				"astro.config.ts",
			})
			if root then
				on_dir(root)
			end
		end,
		settings = {
			tailwindCSS = {
				validate = true,
				hovers = true,
				suggestions = true,
				codeActions = true,
				experimental = {
					classRegex = {
						{ "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*)" },
						{ "cx\\(([^)]*)\\)", "[\"'`]([^\"'`]*)" },
						{ "cn\\(([^)]*)\\)", "[\"'`]([^\"'`]*)" },
					},
				},
			},
		},
	},
	emmet_ls = {
		filetypes = {
			"html",
			"typescriptreact",
			"javascriptreact",
			"css",
			"sass",
			"scss",
			"less",
			"svelte",
			"vue",
			"astro",
			"php",
			"blade",
		},
	},
}

--- Mason package metadata, keyed by lspconfig name.
M.mason = {
	html = { mason = "html-lsp", lang = "HTML", type = "lsp", cmd = "vscode-html-language-server" },
	cssls = { mason = "css-lsp", lang = "CSS", type = "lsp", cmd = "vscode-css-language-server" },
	tailwindcss = {
		mason = "tailwindcss-language-server",
		lang = "Tailwind CSS",
		type = "lsp",
		cmd = "tailwindcss-language-server",
	},
	emmet_ls = { mason = "emmet-ls", lang = "Emmet", type = "lsp", cmd = "emmet-ls" },
}

M.mason_order = { "html", "cssls", "tailwindcss", "emmet_ls" }

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "🌐 Web Frontend"
M.requires = {
	{ cmd = "node", name = "Node.js", hint = "https://nodejs.org" },
}
M.treesitter = { "html", "css" }

--- conform.nvim formatter list per filetype. Astro always runs prettier (see
--- lua/krs/langs/typescript's conform_formatters.prettier for why); biome mangles
--- Astro and Svelte components so it is filtered out for those in formatting.lua.
M.formatters_by_ft = {
	css = { "prettierd", "prettier", "biome", stop_after_first = true },
	html = { "prettierd", "prettier", "biome", stop_after_first = true },
}

--- Fallback defaults for Web Frontend (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply Web Frontend fallback defaults if no formatter config or .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_project_config(buf, M.formatter_configs) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Web Frontend language configuration autocmds.
function M.setup()
	build_formatter_configs()

	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "html", "css", "scss", "less", "vue" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
