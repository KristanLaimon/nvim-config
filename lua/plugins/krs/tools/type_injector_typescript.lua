local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")

local M = {}

--- Adds `glob` to a tsconfig/jsconfig `include` array, whatever shape it has.
--- @param cfg string Config file path.
--- @param glob string Glob to add.
--- @return boolean patched False when the file could not be handled.
local function patch_include(cfg, glob)
	local content = table.concat(vim.fn.readfile(cfg), "\n")
	if content:find(glob, 1, true) then
		return true
	end

	local patched
	if content:find('"include"%s*:%s*%[%s*%]') then
		patched = content:gsub('"include"%s*:%s*%[%s*%]', '"include": ["' .. glob .. '"]', 1)
	elseif content:find('"include"%s*:%s*%[') then
		patched = content:gsub('("include"%s*:%s*%[)', '%1 "' .. glob .. '",', 1)
	elseif content:find("^%s*{") then
		-- No include at all: add one. With an explicit "files" list, adding "**/*"
		-- would widen the project, so only the generated glob goes in.
		local entries = content:find('"files"%s*:') and '"' .. glob .. '"' or '"**/*", "' .. glob .. '"'
		patched = content:gsub("^(%s*{)", '%1\n\t"include": [' .. entries .. "],", 1)
	else
		return false
	end

	if patched == content then
		return false
	end
	vim.fn.writefile(vim.split(patched, "\n"), cfg)
	return true
end

