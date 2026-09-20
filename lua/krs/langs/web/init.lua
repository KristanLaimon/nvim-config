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

--- Checks if a buffer contains at least one Tailwind CSS class or directive.
--- @param bufnr integer
--- @return boolean
function M.has_tailwind_classes(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local max_check = math.min(line_count, 1500)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, max_check, false)
	for _, line in ipairs(lines) do
		if line:find("@tailwind", 1, true) or line:find("@apply", 1, true) or line:find("theme%(") then
			return true
		end
		if line:find("[%w_-]+:[%w_-]+") then
			return true
		end
		if line:find("class", 1, true) then
			if
				line:match("%f[%w_-][pmywhz]%-[%w%[%]%._/-]+")
				or line:match("%f[%w_-][mp][xytrbl]%-[%w%[%]%._/-]+")
				or line:match("%f[%w_-]min%-[wh]%-[%w%[%]%._/-]+")
				or line:match("%f[%w_-]max%-[wh]%-[%w%[%]%._/-]+")
				or line:match("%f[%w_-]flex%f[%W]")
				or line:match("%f[%w_-]grid%f[%W]")
				or line:match("%f[%w_-]hidden%f[%W]")
				or line:match("%f[%w_-]block%f[%W]")
				or line:match("%f[%w_-]inline%f[%W]")
				or line:match("%f[%w_-]relative%f[%W]")
				or line:match("%f[%w_-]absolute%f[%W]")
				or line:match("%f[%w_-]fixed%f[%W]")
				or line:match("%f[%w_-]sticky%f[%W]")
				or line:match(
					"%f[%w_-](text|bg|border|rounded|shadow|ring|gap|items|justify|font|space|col|row|leading|tracking|opacity)%-[%w%[%]%._/-]+"
				)
				or line:match("%f[%w_-]rounded%f[%W]")
				or line:match("%f[%w_-]shadow%f[%W]")
				or line:match("%f[%w_-]border%f[%W]")
			then
				return true
			end
		end
	end
	return false
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
			local ft = (vim.bo[bufnr] and vim.bo[bufnr].filetype) or ""
			local is_blade = ft == "blade" or path:match("%.blade%.php$") ~= nil

			-- Blade optimization: Only activate Tailwind CSS LSP if the file
			-- actually contains at least one Tailwind class or directive.
			if is_blade and not M.has_tailwind_classes(bufnr) then
				return
			end

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

	-- Auto-attach tailwindcss to Blade buffers as soon as Tailwind classes are added
	vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
		pattern = "*.blade.php",
		callback = function(args)
			local buf = args.buf
			if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "blade" then
				return
			end
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
				if client.name == "tailwindcss" then
					return
				end
			end
			if M.has_tailwind_classes(buf) then
				local path = vim.api.nvim_buf_get_name(buf)
				local root = vim.fs.root(path ~= "" and path or buf, {
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
					for _, client in ipairs(vim.lsp.get_clients({ name = "tailwindcss" })) do
						if client.config.root_dir == root then
							vim.lsp.buf_attach_client(buf, client.id)
							return
						end
					end
					local ok_lsp, lspconfig = pcall(require, "lspconfig")
					if ok_lsp and lspconfig.tailwindcss and lspconfig.tailwindcss.manager then
						lspconfig.tailwindcss.manager:try_add(buf)
					end
				end
			end
		end,
	})
end

return M
