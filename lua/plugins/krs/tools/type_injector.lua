-- ============================================================================
-- KRS PLUGIN: Type Injector -- per-project type definitions for Lua and TS/JS.
-- ============================================================================
-- WHAT IT DOES
--   Turns bundles of type definitions ("schemas") on and off PER PROJECT, so a
--   Love2D script gets Love types, a Neovim config gets vim types, and a plain
--   Lua project gets neither.
--
--   Schemas live in `schemas-langs/<lang>/<schema>/` (both in this config and in
--   `stdpath("data")`). For TS/JS they can also be installed straight from npm
--   (`@types/...`) through the picker.
--
-- HOW EACH LANGUAGE IS WIRED
--   lua_ls    `Lua.workspace.library` is rewritten and pushed live through
--             `workspace/didChangeConfiguration`.
--   TS server A single generated `.krsnvim/types.d.ts` holds one
--             `/// <reference path>` per active schema, and `tsconfig.json` is
--             patched to include it (the server ignores types outside the project).
--
-- COMMANDS
--   :TypeInjector / :KrsTypes      Open the picker.
--   :KrsGitignoreGenerated         Add the generated file to .gitignore.
--
-- PROJECT FILE -- `.krsnvim/types.json`
--   { "lua": ["vim_nvim"], "typescript_javascript": ["node"] }
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Per-project file, inside `.krsnvim/`.
	config_file = "types.json",

	--- Legacy single-file config at the project root.
	legacy_project_file = ".nvimkrs",

	--- Markers used to find the project root when no LSP client knows it.
	root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".krsnvim", ".nvimkrs", ".git" },

	--- Directory holding schema bundles, relative to `data` and `config`.
	schemas_dir = "schemas-langs",

	--- Generated TypeScript reference file, relative to the project root.
	ref_file = ".krsnvim/types.d.ts",

	--- Glob added to tsconfig `include` so the generated file is picked up.
	include_glob = ".krsnvim/**/*.d.ts",

	--- Notification title.
	notify_title = "KRS Type Injector",

	--- Supported languages. ADD A LANGUAGE HERE.
	---   key          Folder under `schemas-langs/`, and key in types.json.
	---   filetypes    Buffers that open this language's picker directly.
	---   lang_module  Which lua/krs/langs/<name> module's LSP client gets refreshed.
	--- `lang_module` names the lua/krs/langs/<name> module whose `lsp_server[1]`
	--- is the client to refresh -- NOT resolved eagerly here (this file loads as
	--- part of lua_ls's own settings, in lua/krs/langs/lua/init.lua, so requiring
	--- a langs module at this table's construction time would be circular).
	--- See `resolved_lsp_name` below.
	languages = {
		{ key = "lua", label = "Lua", filetypes = { "lua" }, lang_module = "lua" },
		{
			key = "typescript_javascript",
			label = "TypeScript / JavaScript",
			filetypes = { "typescript", "javascript", "typescriptreact", "javascriptreact" },
			lang_module = "typescript",
		},
	},
}

--- Resolves a `languages` entry's LSP client name, lazily (see the comment above).
--- @param lang table One entry from `M.settings.languages`.
--- @return string|nil
local function resolved_lsp_name(lang)
	if not lang.lang_module then
		return nil
	end
	local ok, mod = pcall(require, "krs.langs." .. lang.lang_module)
	return ok and mod.lsp_server and mod.lsp_server[1] or nil
end

--- Kept as top-level fields: other modules and docs refer to them.
M.REF_FILE = M.settings.ref_file
M.INCLUDE_GLOB = M.settings.include_glob

--- Placeholder row shown when a language has no schemas installed yet.
local INSTALL_PLACEHOLDER = "__install_new__"

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end
M.notify = notify

--- Empty activation table, one list per language.
--- @return table
local function empty_types()
	local out = {}
	for _, lang in ipairs(M.settings.languages) do
		out[lang.key] = {}
	end
	return out
end

-- ============================================================================
-- PROJECT RESOLUTION & PERSISTENCE
-- ============================================================================

