-- ============================================================================
-- KRS PLUGIN: Floating File Explorer -- pure Lua, no external binaries.
-- ============================================================================
-- WHAT IT DOES
--   Browses the filesystem in a Telescope picker with no `fd`/`rg` dependency, so
--   it never fails with "Executable not found". Two pickers share one directory
--   listing engine:
--     * the explorer  -- browse, create, rename, delete, copy, favorite, open
--     * the move target picker -- navigate to a folder and drop a file into it
--
-- KEYS (explorer)
--   <CR> open file / enter folder    o  set folder as project root (CWD)
--   a create   r rename   d delete   c copy   m move   f favorite
--   h/<BS>/u parent      l/<Right> enter    ? help    q close
--
-- WHERE IT STARTS
--   On the dashboard: the Desktop. Otherwise the current working directory,
--   unless that is the bare home directory with no project file open -- then the
--   Desktop again, because home is almost never what you meant.
--
-- FAVORITES -- `<data>/project_favorites.json`
--   A path -> true map. Favorited directories are also pushed into project.nvim's
--   recent list so they show up on the dashboard.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local path = lazy_req("krs.core.path")
local favorites = lazy_req("krs.projects.favorites")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Directories tried, in order, when looking for the Desktop.
	desktop_dirs = { "Desktop", "OneDrive/Desktop" },

	--- Telescope layout shared by both pickers.
	layout = { width = 0.85, height = 0.80, prompt_position = "top" },

	--- Row icons.
	icons = { dir = "📁 ", file = "📄 ", favorite = "⭐ " },

	keys = {
		--- Open the explorer. Bound in normal, insert, visual and terminal mode.
		open = { "<C-/>", "<C-_>" },
	},
}

-- ============================================================================
-- FAVORITES
-- ============================================================================

--- Storage key of a path in the shared favorites file.
--- Thin alias so this file reads naturally; the rule lives in krs.projects.favorites.
--- @param p string|nil Path.
--- @return string key
local function favorite_key(p)
	return favorites.key(p)
end

--- Loads the favorites map.
--- @return table<string,boolean>
local function load_favorites()
	return favorites.load()
end

--- Adds a directory to project.nvim's recent project list, if it is not there.
--- @param dir string Directory path.
local function remember_recent_project(dir)
	local ok, history = pcall(require, "project_nvim.utils.history")
	if not ok or not history.recent_projects then
		return
	end

	for _, p in ipairs(history.recent_projects) do
		if favorite_key(p) == favorite_key(dir) then
			return
		end
	end
	table.insert(history.recent_projects, dir)
	pcall(history.write_projects_to_history)
end

-- ============================================================================
-- DIRECTORY LISTING -- shared by both pickers
-- ============================================================================

--- Cross-platform Desktop directory, falling back to the home directory.
--- @return string dir
function M.get_desktop_path()
	local home = vim.fn.expand("~")
	for _, candidate in ipairs(M.settings.desktop_dirs) do
		local dir = path.join(home, candidate)
		if path.is_dir(dir) then
			return dir
		end
	end
	return home
end

--- Normalizes a directory argument into an existing absolute directory.
--- @param dir string Requested directory.
--- @param fallback string Directory used when `dir` does not exist.
--- @return string dir
local function resolve_dir(dir, fallback)
	local resolved = (vim.fn.fnamemodify(dir, ":p"):gsub("[/\\]$", ""))
	if not path.is_dir(resolved) then
		return fallback
	end
	return resolved
end

