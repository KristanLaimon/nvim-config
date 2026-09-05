-- ============================================================================
-- KRS LANGS: Language Module Template & Extension Guide (init_template.lua)
-- ============================================================================
-- HOW TO ADD OR EXTEND A LANGUAGE TOOLCHAIN IN KRSVIM
--   1. Copy this file to `lua/krs/langs/<your_language>/init.lua`.
--   2. Fill in the fields your language needs (all fields are optional!).
--   3. Register the new submodule in `lua/krs/langs/init.lua`:
--        a. Add to `M.langs`: `<lang_key> = require("krs.langs.<your_language>")`
--        b. Add to `M.lang_order`: append `"<lang_key>"` to the order array.
--   4. Document the language under `docs/languages/<your_language>.md`.
--
-- WHERE DO THE PROPERTIES IN THIS FILE COME FROM?
--   1. `M.lsp_config` (Standard Neovim `vim.lsp.Config` & `nvim-lspconfig`):
--      - `filetypes`: Array of Neovim filetypes that trigger this LSP server.
--      - `cmd`: CLI command array executed to launch the LSP binary.
--      - `root_dir`: Function or `root_pattern(...)` resolving project root.
--      - `settings`: Table of server-specific options (e.g. `Lua.diagnostics.globals`).
--      - `capabilities`: Client capabilities (e.g. `{ offsetEncoding = { "utf-16" } }` for clangd).
--
--   2. `M.formatters_by_ft` & `M.conform_formatters` (Standard `conform.nvim`):
--      - `formatters_by_ft`: Maps filetypes to formatters (`stop_after_first = true` for fallback chains).
--      - `conform_formatters`: Overrides `condition` (checks binary or `.prettierrc`), `command`, `args`, `stdin`.
--
--   3. `M.dap_configs` & `M.dap_setup` (Standard `nvim-dap`):
--      - `type`, `request` ("launch"|"attach"), `program`, `cwd`, `port`, `args`, `stopOnEntry`.
--
--   4. `M.mason` (KrsVim Language Tooling Manager):
--      - `mason`: Package directory name in Mason registry.
--      - `type`: "lsp" | "formatter" | "dap" | "extra" (drives UI category grouping).
--      - `cmd`: Binary executable checked via `vim.fn.executable()`.
--      - `lang` / `name`: Display label in `:LanguageManager`.
--
-- INTELLISENSE & TYPE COMPLETION
--   Annotating `---@type KrsLangModule` or `---@class MyCustomLangModule : KrsLangModule`
--   on `local M = {}` automatically provides full IntelliSense (hover, completion,
--   enum options) for all properties (`M.mason`, `M.requires`, `M.conform_formatters`,
--   `M.dap_configs`, `M.launch_runtimes`, etc.) across every language `init.lua`.
-- ============================================================================

--- Annotate `---@type KrsLangModule` or custom subclass for full IntelliSense completion.
---@class MyCustomLangModule : KrsLangModule
---@field custom_helper? fun(buf: integer): boolean Custom helper method example
---@field custom_port? integer Custom port parameter example
---@field sub_feature? table Submodule reference (like `composer` in PHP)
local M = {}

-- ----------------------------------------------------------------------------
-- 1. LSP CONFIGURATION (Consumed by lua/plugins/lsp/lsp.lua)
-- ----------------------------------------------------------------------------

--- Server name(s) this language owns (matching lspconfig/Mason server names).
M.lsp_server = { "example_ls" }

--- lspconfig server options, keyed by server name (standard `vim.lsp.Config` & `nvim-lspconfig`).
M.lsp_config = {
	example_ls = {
		filetypes = { "example" },
		-- cmd = { "example-language-server", "--stdio" },
		-- root_dir = function(fname) return ... end,
		settings = {
			example_ls = {
				diagnostics = { enable = true },
			},
		},
	},
}

-- ----------------------------------------------------------------------------
-- 2. MASON TOOLING METADATA (Consumed by lua/krs/core/installer.lua)
-- ----------------------------------------------------------------------------

--- Package metadata keyed by tool name. Inherits full completion for
--- `mason`, `type` ("lsp"|"formatter"|"dap"|"extra"), `cmd`, `lang`, and `name`
--- from `KrsMasonToolInfo` in `KrsLangModule`.
M.mason = {
	example_ls = { mason = "example-language-server", lang = "Example Lang", type = "lsp", cmd = "example-language-server" },
	example_fmt = { mason = "example-formatter", name = "example-formatter", type = "formatter", cmd = "example-formatter" },
	example_dap = { mason = "example-debug-adapter", lang = "Example Debugger", type = "dap", cmd = "example-debug-adapter" },
}

