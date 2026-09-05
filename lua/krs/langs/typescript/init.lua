-- ============================================================================
-- KRS TS: Centralized TypeScript / JavaScript Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Owns everything specific to the JS/TS/JSON ecosystem: which LSP servers run
--   (vtsls, jsonls, biome, eslint), their settings, their Mason package names,
--   and which formatter runs for which filetype. lua/plugins/lsp/lsp.lua,
--   lua/plugins/lsp/formatting.lua and lua/krs/core/installer.lua all read
--   these fields instead of hardcoding them -- this file is the one place to
--   edit when swapping a tool (e.g. vtsls -> tsgo) or changing its settings.
--
--   JavaScript/TypeScript projects often rely on specialized formatters like Prettier,
--   Biome, ESLint, or Deno.
--   - If project formatter config files (.prettierrc*, biome.json*, eslint.config*, deno.json*, .editorconfig)
--     exist, we defer to those formatters and skip overriding buffer settings.
--   - If NO project formatter config exists, fallback 2-space defaults are applied.
-- ============================================================================

---@type KrsLangModule
local M = {}

--- The lspconfig/mason server name(s) backing TypeScript & JavaScript. An array even
--- though there is normally one: swap TS servers (e.g. vtsls -> tsgo) by changing
--- this one value, or list more than one for the rare case a language needs several.
M.lsp_server = { "vtsls" }

--- Formatter and tool configuration files that indicate a project-managed code style.
M.PRETTIER_CONFIG_FILES = {
	".prettierrc",
	".prettierrc.json",
	".prettierrc.yml",
	".prettierrc.yaml",
	".prettierrc.json5",
	".prettierrc.js",
	".prettierrc.cjs",
	".prettierrc.mjs",
	"prettier.config.js",
	"prettier.config.cjs",
	"prettier.config.mjs",
}
M.BIOME_CONFIG_FILES = { "biome.json", "biome.jsonc" }
M.ESLINT_CONFIG_FILES = {
	"eslint.config.js",
	"eslint.config.mjs",
	"eslint.config.cjs",
	"eslint.config.ts",
	"eslint.config.mts",
	"eslint.config.cts",
	".eslintrc",
	".eslintrc.json",
	".eslintrc.js",
	".eslintrc.cjs",
	".eslintrc.yml",
	".eslintrc.yaml",
}
M.DENO_CONFIG_FILES = { "deno.json", "deno.jsonc" }

M.formatter_configs = {}
vim.list_extend(M.formatter_configs, M.PRETTIER_CONFIG_FILES)
vim.list_extend(M.formatter_configs, M.BIOME_CONFIG_FILES)
vim.list_extend(M.formatter_configs, M.ESLINT_CONFIG_FILES)
vim.list_extend(M.formatter_configs, M.DENO_CONFIG_FILES)

--- True when `filename` sits inside a prettier-managed project. Checked upward from
--- the file being saved, so a monorepo root config counts. Used by both this
--- module's own conform overrides and (indirectly) anything that formats JS/TS/JSON.
--- @param filename string
--- @return boolean
function M.has_prettier_config(filename)
	return vim.fs.find(M.PRETTIER_CONFIG_FILES, { path = filename, upward = true })[1] ~= nil