--- Lists a directory as picker entries, newest sort rules applied:
--- parent first, then favorites, then directories, then files, each alphabetical.
---
--- @param dir string Directory to list.
--- @param starred table<string,boolean>|nil Favorites map; omit to skip stars.
--- @return table[] entries `{ name, path, key, is_dir, is_parent, is_favorite, display }`
local function list_directory(dir, starred)
	local icons = M.settings.icons
	local entries = {}

	local parent = vim.fn.fnamemodify(dir, ":h")
	if parent ~= "" and not path.equals(parent, dir) then
		table.insert(entries, {
			name = "../",
			path = parent,
			key = favorite_key(parent),
			is_dir = true,
			is_parent = true,
			is_favorite = false,
			display = icons.dir .. "../",
		})
	end

	local handle = vim.uv.fs_scandir(dir)
	while handle do
		local name, entry_type = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end

		local full_path = path.join(dir, name)
		local key = favorite_key(full_path)
		local is_dir = entry_type == "directory"
		local is_favorite = starred ~= nil and starred[key] == true

		table.insert(entries, {
			name = name,
			path = full_path,
			key = key,
			is_dir = is_dir,
			is_favorite = is_favorite,
			display = (is_favorite and icons.favorite or "") .. (is_dir and icons.dir or icons.file) .. name,
		})
	end

	table.sort(entries, function(a, b)
		if a.is_parent ~= b.is_parent then
			return a.is_parent == true
		end
		if a.is_favorite ~= b.is_favorite then
			return a.is_favorite == true
		end
		if a.is_dir ~= b.is_dir then
			return a.is_dir == true
		end
		return a.name:lower() < b.name:lower()
	end)

	return entries
end

--- Sort key keeping the parent entry, then favorites, then folders on top even
--- while the user filters.
--- @param entry table Listing entry.
--- @return string ordinal
local function entry_ordinal(entry)
	return (entry.is_parent and "00_" or "01_")
		.. (entry.is_favorite and "0_" or "1_")
		.. (entry.is_dir and "0_" or "1_")
		.. entry.name
end

--- Builds the picker options both pickers share.
--- @param opts table `{ prompt_title, results_title, entries, attach_mappings }`
--- @return table picker_opts
local function picker_options(opts)
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values

	return {
		prompt_title = opts.prompt_title,
		results_title = opts.results_title,
		finder = finders.new_table({
			results = opts.entries,
			entry_maker = function(entry)
				return { value = entry, display = entry.display, ordinal = entry_ordinal(entry) }
			end,
		}),
		sorter = conf.generic_sorter({}),
		layout_strategy = "horizontal",
		layout_config = M.settings.layout,
		attach_mappings = opts.attach_mappings,
	}
end

-- ============================================================================
-- EXPLORER
-- ============================================================================

--- Directory the explorer opens in when the caller does not name one.
--- @return string dir
local function default_start_dir()
	if vim.bo.filetype == "alpha" then
		return M.get_desktop_path()
	end

	local cwd = vim.fn.getcwd()
	if cwd == "" or not path.is_dir(cwd) then
		return M.get_desktop_path()
	end
	if not path.equals(cwd, vim.fn.expand("~")) then
		return cwd
	end

	-- Sitting in the bare home directory: only stay if a real file is open.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local ft = vim.bo[buf].filetype
		local named = vim.api.nvim_buf_get_name(buf) ~= ""
		if vim.fn.buflisted(buf) == 1 and named and ft ~= "alpha" and ft ~= "neo-tree" then
			return cwd
		end
	end
	return M.get_desktop_path()
end

--- Makes a directory the active project: clears buffers, changes the working
--- directory, records it as recent, and reopens neo-tree there.
--- @param target string Directory to adopt.
local function set_project_root(target)
	pcall(vim.cmd, "Neotree close")
	pcall(vim.cmd, "only")

	vim.cmd("enew")
	local new_buf = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= new_buf and vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end

	pcall(vim.api.nvim_set_current_dir, target)

	local history_ok, history = pcall(require, "project_nvim.utils.history")
	if history_ok and history.recent_projects then
		table.insert(history.recent_projects, target)
		pcall(history.write_projects_to_history)
	end
	pcall(function()
		require("plugins.krs.wsl").add_recent_project(target)
	end)

	pcall(vim.cmd, "Neotree show dir=" .. vim.fn.fnameescape(target))
	vim.notify("📁 Project root changed to:\n" .. target, vim.log.levels.INFO, { title = "Active Project" })
end

