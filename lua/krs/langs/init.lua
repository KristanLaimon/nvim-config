-- ============================================================================
-- KRS LANGS: Centralized Per-Language Configuration Manager
-- ============================================================================
-- WHAT IT DOES
--   1. Automatically imports and executes `setup()` for per-language submodules
--      under `lua/krs/langs/<lang>/init.lua`.
--   2. Provides `has_editorconfig(buf)` and `has_project_config(buf, config_files)`
--      helpers so per-language defaults apply only when no project-level
--      formatter configs (Prettier, Biome, ESLint, EditorConfig, Pint, etc.) exist.
--
-- WHERE LANGUAGE-SPECIFIC CONFIG LIVES
--   This file only holds generic, language-agnostic helpers and the module
--   registry. Anything specific to one language or its tools (LSP server
--   settings, mason package names, formatter file lists, conform entries)
--   belongs in that language's own lua/krs/langs/<lang>/init.lua -- see
--   lua/krs/langs/typescript/init.lua for the fullest example:
--     M.lsp_server        array of lspconfig server names this language owns
--     M.lsp_config         { [server_name] = <lspconfig opts> }
--     M.mason              { [tool_name] = { mason=, cmd=, lang=/name=, type= } }
--     M.formatters_by_ft    { [filetype] = <conform formatter list> }
--     M.conform_formatters  { [formatter_name] = <conform formatter opts> }
--   lua/plugins/lsp/lsp.lua, lua/plugins/lsp/formatting.lua and
--   lua/krs/core/installer.lua all read these fields instead of hardcoding
--   settings -- swapping a server or formatter is a one-file edit.
-- ============================================================================

--- Mason package metadata, keyed by lspconfig/formatter/tool name -- see any
--- language module's `M.mason` table.
---@class KrsMasonToolInfo
---@field mason string Mason package/registry name.
---@field type "lsp"|"formatter"|"dap" Drives the Language Tooling Manager UI grouping.
---@field cmd string CLI binary used to detect an already-installed tool.
---@field lang? string Human-readable language label (lsp/dap tools).
---@field name? string Human-readable tool label (formatter tools).

--- Shape every `lua/krs/langs/<lang>/init.lua` submodule may export. Every
--- field is optional -- see docs/adding-language.md for which ones a new
--- language actually needs.
---@class KrsLangModule
---@field lsp_server? string[] lspconfig/mason server name(s) this language owns.
---@field lsp_config? table<string, vim.lsp.Config> lspconfig opts, keyed by server name; merged into lsp.lua's opts.servers. Annotate each module's own `M.lsp_config` the same way for field-level completion/hover while authoring it.
---@field mason? table<string, KrsMasonToolInfo> Mason package metadata, keyed by lspconfig/formatter/tool name.
---@field mason_order? string[] Preferred Mason install/display order for this language's tools.
---@field formatters_by_ft? table<string, table> conform.nvim formatter list, keyed by filetype.
---@field conform_formatters? table<string, table> conform.nvim per-formatter option overrides, keyed by formatter name.
---@field formatter_configs? string[] Formatter/tool config filenames that indicate a project-managed code style.
---@field defaults? table<string, any> Fallback `vim.bo` options applied when no project formatter config exists.
---@field apply_defaults? fun(buf: integer) Applies `defaults` to `buf` unless a project config overrides them.
---@field setup? fun() Registers this language's autocmds; called once by `M.setup()` below.
---@field dap_setup? fun(dap: table) Registers this language's DAP adapter(s).
---@field launch_runtimes? table<string, table> Launch-profile runtimes this language owns (see lua/krs/launch/runtimes.lua).
---@field bundle_name? string Display name (with icon) for this language's entry in the Language Tooling Manager (`:LanguageManager`).
---@field is_minimal? boolean Marks the always-on core bundle (Lua only); pre-selected and excluded from the "pending" count.
---@field requires? { cmd: string, name: string, alt?: string, hint?: string }[] System runtimes the bundle needs before Mason packages can install; missing ones block the bundle with a lock icon.
---@field treesitter? string[] Treesitter parser names the Language Tooling Manager installs alongside this language's Mason packages.
---@field bundle_extra_mason_pkgs? string[] Mason package names the bundle installs beyond what `mason_order` resolves -- for tools intentionally absent from `M.mason` (e.g. a DAP tool installed through a different mechanism, a standalone linter).
---@field dotnet_tools? string[] `dotnet tool install -g` package names the Language Tooling Manager installs for this language.