--- Installation and display order for the Mason packages listed above.
M.mason_order = { "example_ls", "example_fmt", "example_dap" }

-- ----------------------------------------------------------------------------
-- 3. LANGUAGE TOOLING MANAGER BUNDLE METADATA (:LanguageManager UI)
-- ----------------------------------------------------------------------------

--- Display title with icon shown in `:LanguageManager`.
M.bundle_name = "🚀 Example Language"

--- Omit or set to `false`. (`true` is strictly reserved for minimal Lua core).
M.is_minimal = false

--- Pre-requisite system CLI binaries checked before Mason installation.
--- Inherits completion for `cmd`, `name`, `alt`, and `hint` from `KrsLangRequirement`.
M.requires = {
	{ cmd = "example-cli", name = "Example Language CLI Runtime", hint = "Install via system package manager" },
}

--- Treesitter parser names installed alongside Mason packages.
M.treesitter = { "example" }

--- Optional: Extra Mason packages to install without lspconfig mapping.
-- M.bundle_extra_mason_pkgs = { "standalone-tool" }

-- ----------------------------------------------------------------------------
-- 4. FORMATTING PIPELINE (Consumed by lua/plugins/lsp/formatting.lua)
-- ----------------------------------------------------------------------------

--- conform.nvim formatter assignment per filetype.
--- Use `stop_after_first = true` for preference chains (e.g. prettierd -> prettier).
M.formatters_by_ft = {
	example = { "example_fmt" },
}

--- conform.nvim per-formatter overrides (conditional execution, custom args).
--- Inherits completion for `condition`, `command`, `args`, `stdin`, `cwd` from `KrsConformFormatterOpts`.
M.conform_formatters = {
	example_fmt = {
		condition = function(_, ctx)
			-- Only run if binary exists on PATH or vendored in project
			return vim.fn.executable("example-formatter") == 1
		end,
	},
}

-- ----------------------------------------------------------------------------
-- 5. DEBUG ADAPTER / DAP CONFIGURATION (Consumed by lua/plugins/editor/dap.lua)
-- ----------------------------------------------------------------------------

--- Filetypes the static DAP configurations attach to.
M.dap_filetypes = { "example" }

--- Option A: Static DAP configurations list (standard `nvim-dap`).
--- Inherits completion for `type`, `request`, `name`, `program`, `cwd`, `port`, `args`, `stopOnEntry` from `KrsDapConfig`.
M.dap_configs = {
	{
		type = "example_dap",
		request = "launch",
		name = "🚀 Launch Current File (Example)",
		program = "${file}",
		cwd = "${workspaceFolder}",
	},
}

--- Option B: Dynamic DAP setup function (for adapters requiring runtime setup)
-- function M.dap_setup(dap)
-- 	dap.adapters.example_dap = {
-- 		type = "executable",
-- 		command = "example-debug-adapter",
-- 		args = {},
-- 	}
-- end

-- ----------------------------------------------------------------------------
-- 6. LAUNCH PROFILE RUNTIMES (Consumed by lua/krs/launch/runtimes.lua)
-- ----------------------------------------------------------------------------

--- Custom launch profile runtimes owned by this language module.
--- Inherits completion for `command`, `dap`, and `execute` from `KrsLaunchRuntime`.
M.launch_runtimes = {
	example = {
		command = "example-cli run",
		dap = function(profile, root, ctx)
			return {
				type = "example_dap",
				request = "launch",
				name = profile.name,
				program = ctx.full_entry,
				cwd = root,
			}
		end,
	},
}

-- ----------------------------------------------------------------------------
-- 7. CUSTOM PROPERTY & METHOD INJECTION EXAMPLES (Like `lua/krs/langs/php/init.lua`)
-- ----------------------------------------------------------------------------

--- Custom property injected into module (e.g. custom debug port, sub-configs)
M.custom_port = 9005

--- Custom helper method injected into module (e.g. searching project vendor/bin)
--- @param buf integer Buffer handle.
--- @return boolean
function M.custom_helper(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	return name ~= "" and name:match("%.example$") ~= nil
end

-- ----------------------------------------------------------------------------
-- 8. BUFFER DEFAULTS & AUTOCMDS
-- ----------------------------------------------------------------------------

--- Fallback buffer options applied when no `.editorconfig` exists.
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply defaults if `.editorconfig` does not specify settings.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize language module autocmds and hooks.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "example",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