--- Opens the file explorer or folder picker.
--- @param opts table|nil `{ path = string, cwd = string, on_select = function, prompt_title = string, results_title = string }` Directory to open / options.
--- @param on_select_cb function|nil Callback when folder is selected.
function M.open_desktop_explorer(opts, on_select_cb)
	opts = opts or {}
	local on_select = on_select_cb or opts.on_select

	local ok_pickers, pickers = pcall(require, "telescope.pickers")
	local ok_actions, actions = pcall(require, "telescope.actions")
	local ok_state, action_state = pcall(require, "telescope.actions.state")

	local requested = opts.path or opts.cwd
	local fallback = (on_select or requested) and vim.fn.getcwd() or default_start_dir()
	local curr_dir = resolve_dir(requested or fallback, vim.fn.getcwd())

	if not (ok_pickers and ok_actions and ok_state) then
		if on_select then
			on_select(curr_dir)
		end
		return
	end

	local entries = list_directory(curr_dir, load_favorites())

	local prompt_title = opts.prompt_title
	if not prompt_title then
		if on_select then
			prompt_title = " 🔍 Sneak Peek: Select Folder (Root: " .. vim.fn.fnamemodify(curr_dir, ":t") .. ") "
		else
			prompt_title = " 📁 Explorer: " .. curr_dir .. " "
		end
	end

	local results_title = opts.results_title
	if not results_title then
		if on_select then
			results_title = " Folders / Files | Press [o/O/Ctrl+O] to select folder | Press [?] for help "
		else
			results_title = " Files / Folders | [f / Ctrl+F]=Favorite | Press [?] for help "
		end
	end

	pickers
		.new(picker_options({
			prompt_title = prompt_title,
			results_title = results_title,
			entries = entries,
			attach_mappings = function(prompt_bufnr, map)
				--- Selection under the cursor, or nil. `skip_parent` filters out `../`
				--- for actions that must not touch the parent directory.
				local function selected(skip_parent)
					local selection = action_state.get_selected_entry()
					local value = selection and selection.value or nil
					if value and skip_parent and value.is_parent then
						return nil
					end
					return value
				end

				--- Closes the picker, then reopens the explorer on `dir`.
				local function reopen(dir)
					vim.schedule(function()
						M.open_desktop_explorer({ path = dir or curr_dir, on_select = on_select }, on_select)
					end)
				end

				--- Binds one action to several key/mode pairs.
				local function map_all(bindings, fn)
					for _, binding in ipairs(bindings) do
						map(binding[1], binding[2], fn)
					end
				end

				actions.select_default:replace(function()
					local item = selected()
					if not item then
						return
					end
					actions.close(prompt_bufnr)
					if item.is_dir then
						reopen(item.path)
					else
						if on_select then
							on_select(curr_dir)
						else
							vim.cmd("edit " .. vim.fn.fnameescape(item.path))
						end
					end
				end)

				map_all({ { "i", "<C-o>" }, { "n", "<C-o>" }, { "n", "o" }, { "n", "O" } }, function()
					local item = selected()
					local target = (item and item.is_dir and not item.is_parent) and item.path or curr_dir
					actions.close(prompt_bufnr)
					if on_select then
						on_select(target)
					else
						set_project_root(target)
					end
				end)

				map_all({ { "n", "a" }, { "i", "<C-a>" } }, function()
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Create new (add '/' at end for folder): " }, function(name)
							if not name or name == "" then
								return
							end
							local full_path = path.join(curr_dir, name)
							if name:sub(-1) == "/" or name:sub(-1) == "\\" then
								vim.fn.mkdir(full_path, "p")
								vim.notify("📁 Folder created: " .. name, vim.log.levels.INFO)
							else
								local file = io.open(full_path, "w")
								if file then
									file:close()
									vim.notify("📄 File created: " .. name, vim.log.levels.INFO)
								end
							end
							M.open_desktop_explorer({ path = curr_dir })
						end)
					end)
				end)

				map("n", "r", function()
					local item = selected(true)
					if not item then
						return
					end
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Rename to: ", default = item.name }, function(new_name)
							local target_path = path.join(curr_dir, new_name)
							local ok_ren, err_ren = os.rename(item.path, target_path)
							if ok_ren then
								require("krs.core.buffer_rename").update_buffers_path(item.path, target_path)
								vim.notify("✏️ Renamed to: " .. new_name, vim.log.levels.INFO)
							else
								vim.notify("Error renaming: " .. tostring(err_ren), vim.log.levels.ERROR)
							end
							M.open_desktop_explorer({ path = curr_dir })
						end)
					end)
				end)

				map("n", "d", function()
					local item = selected(true)
					if not item then
						return
					end
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Delete '" .. item.name .. "'? (y/n): " }, function(confirm)
							if confirm and confirm:lower() == "y" then
								vim.fn.delete(item.path, "rf")
								vim.notify("🗑️ Deleted: " .. item.name, vim.log.levels.INFO)
							end
							M.open_desktop_explorer({ path = curr_dir })
						end)
					end)
				end)

				map("n", "c", function()
					local item = selected(true)
					if not item then
						return
					end
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Copy '" .. item.name .. "' to: ", default = item.name }, function(new_name)
							if not new_name or new_name == "" or new_name == item.name then
								return
							end
							local dest = path.join(curr_dir, new_name)

							if item.is_dir then
								-- No portable recursive copy in Lua; shell out per platform.
								if vim.fn.has("win32") == 1 then
									vim.fn.system({
										"xcopy",
										item.path:gsub("/", "\\"),
										dest:gsub("/", "\\"),
										"/E",
										"/I",
										"/H",
										"/Y",
									})
								else
									vim.fn.system({ "cp", "-r", item.path, dest })
								end
								vim.notify("📋 Copied folder to: " .. new_name, vim.log.levels.INFO)
							else
								local ok, err = vim.uv.fs_copyfile(item.path, dest)
								vim.notify(
									ok and ("📋 Copied file to: " .. new_name) or ("Error copying file: " .. tostring(err)),
									ok and vim.log.levels.INFO or vim.log.levels.ERROR
								)
							end
							M.open_desktop_explorer({ path = curr_dir })
						end)
					end)
				end)

				map("n", "m", function()
					local item = selected(true)
					if not item then
						return
					end
					actions.close(prompt_bufnr)
					vim.schedule(function()
						M.open_move_picker({ source_path = item.path, root_dir = curr_dir })
					end)
				end)

				map_all({ { "i", "<C-f>" }, { "n", "<C-f>" }, { "n", "f" } }, function()
					-- With `../` selected (or nothing), favorite the directory itself.
					local item = selected(true)
					local target_path = item and item.path or curr_dir
					local target_name = item and item.name or vim.fn.fnamemodify(curr_dir, ":t")
					if target_path == "" then
						return
					end

					if favorites.toggle(target_path) then
						if path.is_dir(target_path) then
							remember_recent_project(target_path)
						end
						vim.notify("⭐ Saved as favorite: " .. target_name, vim.log.levels.INFO, { title = "Explorer Favorites" })
					else
						vim.notify("Removed from favorites: " .. target_name, vim.log.levels.INFO, { title = "Explorer Favorites" })
					end

					actions.close(prompt_bufnr)
					reopen()
				end)

				local function go_parent()
					local parent = vim.fn.fnamemodify(curr_dir, ":h")
					if parent and parent ~= curr_dir then
						actions.close(prompt_bufnr)
						reopen(parent)
					end
				end
				map_all({ { "n", "h" }, { "n", "<BS>" }, { "n", "<Left>" }, { "n", "u" }, { "i", "<C-h>" } }, go_parent)

				-- In insert mode <BS> only navigates when the filter is empty; otherwise
				-- it has to keep deleting characters.
				map("i", "<BS>", function()
					if action_state.get_current_line() == "" then
						go_parent()
					else
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<BS>", true, false, true), "n", false)
					end
				end)

				map_all({ { "n", "l" }, { "n", "<Right>" } }, function()
					local item = selected()
					if item and item.is_dir then
						actions.close(prompt_bufnr)
						reopen(item.path)
					end
				end)

				map_all({ { "n", "?" }, { "n", "<F1>" } }, function()
					require("plugins.krs.context_help").show_help()
				end)

				map("n", "q", function()
					actions.close(prompt_bufnr)
				end)

				return true
			end,
		}))
		:find()