end

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	[M.lsp_server[1]] = {
		root_dir = function(bufnr, on_dir)
			local root = vim.fs.root(bufnr, {
				"tsconfig.json",
				"jsconfig.json",
				"package.json",
			})
			local home = vim.fs.normalize(vim.env.USERPROFILE or vim.env.HOME or ""):lower()
			if not root or vim.fs.normalize(root):lower() == home then
				on_dir(vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)))
			else
				on_dir(root)
			end
		end,
		settings = {
			[M.lsp_server[1]] = {
				autoUseWorkspaceTsdk = true,
				experimental = {
					completion = { enableServerSideFuzzyMatch = true },
				},
			},
			typescript = {
				tsserver = { maxTsServerMemory = 8192 },
				inlayHints = {
					parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
					parameterTypes = { enabled = true },
					variableTypes = { enabled = false },
					propertyDeclarationTypes = { enabled = true },
					functionLikeReturnTypes = { enabled = true },
					enumMemberValues = { enabled = true },
				},
			},
			javascript = {
				inlayHints = {
					parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
					parameterTypes = { enabled = true },
					variableTypes = { enabled = false },
					propertyDeclarationTypes = { enabled = true },
					functionLikeReturnTypes = { enabled = true },
					enumMemberValues = { enabled = true },
				},
			},
		},
	},
	jsonls = {}, -- enriched with SchemaStore schemas by lsp.lua (needs plugin availability)
	biome = {
		root_dir = function(bufnr, on_dir)
			local root = vim.fs.root(bufnr, { "biome.json", "biome.jsonc" })
			if root then
				on_dir(root)
			end
		end,
	},
	eslint = {
		root_dir = function(bufnr, on_dir)
			local path = vim.api.nvim_buf_get_name(bufnr)
			local root = vim.fs.root(path ~= "" and path or bufnr, M.ESLINT_CONFIG_FILES)
			if root then
				on_dir(root)
			end
		end,
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	[M.lsp_server[1]] = { mason = M.lsp_server[1], lang = "TypeScript / JavaScript", type = "lsp", cmd = M.lsp_server[1] },
	jsonls = { mason = "json-lsp", lang = "JSON", type = "lsp", cmd = "vscode-json-language-server" },
	biome = { mason = "biome", lang = "JS/TS/JSON", type = "lsp", cmd = "biome" },
	eslint = { mason = "eslint-lsp", lang = "JS/TS (ESLint)", type = "lsp", cmd = "vscode-eslint-language-server" },
	prettier = { mason = "prettier", name = "prettier", type = "formatter", cmd = "prettier" },
	prettierd = { mason = "prettierd", name = "prettierd", type = "formatter", cmd = "prettierd" },
}

--- js-debug-adapter drives node/deno/bun's browser-adjacent debugging (pwa-node,
--- pwa-chrome, pwa-msedge); registered as a JS/TS-ecosystem tool even though the
--- adapter setup itself lives in lua/plugins/krs/debuggers/ (shared by node.lua,
--- browsers.lua and bun.lua, so it isn't owned by one single dap_setup here).
M.mason["js-debug-adapter"] = {
	mason = "js-debug-adapter",
	lang = "JS/TS Debugger",
	type = "dap",
	cmd = "js-debug-adapter",
}

-- Tool installation is grouped with Svelte, Angular, and React in the Web UI
-- bundle. This module remains the single source of truth for JS/TS settings,
-- formatting, and debugger helpers used throughout the configuration.

--- Paths js-debug must never step into, so the debugger does not stop inside node
--- internals or the tsx loader. Shared with lua/plugins/krs/debuggers/_shared.lua.
M.js_skip_files = { "<node_internals>/**", "**/node_modules/**" }

--- Port the Deno inspector attaches to.
M.deno_inspect_port = 9229

--- Memoized `node -v` result; the call costs ~50ms and never changes per session.
local node_major

--- Decides how a `.ts`/`.tsx` entry point should be started under node.
--- Preference order: the project's own `tsx` (handles tsconfig paths, enums and
--- decorators), then native node type stripping (22.18+/23.6+), then `npx tsx`.
--- Shared with lua/plugins/krs/debuggers/node.lua -- keep the return shape stable.
--- @param root string Project root.
--- @param entry string Entry point path, relative to root.
--- @return table runtime `{ exe = string, args = string[] }`
function M.ts_runtime(root, entry)
	local path = require("krs.core.path")
	if not entry:match("%.[cm]?tsx?$") then
		return { exe = "node", args = {} }
	end

	if path.is_dir(path.join(root, "node_modules", "tsx")) then
		return { exe = "node", args = { "--import", "tsx" } }
	end

	if not node_major then
		local major, minor = (vim.fn.system("node -v") or ""):match("v(%d+)%.(%d+)")
		node_major = tonumber(major) and (tonumber(major) + tonumber(minor) / 1000) or 0
	end
	if node_major >= 22.018 then
		return { exe = "node", args = {} }
	end

	local npx = vim.fn.exepath("npx")
	return { exe = npx ~= "" and npx or "npx", args = { "tsx" } }