--- Makes sure the project has a tsconfig that includes the generated types,
--- creating one when there is none.
--- @param norm_root string Normalized project root.
--- @param core table type_injector core module.
local function ensure_ts_project_config(norm_root, core)
	local found = vim.fs.find({ "tsconfig.json", "jsconfig.json" }, {
		path = norm_root,
		upward = true,
		type = "file",
		limit = 1,
	})

	if not found[1] then
		vim.fn.writefile({
			"{",
			'\t"compilerOptions": {',
			'\t\t"allowJs": true',
			"\t},",
			'\t"include": ["**/*", "' .. core.settings.include_glob .. '"]',
			"}",
		}, path.join(norm_root, "tsconfig.json"))
		core.notify("Created tsconfig.json -- the TS server ignores injected types without one.")
		return
	end

	local cfg = vim.fs.normalize(found[1])
	local cfg_dir = vim.fs.dirname(cfg)

	-- A config further up the tree needs the path from ITS directory down to us.
	local glob = core.settings.include_glob
	if cfg_dir:lower() ~= norm_root:lower() then
		glob = norm_root:sub(#cfg_dir + 2) .. "/" .. core.settings.include_glob
	end

	if not patch_include(cfg, glob) then
		core.notify(
			'Add "' .. glob .. '" to "include" in ' .. cfg .. "\ninjected types stay inactive until then.",
			vim.log.levels.WARN
		)
	end
end

--- Declaration files contributed by the active schemas.
--- An npm-installed schema exposes `node_modules/@types/<pkg>/index.d.ts`; a
--- hand-written one exposes `index.d.ts`, or any `*.d.ts` it contains.
---
--- @param active_names string[] Active schema names.
--- @param core table type_injector core module.
--- @return string[] files Sorted absolute paths.
local function active_schema_entries(active_names, core)
	local entries = {}

	for _, name in ipairs(active_names) do
		local schema_dir = core.resolve_schema_dir("typescript_javascript", name)
		if schema_dir then
			local types_dir = path.join(schema_dir, "node_modules/@types")
			if path.is_dir(types_dir) then
				for pkg, kind in vim.fs.dir(types_dir) do
					local index = path.join(types_dir, pkg, "index.d.ts")
					if kind == "directory" and path.is_file(index) then
						table.insert(entries, index)
					end
				end
			else
				local index = path.join(schema_dir, "index.d.ts")
				if path.is_file(index) then
					table.insert(entries, index)
				else
					for _, file in ipairs(vim.fn.glob(schema_dir .. "/*.d.ts", false, true)) do
						table.insert(entries, vim.fs.normalize(file))
					end
				end
			end
		end
	end

	table.sort(entries)
	return entries
end

--- Rewrites `.krsnvim/types.d.ts` and tells the TS server the file changed.
--- With no active schemas the file is deleted instead.
---
--- @param root string Project root.
--- @param active_names string[]|nil Active TS/JS schema names.
--- @param core table type_injector core module.
function M.sync_ts_type_links(root, active_names, core)
	local norm_root = vim.fs.normalize(root)
	local ref_file = path.join(norm_root, core.settings.ref_file)
	local entries = active_schema_entries(active_names or {}, core)

	--- The TS server watches files rather than polling; `kind` is the LSP
	--- FileChangeType (1 = created, 2 = changed, 3 = deleted).
	local ts_lsp_name = require("krs.langs.typescript").lsp_server[1]
	local function notify_ts_lsp(kind, also_config)
		local changes = { { uri = vim.uri_from_fname(ref_file), type = kind } }
		if also_config then
			table.insert(changes, { uri = vim.uri_from_fname(path.join(norm_root, "tsconfig.json")), type = 1 })
		end
		for _, client in ipairs(vim.lsp.get_clients({ name = ts_lsp_name })) do
			client:notify("workspace/didChangeWatchedFiles", { changes = changes })
		end
	end

	if #entries == 0 then
		if path.is_file(ref_file) then
			vim.fn.delete(ref_file)
			notify_ts_lsp(3, false)
		end
		return
	end

	local had_config = path.is_file(path.join(norm_root, "tsconfig.json"))
	ensure_ts_project_config(norm_root, core)

	path.ensure_dir(vim.fs.dirname(ref_file))

	local lines = { "// Auto-generated by KRS Type Injector -- do not edit." }
	for _, entry in ipairs(entries) do
		table.insert(lines, '/// <reference path="' .. entry .. '" />')
	end
	vim.fn.writefile(lines, ref_file)

	notify_ts_lsp(1, not had_config)
end

function M.apply_lsp_settings(root, core)
	local active = core.load_project_types(root)
	M.sync_ts_type_links(root, active.typescript_javascript, core)
end

--- Installs a TypeScript type package into the schema store.
--- Accepts `node`, `@scope/pkg`, and either with an `@version` suffix. A bare
--- name is resolved as `@types/<name>`; a scoped name is taken as-is.
---
--- @param input_pkg string Package specification.
--- @param callback fun(ok: boolean, schema_folder: string)|nil
--- @param core table type_injector core module.
function M.install_npm_types(input_pkg, callback, core)
	if not input_pkg or input_pkg == "" then
		return
	end

	local pkg_name = vim.trim(input_pkg)
	local target_version = ""

	-- Search from index 2, so a leading `@scope` is not read as a version.
	local at_index = pkg_name:find("@", 2)
	if at_index then
		target_version = pkg_name:sub(at_index + 1)
		pkg_name = pkg_name:sub(1, at_index - 1)
	end

	local npm_package, schema_folder
	if pkg_name:find("^@") then
		npm_package = pkg_name
		schema_folder = pkg_name:gsub("^@", ""):gsub("/", "__")
	else
		npm_package = "@types/" .. pkg_name
		schema_folder = pkg_name
	end
	if target_version ~= "" then
		npm_package = npm_package .. "@" .. target_version
	end

	local schema_dir = path.ensure_dir(path.join(core.get_schemas_base_dir("typescript_javascript"), schema_folder))

	-- npm refuses to install into a directory with no manifest.
	local pkg_json = path.join(schema_dir, "package.json")
	if not path.is_file(pkg_json) then
		store.save(pkg_json, { name = "krs-schema-" .. schema_folder, private = true })
	end

	core.notify("📦 Installing " .. npm_package .. " via npm...")

	vim.system({ "npm", "install", "--save-dev", npm_package }, { cwd = schema_dir }, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				core.notify("✅ Installed " .. npm_package .. " successfully!")
			else
				core.notify("❌ Failed to install " .. npm_package .. ":\n" .. (obj.stderr or ""), vim.log.levels.ERROR)
			end
			if callback then
				callback(obj.code == 0, schema_folder)
			end
		end)
	end)
end

return setmetatable({
	name = "krs_type_injector_typescript",
	dir = require("krs.core.lazyspec").for_module(),
}, { __index = M })