local M = {}

--- Helper to check if an `.editorconfig` file has applied settings to the buffer,
--- or if an `.editorconfig` file exists in the directory hierarchy of the buffer.
--- @param buf integer|nil Buffer handle (defaults to current).
--- @return boolean has_editorconfig
function M.has_editorconfig(buf)
	buf = (buf and buf ~= 0) and buf or vim.api.nvim_get_current_buf()

	-- Check Neovim buffer-local editorconfig flags
	if vim.b[buf].editorconfig ~= nil or vim.b[buf].editorconfig_applied then
		return true
	end

	-- Check if an .editorconfig file exists in the buffer's folder hierarchy
	local name = vim.api.nvim_buf_get_name(buf)
	if name and name ~= "" then
		local dir = vim.fs.dirname(name)
		if dir and dir ~= "" then
			local found = vim.fs.find(".editorconfig", { upward = true, path = dir })
			if found and #found > 0 then
				return true
			end
		end
	end

	return false
end

--- Helper to check whether a buffer belongs to a project with EditorConfig or any
--- specific formatter/tool configuration files (e.g. Prettier, Biome, ESLint, Deno, Pint).
--- @param buf integer|nil Buffer handle (defaults to current).
--- @param config_files table|nil Optional list of formatter/tool config filenames to look for.
--- @return boolean has_config
function M.has_project_config(buf, config_files)
	buf = (buf and buf ~= 0) and buf or vim.api.nvim_get_current_buf()

	if M.has_editorconfig(buf) then
		return true
	end

	if config_files and #config_files > 0 then
		local name = vim.api.nvim_buf_get_name(buf)
		if name and name ~= "" then
			local dir = vim.fs.dirname(name)
			if dir and dir ~= "" then
				local found = vim.fs.find(config_files, { upward = true, path = dir })
				if found and #found > 0 then
					return true
				end
			end
		end
	end

	return false
end

--- Registered per-language configuration submodules.
---@type table<string, KrsLangModule>
M.langs = {
	php = require("krs.langs.php"),
	typescript = require("krs.langs.typescript"),
	web = require("krs.langs.web"),
	astro = require("krs.langs.astro"),
	web_ui = require("krs.langs.web_ui"),
	csharp = require("krs.langs.csharp"),
	go = require("krs.langs.go"),
	rust = require("krs.langs.rust"),
	python = require("krs.langs.python"),
	lua = require("krs.langs.lua"),
	bash = require("krs.langs.bash"),
	docker = require("krs.langs.docker"),
	proto = require("krs.langs.proto"),
}

--- Display order for `M.langs` in the Language Tooling Manager (`:LanguageManager`)
--- -- `pairs()` over `M.langs` has no stable order, and this is otherwise the only
--- language-agnostic thing left to declare once; everything else per bundle
--- (name, requires, Mason packages, Treesitter parsers) comes from the module
--- itself, see lua/krs/core/installer.lua's `M.language_bundles`.
M.lang_order =
	{ "lua", "php", "go", "rust", "python", "csharp", "web", "astro", "web_ui", "docker", "proto", "bash" }

--- Initialize all per-language configuration submodules.
function M.setup()
	for _, lang in pairs(M.langs) do
		if type(lang) == "table" and type(lang.setup) == "function" then
			lang.setup()
		end
	end
end

return M