end

--- Base js-debug configuration, used by node, deno and any unknown runtime.
--- @param profile table Launch profile.
--- @param root string Project root.
--- @param ctx table Launch context.
--- @return table config nvim-dap configuration.
function M.js_debug_config(profile, root, ctx)
	local cfg = {
		type = "pwa-node",
		request = "launch",
		name = profile.name,
		program = ctx.full_entry,
		cwd = root,
		-- Keeps the child process in a nvim terminal buffer instead of popping
		-- external cmd.exe windows for .cmd shims on Windows.
		console = "integratedTerminal",
		sourceMaps = true,
		skipFiles = M.js_skip_files,
	}

	if ctx.is_ts then
		local rt = M.ts_runtime(root, ctx.entry)
		cfg.runtimeExecutable = rt.exe
		cfg.runtimeArgs = #rt.args > 0 and rt.args or nil
	end

	return cfg
end

--- Launch-profile runtimes this language owns (see lua/krs/launch/runtimes.lua).
M.launch_runtimes = {
	bun = {
		command = "bun",
		-- Bun ships its own adapter (WebKit inspector protocol). It spawns bun
		-- itself, so no runtimeExecutable, and it runs .ts with no loader.
		dap = function(profile, root, ctx)
			return {
				type = "bun",
				request = "launch",
				name = profile.name,
				program = ctx.full_entry,
				cwd = root,
				stopOnEntry = false,
				watchMode = false,
			}
		end,
	},
	node = {
		-- Terminal runs go through npx tsx for plain .ts/.tsx only; the debugger
		-- path (js_debug_config) is the one that also handles .mts/.cts.
		command = function(ctx)
			return ctx.entry:match("%.tsx?$") and "npx tsx" or "node"
		end,
	},
	deno = {
		command = "deno run -A",
		dap = function(profile, root, ctx)
			local cfg = M.js_debug_config(profile, root, ctx)
			cfg.runtimeExecutable = "deno"
			cfg.runtimeArgs = { "run", "--inspect-wait", "--allow-all" }
			cfg.attachSimplePort = M.deno_inspect_port
			return cfg
		end,
	},
}

--- conform.nvim formatter list per filetype. `stop_after_first`: preference order
--- (prettierd, the daemon, first) not a pipeline.
M.formatters_by_ft = {
	json = { "prettierd", "prettier", "biome", stop_after_first = true },
	javascript = { "prettierd", "prettier", "biome", stop_after_first = true },
	typescript = { "prettierd", "prettier", "biome", stop_after_first = true },
	javascriptreact = { "prettierd", "prettier", "biome", stop_after_first = true },
	typescriptreact = { "prettierd", "prettier", "biome", stop_after_first = true },
}

--- conform.nvim per-formatter overrides. prettier/prettierd only run when the
--- project actually asks for them (a Prettier config file exists) -- except for
--- Astro, whose plugin must be passed explicitly, so prettier always runs there.
M.conform_formatters = {
	prettier = {
		condition = function(_, ctx)
			return ctx.filetype == "astro" or M.has_prettier_config(ctx.filename)
		end,
		args = function(_, ctx)
			local args = { "--stdin-filepath", "$FILENAME" }
			if ctx.filetype == "astro" then
				vim.list_extend(args, { "--plugin", "prettier-plugin-astro" })
				local config = vim.fs.find({ ".prettierrc.astro.json" }, { path = ctx.filename, upward = true })[1]
				if config then
					vim.list_extend(args, { "--config", config })
				end
			end
			return args
		end,
	},
	prettierd = {
		condition = function(_, ctx)
			return M.has_prettier_config(ctx.filename)
		end,
	},
}

--- Fallback defaults for TypeScript / JavaScript (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply TypeScript / JavaScript fallback defaults if no formatter config or .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_project_config(buf, M.formatter_configs) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize TypeScript language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "typescript", "javascript", "typescriptreact", "javascriptreact", "json", "jsonc" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