--- Project root for a buffer.
--- An attached lua_ls/TS-server client knows the real root, so it wins; otherwise
--- walk up for a marker. The home directory is rejected: it is never a project.
---
--- @param bufnr integer|nil
--- @return string root
function M.get_project_root(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		for _, lang in ipairs(M.settings.languages) do
			if client.name == resolved_lsp_name(lang) and client.root_dir then
				return vim.fs.normalize(client.root_dir)
			end
		end
	end

	local dir = vim.fs.normalize(path.buffer_dir(bufnr))
	local root = vim.fs.root(dir, M.settings.root_markers)
	local home = vim.fs.normalize(vim.env.USERPROFILE or vim.env.HOME or ""):lower()

	if not root or vim.fs.normalize(root):lower() == home then
		return dir
	end
	return vim.fs.normalize(root)
end

--- Path of the activation file for a project.
--- Prefers `.krsnvim/types.json`, falls back to the legacy `.nvimkrs` file.
---
--- @param root string|nil Project root.
--- @return string filepath
function M.get_config_path(root)
	local norm_root = path.normalize(root or M.get_project_root())
	local krs_file = path.join(norm_root, ".krsnvim", M.settings.config_file)

	if path.is_dir(path.join(norm_root, ".krsnvim")) then
		return krs_file
	end

	local legacy = path.join(norm_root, M.settings.legacy_project_file)
	if path.is_file(legacy) then
		return legacy
	end
	return krs_file
end

--- Active schemas per language for a project.
--- @param root string|nil Project root.
--- @return table types `{ lua = {...}, typescript_javascript = {...} }`
function M.load_project_types(root)
	local parsed = store.load(M.get_config_path(root or M.get_project_root()), nil)
	if type(parsed) ~= "table" then
		return empty_types()
	end

	-- The legacy `.nvimkrs` file nests everything under a `types` key.
	if type(parsed.types) == "table" then
		parsed = parsed.types
	end

	local out = empty_types()
	for _, lang in ipairs(M.settings.languages) do
		if type(parsed[lang.key]) == "table" then
			out[lang.key] = parsed[lang.key]
		end
	end
	return out
end

--- Persists the activation table.
--- Writing to the legacy file merges into it instead of replacing it, so the
--- other settings it holds survive.
---
--- @param root string|nil Project root.
--- @param data table Activation table.
function M.save_project_types(root, data)
	local filepath = M.get_config_path(root or M.get_project_root())

	if filepath:sub(-#M.settings.legacy_project_file) == M.settings.legacy_project_file and path.is_file(filepath) then
		local existing = store.load(filepath, nil)
		if type(existing) == "table" then
			existing.types = data
			store.save(filepath, existing)
			return
		end
	end

	store.save(filepath, data)
end

-- ============================================================================
-- SCHEMA STORE
-- ============================================================================

--- Directories searched for a language's schemas: the writable data directory
--- first (npm installs land there), then the ones shipped with this config.
---
--- @param lang string Language key.
--- @return string[] roots
function M.get_schema_roots(lang)
	return {
		vim.fs.normalize(path.join(vim.fn.stdpath("data"), M.settings.schemas_dir, lang)),
		vim.fs.normalize(path.join(vim.fn.stdpath("config"), M.settings.schemas_dir, lang)),
	}
end

--- Directory new schemas are installed into.
--- @param lang string Language key.
--- @return string dir
function M.get_schemas_base_dir(lang)
	return M.get_schema_roots(lang)[1]
end

--- Locates an installed schema.
--- @param lang string Language key.
--- @param schema_name string Schema folder name.
--- @return string|nil dir
function M.resolve_schema_dir(lang, schema_name)
	for _, root in ipairs(M.get_schema_roots(lang)) do
		local candidate = path.join(root, schema_name)
		if path.is_dir(candidate) then
			return candidate
		end
	end
	return nil
end

--- Every schema installed for a language, sorted, without duplicates.
--- @param lang string Language key.
--- @return string[] names
function M.scan_available_schemas(lang)
	local seen, results = {}, {}

	for _, schemas_dir in ipairs(M.get_schema_roots(lang)) do
		if path.is_dir(schemas_dir) then
			for _, name in ipairs(vim.fn.readdir(schemas_dir)) do
				if not seen[name] and path.is_dir(path.join(schemas_dir, name)) then
					seen[name] = true
					table.insert(results, name)
				end
			end
		end
	end

	table.sort(results)
	return results
end

--- Version of an installed schema, read from its package.json.
--- @param lang string Language key.
--- @param schema_name string Schema folder name.
--- @return string|nil version Prefixed with "v", or nil when unknown.
function M.get_schema_version(lang, schema_name)
	local schema_dir = M.resolve_schema_dir(lang, schema_name)
	if not schema_dir then
		return nil
	end

	local candidates = {
		path.join(schema_dir, "package.json"),
		path.join(schema_dir, "node_modules/@types", schema_name, "package.json"),
	}
	for _, candidate in ipairs(candidates) do
		local version = store.load(candidate, {}).version
		if version then
			return "v" .. tostring(version)
		end
	end
	return nil
end

-- ============================================================================
-- LANGUAGE WIRING (DELEGATED)
-- ============================================================================

local lua_injector = require("plugins.krs.tools.type_injector_lua")
local ts_injector = require("plugins.krs.tools.type_injector_typescript")

-- Forwarding for any external references
function M.get_active_lua_libraries(root)
	return lua_injector.get_active_lua_libraries(root, M)
end

function M.sync_ts_type_links(root, active_names)
	return ts_injector.sync_ts_type_links(root, active_names, M)
end

--- Pushes the active schemas into the running language servers.
--- @param root string|nil Project root.
function M.apply_lsp_settings(root)
	root = root or M.get_project_root()
	lua_injector.apply_lsp_settings(root, M)
	ts_injector.apply_lsp_settings(root, M)
end

-- ============================================================================
-- NPM INSTALL (DELEGATED)
-- ============================================================================

--- Installs a TypeScript type package into the schema store.
--- Accepts `node`, `@scope/pkg`, and either with an `@version` suffix. A bare
--- name is resolved as `@types/<name>`; a scoped name is taken as-is.
---
--- @param input_pkg string Package specification.
--- @param callback fun(ok: boolean, schema_folder: string)|nil
function M.install_npm_types(input_pkg, callback)
	ts_injector.install_npm_types(input_pkg, callback, M)
end

-- ============================================================================
-- PICKER
-- ============================================================================

--- Language definition matching a filetype, or nil.
--- @param filetype string
--- @return table|nil language
local function language_for_filetype(filetype)
	for _, lang in ipairs(M.settings.languages) do
		if vim.tbl_contains(lang.filetypes, filetype) then
			return lang
		end
	end
	return nil
end

--- Opens the schema picker for one language.
--- @param lang table Entry from `M.settings.languages`.
--- @param root string Project root.
--- @param active_data table Activation table, mutated in place.
local function open_schema_picker(lang, root, active_data)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local active_set = {}
	for _, name in ipairs(active_data[lang.key] or {}) do
		active_set[name] = true
	end

	local items = {}
	for _, name in ipairs(M.scan_available_schemas(lang.key)) do
		local version = M.get_schema_version(lang.key, name)
		table.insert(items, {
			name = name,
			is_active = active_set[name] == true,
			display = (active_set[name] and "✅ " or "⬜ ") .. name .. (version and (" (" .. version .. ")") or ""),
		})
	end

	if #items == 0 and lang.key == "typescript_javascript" then
		table.insert(items, {
			name = INSTALL_PLACEHOLDER,
			is_active = false,
			display = "➕ [No schemas found] Press Ctrl+N to install from NPM",
		})
	end

	--- Persists a change and refreshes the language servers.
	local function persist()
		M.save_project_types(root, active_data)
		M.apply_lsp_settings(root)
	end

	--- Removes a schema from the active list of this language.
	local function deactivate(name)
		local kept = {}
		for _, existing in ipairs(active_data[lang.key]) do
			if existing ~= name then
				table.insert(kept, existing)
			end
		end
		active_data[lang.key] = kept
	end

	--- Prompts for an npm package, installs it, and activates it.
	local function install_flow(prompt)
		vim.ui.input({ prompt = prompt }, function(pkg)
			if not pkg or pkg == "" then
				return
			end
			M.install_npm_types(pkg, function(ok, schema_folder)
				if ok and not vim.tbl_contains(active_data.typescript_javascript, schema_folder) then
					table.insert(active_data.typescript_javascript, schema_folder)
					persist()
				end
				M.open_menu()
			end)
		end)
	end

	pickers
		.new({
			prompt_title = " 💉 Type Injector ("
				.. lang.label
				.. ") | Enter/Tab: Toggle | Ctrl+N: Install NPM | Ctrl+D: Delete ",
			finder = finders.new_table({
				results = items,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						-- Active schemas sort first.
						ordinal = (entry.is_active and "0_" or "1_") .. entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				--- Selected item, or nil.
				local function selected()
					local selection = action_state.get_selected_entry()
					return selection and selection.value or nil
				end

				--- Binds one action to several key/mode pairs.
				local function map_all(bindings, fn)
					for _, binding in ipairs(bindings) do
						map(binding[1], binding[2], fn)
					end
				end

				local function toggle_selected()
					local item = selected()
					if not item then
						return
					end

					if item.name == INSTALL_PLACEHOLDER then
						actions.close(prompt_bufnr)
						vim.schedule(function()
							install_flow("Enter NPM package name (e.g. node, express, react): ")
						end)
						return
					end

					if item.is_active then
						deactivate(item.name)
					else
						table.insert(active_data[lang.key], item.name)
					end
					persist()

					actions.close(prompt_bufnr)
					vim.schedule(function()
						open_schema_picker(lang, root, active_data)
					end)
				end

				actions.select_default:replace(toggle_selected)
				map("n", "<Space>", toggle_selected)
				map({ "i", "n" }, "<Tab>", toggle_selected)

				map_all({ { "i", "<C-n>" }, { "n", "<C-n>" }, { "i", "<C-i>" }, { "n", "<C-i>" }, { "n", "i" } }, function()
					actions.close(prompt_bufnr)
					vim.schedule(function()
						install_flow("Enter NPM type package (e.g. node, express@18, react): ")
					end)
				end)

				map_all({ { "i", "<C-d>" }, { "n", "<C-d>" }, { "n", "d" } }, function()
					local item = selected()
					if not item or item.name == INSTALL_PLACEHOLDER then
						return
					end

					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Delete schema '" .. item.name .. "' from store? (y/n): " }, function(answer)
							if answer and answer:lower() == "y" then
								local schema_dir = M.resolve_schema_dir(lang.key, item.name)
								if schema_dir then
									vim.fn.delete(schema_dir, "rf")
								end
								deactivate(item.name)
								persist()
								notify("🗑️ Schema deleted: " .. item.name)
							end
							open_schema_picker(lang, root, active_data)
						end)
					end)
				end)

				return true
			end,
		})
		:find()
end

--- Opens the type injector for the current buffer's language, asking which one
--- when the buffer is neither Lua nor TS/JS.
function M.open_menu()
	local root = M.get_project_root()
	local active_data = M.load_project_types(root)

	local lang = language_for_filetype(vim.bo.filetype)
	if lang then
		open_schema_picker(lang, root, active_data)
		return
	end

	local choices = {}
	for index, entry in ipairs(M.settings.languages) do
		table.insert(choices, index .. ". " .. entry.label)
	end

	vim.ui.select(choices, { prompt = "Select Language for Type Injector:" }, function(choice)
		if not choice then
			return
		end
		local index = tonumber(choice:match("^(%d+)%."))
		if index and M.settings.languages[index] then
			open_schema_picker(M.settings.languages[index], root, active_data)
		end
	end)
end

-- ============================================================================
-- HOUSEKEEPING
-- ============================================================================

--- Adds .krsnvim generated files and ignore patterns to the project's .gitignore (prepended to the beginning of the file).
--- @param root string|nil Project root.
function M.gitignore_generated(root)
	local gitignore = path.join(path.normalize(vim.fs.normalize(root or M.get_project_root())), ".gitignore")
	local default_entries = {
		M.settings.ref_file or ".krsnvim/types.d.ts",
		".krsnvim/",
		"*.krsnvim",
	}

	local existing_lines = {}
	local existing_set = {}
	if path.is_file(gitignore) then
		existing_lines = vim.fn.readfile(gitignore)
		for _, line in ipairs(existing_lines) do
			existing_set[vim.trim(line)] = true
		end
	end

	local to_add = {}
	for _, entry in ipairs(default_entries) do
		if not existing_set[entry] then
			table.insert(to_add, entry)
		end
	end

	if #to_add == 0 then
		notify(".krsnvim ignore entries are already in .gitignore")
		return
	end

	local new_lines = {}
	for _, entry in ipairs(to_add) do
		table.insert(new_lines, entry)
	end

	if #existing_lines > 0 then
		table.insert(new_lines, "")
		for _, line in ipairs(existing_lines) do
			table.insert(new_lines, line)
		end
	end

	vim.fn.writefile(new_lines, gitignore)
	notify("Added " .. table.concat(to_add, ", ") .. " to top of .gitignore")
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers the commands and re-applies the project's types whenever one of the
--- supported language servers attaches.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local commands = {
		TypeInjector = { M.open_menu, "Open KRS Modular Type Injector Menu" },
		KrsTypes = { M.open_menu, "Open KRS Modular Type Injector Menu" },
		KrsGitignoreGenerated = {
			function()
				M.gitignore_generated()
			end,
			"Add .krsnvim ignore entries (*.krsnvim, .krsnvim/, types.d.ts) to .gitignore",
		},
	}
	for name, spec in pairs(commands) do
		vim.api.nvim_create_user_command(name, function()
			spec[1]()
		end, { desc = spec[2] })
	end

	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("KrsTypeInjectorGroup", { clear = true }),
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client then
				return
			end
			for _, lang in ipairs(M.settings.languages) do
				if client.name == lang.lsp then
					M.apply_lsp_settings(M.get_project_root())
					return
				end
			end
		end,
	})
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.TypeInjector = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_type_injector",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "TypeInjector", "KrsTypes", "KrsGitignoreGenerated" },
	event = { "LspAttach" },
	config = M.setup,
}, { __index = M })