end

-- ============================================================================
-- MOVE TARGET PICKER
-- ============================================================================

--- Navigates folders to pick a destination for `source_path`, confirmed with `O`.
--- @param opts table `{ source_path = string, root_dir = string?, path = string? }`
function M.open_move_picker(opts)
	opts = opts or {}

	local source_path = opts.source_path
	if not source_path or source_path == "" then
		vim.notify("No file selected to move", vim.log.levels.WARN, { title = "Move File" })
		return
	end

	local pickers = require("telescope.pickers")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local source_name = vim.fn.fnamemodify(source_path, ":t")
	local root_dir = opts.root_dir or vim.fn.getcwd()
	local curr_dir = resolve_dir(opts.path or root_dir, root_dir)

	pickers
		.new(picker_options({
			prompt_title = " 🚚 Move '" .. source_name .. "' ➜ Navigate & press [O] or [m] to confirm target folder ",
			results_title = " Folders / Files | [O] Move into selected | [m] Move Here | [l] Open Folder | [h] Parent ",
			entries = list_directory(curr_dir, nil),
			attach_mappings = function(prompt_bufnr, map)
				--- Reopens this picker somewhere else, keeping the source file.
				local function reopen(dir)
					vim.schedule(function()
						M.open_move_picker({ source_path = source_path, root_dir = root_dir, path = dir })
					end)
				end

				local function map_all(bindings, fn)
					for _, binding in ipairs(bindings) do
						map(binding[1], binding[2], fn)
					end
				end

				local function selected_dir()
					local selection = action_state.get_selected_entry()
					local value = selection and selection.value or nil
					return (value and value.is_dir) and value.path or nil
				end

				local function perform_move(target_dir)
					actions.close(prompt_bufnr)

					local dest_path = path.join(target_dir, source_name)
					if source_path == dest_path then
						vim.notify("File is already in this directory", vim.log.levels.WARN, { title = "Move File" })
						return
					end
					if path.is_file(dest_path) or path.is_dir(dest_path) then
						vim.notify("Target file already exists: " .. dest_path, vim.log.levels.ERROR, { title = "Move File" })
						return
					end

					local ok, err = os.rename(source_path, dest_path)
					if ok then
						require("krs.core.buffer_rename").update_buffers_path(source_path, dest_path)
						vim.notify(
							"🚚 Moved '" .. source_name .. "' to:\n" .. target_dir,
							vim.log.levels.INFO,
							{ title = "Move File" }
						)
						pcall(function()
							require("neo-tree.sources.manager").refresh("filesystem")
						end)
					else
						vim.notify("Error moving file: " .. tostring(err), vim.log.levels.ERROR, { title = "Move File" })
					end
				end

				actions.select_default:replace(function()
					local dir = selected_dir()
					if dir then
						actions.close(prompt_bufnr)
						reopen(dir)
					end
				end)

				map_all({ { "n", "O" }, { "n", "o" }, { "i", "<C-o>" } }, function()
					local target_dir = selected_dir() or curr_dir
					perform_move(target_dir)
				end)

				map_all({ { "n", "m" }, { "n", "M" }, { "i", "<C-m>" } }, function()
					perform_move(curr_dir)
				end)

				map_all({ { "n", "a" }, { "i", "<C-a>" } }, function()
					actions.close(prompt_bufnr)
					vim.schedule(function()
						vim.ui.input({ prompt = "Create folder to move into (add '/' at end): " }, function(name)
							if name and name ~= "" then
								vim.fn.mkdir(path.join(curr_dir, name), "p")
							end
							M.open_move_picker({ source_path = source_path, root_dir = root_dir, path = curr_dir })
						end)
					end)
				end)

				map_all({ { "n", "h" }, { "n", "<BS>" }, { "n", "<Left>" }, { "n", "u" } }, function()
					local parent = vim.fn.fnamemodify(curr_dir, ":h")
					if parent and parent ~= curr_dir then
						actions.close(prompt_bufnr)
						reopen(parent)
					end
				end)

				map_all({ { "n", "l" }, { "n", "<Right>" } }, function()
					local dir = selected_dir()
					if dir then
						actions.close(prompt_bufnr)
						reopen(dir)
					end
				end)

				map("n", "q", function()
					actions.close(prompt_bufnr)
				end)

				return true
			end,
		}))
		:find()
