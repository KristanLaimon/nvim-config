local lazy_req = require("krs.core.lazy_require")
local path = lazy_req("krs.core.path")

local M = {}

local _cached_luarocks_paths = nil
local function get_luarocks_paths()
	if _cached_luarocks_paths ~= nil then
		return _cached_luarocks_paths
	end
	_cached_luarocks_paths = {}
	if vim.fn.executable("luarocks") == 1 and vim.fn.executable("lua") == 1 then
		local out = vim.fn.system({ "luarocks", "path", "--lr-path" })
		if vim.v.shell_error == 0 and out then
			for _, p in ipairs(vim.split(out, ";", { trimempty = true })) do
				p = p:gsub("%?%.lua%s*$", ""):gsub("%?[/\\]init%.lua%s*$", ""):gsub("[/\\]$", "")
				p = vim.trim(p)
				if p ~= "" and not vim.tbl_contains(_cached_luarocks_paths, p) then
					table.insert(_cached_luarocks_paths, p)
				end
			end
		end
	end
	return _cached_luarocks_paths
end

local function get_local_luarocks_paths(root)
	local results = {}
	if not root then
		return results
	end
	for _, dir in ipairs({ "lua_modules", ".luarocks" }) do
		local share = path.join(root, dir, "share", "lua")
		if path.is_dir(share) then
			for _, ver in ipairs(vim.fn.readdir(share)) do
				local full = path.join(share, ver)
				if path.is_dir(full) then
					table.insert(results, full)
				end
			end
		end
	end
	return results
end

--- Library paths lua_ls should load: the Neovim runtime plus every active schema.
--- @param root string|nil Project root.
--- @param core table type_injector core module.
--- @return string[] paths
function M.get_active_lua_libraries(root, core)
	local config_lua = vim.fn.stdpath("config") .. "/lua"
	local paths = { vim.env.VIMRUNTIME, config_lua }
	for _, name in ipairs(core.load_project_types(root).lua) do
		local schema_path = core.resolve_schema_dir("lua", name)
		if schema_path then
			table.insert(paths, schema_path)
		end
	end

	-- Inject local trees first so they take precedence over global installations
	if root then
		for _, p in ipairs(get_local_luarocks_paths(root)) do
			table.insert(paths, p)
		end
	end

	-- Then inject global trees
	for _, p in ipairs(get_luarocks_paths()) do
		table.insert(paths, p)
	end

	return paths
end

--- Directories lua_ls should ignore: inactive schemas and common non-project folders.
--- @param root string|nil Project root.
--- @param core table type_injector core module.
--- @return string[] ignored
function M.get_ignored_lua_directories(root, core)
	local ignored = { ".vscode" }
	local active_names = {}
	if root then
		for _, name in ipairs(core.load_project_types(root).lua or {}) do
			active_names[name] = true
		end
	end

	local all_schemas = core.scan_available_schemas("lua")
	for _, name in ipairs(all_schemas) do
		if not active_names[name] then
			local schema_dir = core.resolve_schema_dir("lua", name)
			if schema_dir then
				table.insert(ignored, schema_dir)
				if root then
					local norm_root = vim.fs.normalize(root)
					local norm_dir = vim.fs.normalize(schema_dir)
					if norm_dir:sub(1, #norm_root) == norm_root then
						local rel = norm_dir:sub(#norm_root + 2)
						if rel ~= "" and not vim.tbl_contains(ignored, rel) then
							table.insert(ignored, rel)
						end
					end
				end
			end
		end
	end

	return ignored
end

function M.apply_lsp_settings(root, core)
	local lua_libs = M.get_active_lua_libraries(root, core)
	local lua_ignored = M.get_ignored_lua_directories(root, core)
	for _, client in ipairs(vim.lsp.get_clients({ name = "lua_ls" })) do
		local settings = client.config and client.config.settings
		if settings and settings.Lua then
			settings.Lua.workspace = settings.Lua.workspace or {}
			settings.Lua.workspace.library = lua_libs
			settings.Lua.workspace.ignoreDir = lua_ignored
			client.notify("workspace/didChangeConfiguration", { settings = settings })
		end
	end
end

return setmetatable({
	name = "krs_type_injector_lua",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = true,
}, { __index = M })
