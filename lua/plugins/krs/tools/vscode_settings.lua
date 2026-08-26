-- ============================================================================
-- KRS PLUGIN: VSCode Settings Sync -- Auto-apply `.vscode/settings.json` in Neovim.
-- ============================================================================
-- WHAT IT DOES
--   Reads `.vscode/settings.json` (and `.krsnvim/settings.json`) at project root
--   and maps pertinent VSCode settings directly into Neovim options and LSP options.
--
-- SUPPORTED SETTINGS MAPPINGS
--   * editor.tabSize                  -> vim.bo.tabstop & vim.bo.shiftwidth
--   * editor.insertSpaces             -> vim.bo.expandtab
--   * files.eol                       -> vim.bo.fileformat ("unix" or "dos")
--   * editor.formatOnSave             -> vim.b.autoformat
--   * editor.wordWrap                 -> vim.wo.wrap ("on"/"off")
--   * editor.rulers                   -> vim.wo.colorcolumn
--   * python.defaultInterpreterPath   -> Pyright / Debugpy Python path
--   * php.validate.executablePath     -> PHP binary path
--   * lua.diagnostics.globals         -> lua_ls workspace globals
--
-- COMMANDS
--   :VSCodeSettings / :KrsVSCodeSettings  View or edit active VSCode settings.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path = lazy_req("krs.core.path")

local M = {}

M.settings = {
	notify_title = "KRS VSCode Settings",
	config_files = { ".vscode/settings.json", ".krsnvim/settings.json" },
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

--- Strips JSON comments (lines starting with // or /* ... */) to safely decode VSCode JSON files.
--- @param content string
--- @return string
local function strip_json_comments(content)
	if not content or content == "" then
		return ""
	end
	-- Remove block comments
	content = content:gsub("/%*.-%*/", "")
	-- Remove line comments
	content = content:gsub("//[^\r\n]*", "")
	return content
end

local _settings_cache = {}

--- Resolves the settings.json file for a given project root.
--- @param root string|nil
--- @param force_reload boolean|nil
--- @return string|nil filepath, table|nil decoded_json
function M.load_settings(root, force_reload)
	root = path.normalize(root or project.root())
	if not force_reload and _settings_cache[root] ~= nil then
		local cached = _settings_cache[root]
		return cached.filepath, cached.settings
	end

	for _, rel_path in ipairs(M.settings.config_files) do
		local full_path = path.join(root, rel_path)
		if path.is_file(full_path) then
			local f = io.open(full_path, "r")
			if f then
				local raw = f:read("*a")
				f:close()
				local clean = strip_json_comments(raw)
				local ok, decoded = pcall(vim.json.decode, clean)
				if ok and type(decoded) == "table" then
					_settings_cache[root] = { filepath = full_path, settings = decoded }
					return full_path, decoded
				end
			end
		end
	end
	_settings_cache[root] = { filepath = nil, settings = nil }
	return nil, nil
end

--- Applies VSCode settings to the current buffer and global environment.
--- @param bufnr integer|nil
function M.apply_settings(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local root = project.root(bufnr)
	local filepath, settings = M.load_settings(root)
	if not settings then
		return
	end

	-- 1. Editor Indentation (tabSize, insertSpaces)
	local tab_size = settings["editor.tabSize"]
	if type(tab_size) == "number" then
		vim.bo[bufnr].tabstop = tab_size
		vim.bo[bufnr].shiftwidth = tab_size
		vim.bo[bufnr].softtabstop = tab_size
	end

	local insert_spaces = settings["editor.insertSpaces"]
	if type(insert_spaces) == "boolean" then
		vim.bo[bufnr].expandtab = insert_spaces
	end

	-- 2. Line Endings (files.eol)
	local eol = settings["files.eol"]
	if type(eol) == "string" then
		if eol == "\n" or eol == "lf" then
			vim.bo[bufnr].fileformat = "unix"
		elseif eol == "\r\n" or eol == "crlf" then
			vim.bo[bufnr].fileformat = "dos"
		end
	end

	-- 3. Word Wrap (editor.wordWrap)
	local wrap = settings["editor.wordWrap"]
	if wrap == "on" or wrap == true then
		vim.wo.wrap = true
	elseif wrap == "off" or wrap == false then
		vim.wo.wrap = false
	end

	-- 4. Rulers (editor.rulers)
	local rulers = settings["editor.rulers"]
	if type(rulers) == "table" and #rulers > 0 then
		local cols = {}
		for _, r in ipairs(rulers) do
			if type(r) == "number" then
				table.insert(cols, tostring(r))
			end
		end
		if #cols > 0 then
			vim.wo.colorcolumn = table.concat(cols, ",")
		end
	end

	-- 5. Format on save (editor.formatOnSave)
	local fmt_on_save = settings["editor.formatOnSave"]
	if type(fmt_on_save) == "boolean" then
		vim.b[bufnr].autoformat = fmt_on_save
	end

	-- 6. Language specific paths (Python, PHP, Lua)
	local py_path = settings["python.defaultInterpreterPath"] or settings["python.pythonPath"]
	if type(py_path) == "string" and py_path ~= "" then
		vim.g.python3_host_prog = py_path
	end

	local php_path = settings["php.validate.executablePath"]
	if type(php_path) == "string" and php_path ~= "" then
		vim.g.php_executable_path = php_path
	end

	-- 7. Lua diagnostics globals
	local lua_globals = settings["lua.diagnostics.globals"] or settings["Lua.diagnostics.globals"]
	if type(lua_globals) == "table" and #lua_globals > 0 then
		vim.g.lua_diagnostics_globals = lua_globals
	end
end

--- Shows the active VSCode settings summary or opens the settings file.
function M.open_settings_menu()
	local root = project.root()
	local filepath, settings = M.load_settings(root)

	if not filepath then
		local default_path = path.join(root, ".vscode", "settings.json")
		vim.ui.select({
			"➕ Create .vscode/settings.json in Project Root",
			"❌ Cancel",
		}, { prompt = "No .vscode/settings.json found in " .. root }, function(choice, idx)
			if idx == 1 then
				path.ensure_dir(path.join(root, ".vscode"))
				local f = io.open(default_path, "w")
				if f then
					f:write(
						'{\n  "editor.tabSize": 4,\n  "editor.insertSpaces": true,\n  "files.eol": "\\n",\n  "editor.formatOnSave": true\n}\n'
					)
					f:close()
				end
				vim.cmd("edit " .. vim.fn.fnameescape(default_path))
			end
		end)
		return
	end

	local options = {
		"📝 Edit " .. filepath,
		"🔄 Re-apply VSCode Settings to Current Buffer",
	}

	vim.ui.select(options, { prompt = "⚙️ VSCode Settings (" .. filepath .. ")" }, function(choice, idx)
		if idx == 1 then
			vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		elseif idx == 2 then
			M.apply_settings()
			notify("Applied settings from " .. filepath)
		end
	end)
end

--- Sets up autocommands to automatically apply VSCode settings on buffer load.
function M.setup()
	local group = vim.api.nvim_create_augroup("KrsVSCodeSettingsSync", { clear = true })
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "DirChanged" }, {
		group = group,
		callback = function(args)
			M.apply_settings(args.buf)
		end,
	})

	vim.api.nvim_create_user_command("VSCodeSettings", function()
		M.open_settings_menu()
	end, { desc = "Open VSCode settings menu" })

	vim.api.nvim_create_user_command("KrsVSCodeSettings", function()
		M.open_settings_menu()
	end, { desc = "Open VSCode settings menu" })
end

return setmetatable({
	name = "vscode_settings",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VeryLazy",
	config = M.setup,
}, { __index = M })