end

-- ============================================================================
-- WSL EXPLORER
-- ============================================================================
-- FOLDER PICKER
-- ============================================================================

--- Opens a folder picker with the exact same UI, motions, and keymaps as the file explorer,
--- starting at current CWD (or `opts.cwd` / `opts.path`).
--- @param opts table|nil `{ path = string, cwd = string, prompt_title = string }`
--- @param on_select function|nil `function(dir)` Callback when directory is selected.
function M.open_folder_picker(opts, on_select)
	opts = opts or {}
	local start_dir = opts.cwd or opts.path or vim.fn.getcwd()
	if not start_dir or start_dir == "" or path.is_dir(start_dir) == false then
		start_dir = vim.fn.getcwd()
	end
	opts.path = start_dir
	opts.on_select = on_select or opts.on_select
	return M.open_desktop_explorer(opts, opts.on_select)
end

-- ============================================================================
-- WSL EXPLORER
-- ============================================================================
--- when several are installed.
function M.open_wsl_explorer()
	local wsl = require("plugins.krs.wsl")

	if not wsl.available() then
		vim.notify("WSL is not available on this system", vim.log.levels.WARN, { title = "WSL Explorer" })
		return
	end

	local distros = wsl.list_distros()
	if #distros == 0 then
		vim.notify("No WSL distributions found", vim.log.levels.WARN, { title = "WSL Explorer" })
		return
	end

	local function open_distro(distro)
		local root = wsl.distro_root(distro)
		if not path.is_dir(root) then
			vim.notify("Could not reach WSL distro filesystem: " .. root, vim.log.levels.ERROR, { title = "WSL Explorer" })
			return
		end
		M.open_desktop_explorer({ path = root })
	end

	if #distros == 1 then
		open_distro(distros[1])
	else
		vim.ui.select(distros, { prompt = "Select WSL distro:" }, function(choice)
			if choice then
				open_distro(choice)
			end
		end)
	end
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers `:TelescopeFileBrowserDesktop`, `:TelescopeFileBrowserWSL` and keys.
function M.setup()
	local commands = {
		TelescopeFileBrowserDesktop = { M.open_desktop_explorer, "Open Floating File Explorer (Desktop)" },
		TelescopeFileBrowserWSL = { M.open_wsl_explorer, "Open Floating File Explorer (WSL)" },
	}
	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, function()
				spec[1]()
			end, { desc = spec[2] })
		end
	end

	for _, key in ipairs(M.settings.keys.open) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, function()
			if vim.fn.mode() == "t" then
				vim.cmd("stopinsert")
			end
			M.open_desktop_explorer()
		end, { noremap = true, silent = true, desc = "Open Floating File Explorer (Desktop)" })
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.FileExplorer = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_file_explorer",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "TelescopeFileBrowserDesktop", "TelescopeFileBrowserWSL" },
	keys = {
		{ "<C-/>", mode = { "n", "i", "v" }, desc = "Desktop File Explorer" },
		{ "<C-_>", mode = { "n", "i", "v" }, desc = "Desktop File Explorer" },
	},
	dependencies = { "nvim-telescope/telescope.nvim" },
	config = M.setup,
}, { __index = M })
