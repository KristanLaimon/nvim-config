-- ============================================================================
-- PLUGIN: neo-tree -- the file sidebar (<C-S-Space> / <leader>e).
-- ============================================================================
-- WHAT THIS FILE ADDS
--   1. A REMEMBERED width that survives restarts, and stays put when other
--      windows open and close (see "width pinning" below).
--   2. Create/rename/move through the shared KRS input modal, so the sidebar
--      matches the rest of the editor instead of neo-tree's own prompts.
--   3. `<C-S-CR>` opens the selected entry with the OS default application.
--   4. Search keys that reuse the project's own file finders.
--
-- WIDTH PINNING -- why there is so much code for one number
--   neo-tree does not set `winfixwidth`, so any `wincmd =` (dap-ui opening its
--   panels, a plain split) steals the sidebar's width. `winfixwidth` alone is not
--   enough either: it only blocks SHRINKING, so when a neighbour closes, nvim
--   hands the freed columns to the sidebar and it swallows the screen. Hence the
--   width is re-asserted on WinClosed as well.
--
-- SIDEBAR KEYS
--   a / <C-n> new file    A / <C-S-n> new folder    r rename    m move
--   <C-/> find files (gitignore)   <C-S-/> find all files
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local env_ok, env_mod = pcall(require, "krs.core.environment")
local env = env_ok and env_mod.detect() or {}
local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Where the sidebar width is remembered.
	width_file = vim.fn.stdpath("state") .. "/neotree_width",

	--- Width used before anything is saved, and the range that may be saved.
	default_width = 30,
	min_width = 18,
	max_width = 60,

	--- The sidebar may never take more than this fraction of the editor.
	max_width_ratio = 0.45,

	--- Sidebar mappings, mapped to the commands defined further down.
	mappings = {
		["d"] = "delete",
		["D"] = "delete_visual",
		["r"] = "rename_with_modal",
		["R"] = "refresh_neotree",
		["m"] = "move_with_picker",
		["a"] = "add_file_with_modal",
		["A"] = "add_folder_with_modal",
		["<C-n>"] = "add_file_with_modal",
		["<C-f>"] = "open_file_browser_desktop",
		["<C-F>"] = "open_file_browser_desktop",
		["<C-S-n>"] = "add_folder_with_modal",
		["<C-S-N>"] = "add_folder_with_modal",
		["<C-/>"] = "search_respect_gitignore",
		["<C-_>"] = "search_respect_gitignore",
		["<C-S-/>"] = "search_all_files",
		["<C-?>"] = "search_all_files",
		["<C-S-CR>"] = "open_with_system_app",
		["<C-S-Enter>"] = "open_with_system_app",
		["H"] = "toggle_custom_hidden",
		["gh"] = "toggle_custom_hidden",
	},

	--- Keys that toggle the sidebar.
	toggle_keys = { "<C-S-Space>", "<C-e>", "<C-E>", "<leader>e", "<leader>fe" },
}

-- ============================================================================
-- WIDTH PERSISTENCE
-- ============================================================================

local saved_width_cached = nil
local function get_saved_width()
	if not saved_width_cached then
		local raw = store.read_file(settings.width_file)
		local width = tonumber(raw or "") or settings.default_width
		if width < settings.min_width or width > settings.max_width then
			width = settings.default_width
		end
		saved_width_cached = width
	end
	return saved_width_cached
end

--- Remembers a new width, when it is in range and actually changed.
--- @param width integer
local function save_width(width)
	local max_allowed = math.min(settings.max_width, math.floor((vim.o.columns or 80) * settings.max_width_ratio))
	if type(width) ~= "number" or width < settings.min_width or width > max_allowed or width == get_saved_width() then
		return
	end

	saved_width_cached = width
	store.write_file(settings.width_file, tostring(width))
end

--- Forces every neo-tree window back to the remembered width.
local function pin_width()
	local target_w = get_saved_width()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
		if buf and vim.bo[buf].filetype == "neo-tree" then
			vim.wo[win].winfixwidth = true
			if vim.api.nvim_win_get_width(win) ~= target_w then
				pcall(vim.api.nvim_win_set_width, win, target_w)
			end
		end
	end
end

--- Toggles Neo-tree from any mode (including Terminal mode), ensuring
--- Neo-tree remains full-height on the left of dock/terminal windows.
local function toggle_neotree()
	if vim.api.nvim_get_mode().mode == "t" then
		pcall(vim.cmd, "stopinsert")
	end
	vim.cmd("silent! Neotree toggle")
	vim.schedule(function()
		pcall(function()
			require("krs.core.dock").enforce_neotree_layout()
		end)
	end)
end

_G.Neotree_Toggle = toggle_neotree

local fix_group = vim.api.nvim_create_augroup("NeoTreeFixWidth", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	pattern = "neo-tree",
	group = fix_group,
	callback = function()
		pin_width()
		vim.schedule(function()
			pcall(function()
				require("krs.core.dock").enforce_neotree_layout()
			end)
		end)
	end,
})

vim.api.nvim_create_autocmd("WinClosed", {
	group = fix_group,
	callback = function()
		vim.schedule(pin_width)
	end,
})

-- Open Neo-tree automatically when Neovim opens a directory target
vim.api.nvim_create_autocmd("VimEnter", {
	group = fix_group,
	callback = function(data)
		local file = data.file
		if file ~= "" and vim.fn.isdirectory(file) == 1 then
			vim.cmd("silent! Neotree show dir=" .. vim.fn.fnameescape(file))
		end
	end,
})

-- `equalalways` should already balance the other splits, but neo-tree's own
-- resize event does not always trigger it.
vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
	group = vim.api.nvim_create_augroup("NeoTreeEqualize", { clear = true }),
	callback = function()
		vim.schedule(function()
			pin_width()
			pcall(function()
				require("krs.core.dock").enforce_neotree_layout()
			end)
		end)
	end,
})

vim.api.nvim_create_autocmd("WinResized", {
	group = vim.api.nvim_create_augroup("NeoTreeWidthSaver", { clear = true }),
	callback = function()
		local wins = vim.api.nvim_tabpage_list_wins(0)
		-- A single window means the sidebar is full-screen; that is not a width
		-- worth remembering.
		if #wins <= 1 then
			return
		end

		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "neo-tree" then
					save_width(vim.api.nvim_win_get_width(win))
				end
			end
		end
	end,
})

-- ============================================================================
-- SIDEBAR COMMAND HELPERS
-- ============================================================================

--- Redraws the tree after a filesystem change.
--- @param full_reset boolean|nil Perform a complete state reset (heavy scan).
local function refresh_tree(full_reset)
	pcall(function()
		require("neo-tree.sources.manager").refresh("filesystem")
	end)
	if full_reset then
		pcall(function()
			require("neo-tree.sources.filesystem").reset()
		end)
	end
end

local function refresh_neotree_with_notify()
	refresh_tree(true)
	vim.notify("🔄 Rescanned & refreshed Neo-tree files!", vim.log.levels.INFO, { title = "Neo-tree" })
end

_G.Neotree_Refresh = refresh_neotree_with_notify

--- Deletes a file or directory on disk, handling Windows reserved names like NUL.
--- @param path string Absolute path to file or directory.
--- @return boolean ok, string|nil err
local function delete_path(path)
	if not path or path == "" then
		return false, "Invalid path"
	end

	local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 or os.getenv("OS") == "Windows_NT"
	local win_path = is_win and ("\\\\?\\" .. path:gsub("/", "\\")) or path

	-- Try stdlib os.remove first (fast for single files and Windows reserved device names like NUL)
	local ok, err = os.remove(is_win and win_path or path)
	if ok then
		return true, nil
	end

	-- Try vim.fn.delete (handles directories and normal files)
	local res = vim.fn.delete(is_win and win_path or path, "rf")
	if res == 0 then
		return true, nil
	end

	if is_win then
		ok, err = os.remove(path)
		if ok then
			return true, nil
		end

		res = vim.fn.delete(path, "rf")
		if res == 0 then
			return true, nil
		end

		-- Final fallback for Windows reserved files or locked files via powershell
		pcall(function()
			vim.fn.system({
				"powershell",
				"-NoProfile",
				"-NonInteractive",
				"-Command",
				"Remove-Item -LiteralPath '" .. win_path .. "' -Force -Recurse",
			})
		end)
		local uv = vim.uv or vim.loop
		if uv.fs_stat(path) == nil then
			return true, nil
		end
	end

	return false, tostring(err or "Failed to delete path")
end

--- Directory a new entry should be created in: the selected directory, or the
--- parent of the selected file. Falls back to active buffer dir or CWD.
--- @param node table|nil neo-tree node.
--- @return string dir
local function target_dir(node)
	if node and node.path then
		return node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h")
	end

	local ok, manager = pcall(require, "neo-tree.sources.manager")
	if ok and manager then
		local state = manager.get_state("filesystem")
		if state and state.tree then
			local curr_node = state.tree:get_node()
			if curr_node and curr_node.path then
				return curr_node.type == "directory" and curr_node.path or vim.fn.fnamemodify(curr_node.path, ":h")
			end
		end
	end

	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path ~= "" and vim.bo.filetype ~= "neo-tree" then
		local parent = vim.fn.fnamemodify(buf_path, ":h")
		if vim.fn.isdirectory(parent) == 1 then
			return parent
		end
	end

	return vim.fn.getcwd()
end

--- Prompts for a name and creates a file or a folder in `parent_dir`.
--- @param parent_dir string Directory to create in.
--- @param kind "file"|"folder"
local function create_entry(parent_dir, kind)
	require("plugins.krs.ui.input_modal").open({
		label = kind == "folder" and "New Folder" or "New File",
		default_value = "",
		relative = "editor",
		callback = function(ok, name)
			if not ok or not name or name == "" then
				return
			end

			-- A trailing slash is how you ask for a folder elsewhere in this
			-- config; here the key already decided, so strip it.
			local clean = name:gsub("[/\\]+$", "")
			if clean == "" then
				return
			end

			local target = parent_dir .. "/" .. clean

			if kind == "folder" then
				vim.fn.mkdir(target, "p")
				vim.notify("Created folder: " .. clean, vim.log.levels.INFO, { title = "Neo-tree" })
			else
				-- Support "sub/dir/file.lua" by creating the missing directories.
				local target_parent = vim.fn.fnamemodify(target, ":h")
				if vim.fn.isdirectory(target_parent) == 0 then
					vim.fn.mkdir(target_parent, "p")
				end

				local file = io.open(target, "w")
				if file then
					file:close()
					vim.cmd("edit " .. vim.fn.fnameescape(target))
					vim.notify("Created file: " .. clean, vim.log.levels.INFO, { title = "Neo-tree" })
				else
					vim.notify("Failed to create file: " .. clean, vim.log.levels.ERROR, { title = "Neo-tree" })
				end
			end

			vim.schedule(function()
				refresh_tree(false)
			end)
		end,
	})
end

local function add_file_prompt(node)
	create_entry(target_dir(node), "file")
end

local function add_folder_prompt(node)
	create_entry(target_dir(node), "folder")
end

_G.Neotree_Create_File = add_file_prompt
_G.Neotree_Create_Folder = add_folder_prompt

--- Wraps a command so it only runs with a usable node selected.
--- @param fn fun(node: table, state: table)
--- @param needs_path boolean|nil Require the node to have a path.
--- @return fun(state: table)
local function with_node(fn, needs_path)
	return function(state)
		local node = state.tree:get_node()
		if not node or (needs_path and not node.path) then
			return
		end
		fn(node, state)
	end
end

-- ============================================================================
-- PLUGIN SPECS
-- ============================================================================

return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		cmd = {
			"Neotree",
			"NeotreeCreateFile",
			"NeotreeAddFile",
			"NeotreeCreateFolder",
			"NeotreeAddFolder",
			"NeotreeRefresh",
			"NeotreeRescan",
		},
		keys = (function()
			local k = {}
			for _, key in ipairs(settings.toggle_keys) do
				table.insert(k, { key, toggle_neotree, mode = { "n", "i", "t" }, desc = "Toggle Explorer" })
			end
			return k
		end)(),
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-tree/nvim-web-devicons",
			"antosha417/nvim-lsp-file-operations",
			"folke/snacks.nvim",
		},
		config = function()
			for _, key in ipairs(settings.toggle_keys) do
				vim.keymap.set({ "n", "i", "t" }, key, toggle_neotree, {
					noremap = true,
					silent = true,
					desc = "Toggle Explorer",
				})
			end

			local neotree_hidden = require("plugins.krs.editor.neotree_hidden")
			neotree_hidden.setup()

			local user_cmds = {
				NeotreeCreateFile = {
					function()
						add_file_prompt()
					end,
					"Create new file in Neo-tree target directory",
				},
				NeotreeAddFile = {
					function()
						add_file_prompt()
					end,
					"Create new file in Neo-tree target directory",
				},
				NeotreeCreateFolder = {
					function()
						add_folder_prompt()
					end,
					"Create new folder in Neo-tree target directory",
				},
				NeotreeAddFolder = {
					function()
						add_folder_prompt()
					end,
					"Create new folder in Neo-tree target directory",
				},
				NeotreeRefresh = {
					function()
						refresh_neotree_with_notify()
					end,
					"Rescan and refresh Neo-tree files",
				},
				NeotreeRescan = {
					function()
						refresh_neotree_with_notify()
					end,
					"Rescan and refresh Neo-tree files",
				},
				NeotreeToggleCustomHiddenVisibility = {
					function()
						neotree_hidden.toggle_visibility()
					end,
					"Toggle visibility of custom hidden items in Neo-tree",
				},
				NeotreeClearCustomHidden = {
					function()
						neotree_hidden.clear_all()
					end,
					"Clear all marked custom hidden items in Neo-tree",
				},
			}
			for name, spec in pairs(user_cmds) do
				if vim.fn.exists(":" .. name) == 0 then
					vim.api.nvim_create_user_command(name, spec[1], { desc = spec[2] })
				end
			end

			require("neo-tree").setup({
				-- Was true: while dap-ui tears its panels down, neo-tree can briefly
				-- be the last window, close itself, and take the whole session with
				-- it. Smart quit (<C-q>) still handles quitting explicitly.
				close_if_last_window = false,
				window = {
					width = get_saved_width(),
					mappings = settings.mappings,
				},
				commands = {
					refresh_neotree = function()
						refresh_neotree_with_notify()
					end,
					open_file_browser_desktop = function()
						vim.cmd("TelescopeFileBrowserDesktop")
					end,
					toggle_custom_hidden = with_node(function(node)
						neotree_hidden.toggle_path(node.path)
					end, true),
					open_with_system_app = with_node(function(node)
						require("plugins.krs.ui.image_viewer").open_with_system_app(node.path)
					end, true),

					rename_with_modal = with_node(function(node)
						local old_path, old_name = node.path, node.name

						require("plugins.krs.ui.input_modal").open({
							label = "Rename (" .. old_name .. ")",
							default_value = old_name,
							relative = "editor",
							callback = function(ok, new_name)
								if not ok or not new_name or new_name == "" or new_name == old_name then
									return
								end

								local new_path = vim.fn.fnamemodify(old_path, ":h") .. "/" .. new_name
								local renamed, err = os.rename(old_path, new_path)

								if renamed then
									require("krs.core.buffer_rename").update_buffers_path(old_path, new_path)
									vim.notify("Renamed: " .. old_name .. " ➜ " .. new_name, vim.log.levels.INFO, {
										title = "Neo-tree",
									})
									refresh_tree()
								else
									vim.notify("Error renaming: " .. tostring(err), vim.log.levels.ERROR, {
										title = "Neo-tree",
									})
								end
							end,
						})
					end, true),

					move_with_picker = with_node(function(node)
						require("plugins.krs.tools.file_explorer").open_move_picker({
							source_path = node.path,
							root_dir = vim.fn.getcwd(),
						})
					end, true),

					add_file_with_modal = function(state)
						local node = state and state.tree and state.tree:get_node()
						add_file_prompt(node)
					end,

					add_folder_with_modal = function(state)
						local node = state and state.tree and state.tree:get_node()
						add_folder_prompt(node)
					end,

					search_respect_gitignore = function()
						if _G.FindFilesGitignore then
							_G.FindFilesGitignore()
						else
							require("telescope.builtin").find_files({ no_ignore = false })
						end
					end,

					search_all_files = function()
						if _G.FindFilesNoIgnore then
							_G.FindFilesNoIgnore()
						else
							require("telescope.builtin").find_files({ no_ignore = true, hidden = true })
						end
					end,

					delete = with_node(function(node, state)
						local inputs = require("neo-tree.ui.inputs")
						local path = node.path
						local name = node.name

						inputs.confirm("Are you sure you want to delete '" .. name .. "'?", function(confirmed)
							if not confirmed then
								return
							end

							local ok, err = delete_path(path)
							if ok then
								vim.notify("Deleted: " .. name, vim.log.levels.INFO, { title = "Neo-tree" })
								refresh_tree()
							else
								vim.notify(
									"Failed to delete '" .. name .. "': " .. tostring(err),
									vim.log.levels.ERROR,
									{ title = "Neo-tree" }
								)
							end
						end)
					end, true),

					delete_visual = function(state, selected_nodes)
						local inputs = require("neo-tree.ui.inputs")
						local nodes = selected_nodes or {}
						if #nodes == 0 then
							local node = state.tree:get_node()
							if node then
								table.insert(nodes, node)
							end
						end
						if #nodes == 0 then
							return
						end

						local msg = #nodes == 1 and ("Are you sure you want to delete '" .. nodes[1].name .. "'?")
							or string.format("Are you sure you want to delete %d selected item(s)?", #nodes)

						inputs.confirm(msg, function(confirmed)
							if not confirmed then
								return
							end

							local count = 0
							for _, node in ipairs(nodes) do
								if node.path and delete_path(node.path) then
									count = count + 1
								end
							end

							vim.notify("Deleted " .. count .. " item(s)", vim.log.levels.INFO, { title = "Neo-tree" })
							refresh_tree()
						end)
					end,
				},
				filesystem = {
					bind_to_cwd = true,
					follow_current_file = {
						enabled = true,
						leave_dirs_open = false,
					},
					use_libuv_file_watcher = not is_mobile_or_proot,
					-- Nothing is hidden: this config edits dotfiles and ignored
					-- build output often enough that hiding them costs more.
					filtered_items = {
						visible = true,
						hide_dotfiles = false,
						hide_gitignored = false,
					},
				},
				event_handlers = {
					{
						event = "file_renamed",
						handler = function(args)
							require("krs.core.buffer_rename").update_buffers_path(args.source, args.destination)
						end,
					},
					{
						event = "file_moved",
						handler = function(args)
							require("krs.core.buffer_rename").update_buffers_path(args.source, args.destination)
						end,
					},
					{
						event = "dir_renamed",
						handler = function(args)
							require("krs.core.buffer_rename").update_buffers_path(args.source, args.destination)
						end,
					},
					{
						event = "dir_moved",
						handler = function(args)
							require("krs.core.buffer_rename").update_buffers_path(args.source, args.destination)
						end,
					},
				},
			})
		end,
	},

	-- Keeps LSP-aware file operations (imports follow a rename) working with the
	-- tree's own create/rename/move commands.
	{
		"Crysthamus/nvim-file-operations",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "nvim-neo-tree/neo-tree.nvim" },
		config = function()
			require("nvim-file-operations").setup()
		end,
	},

	-- Used by neo-tree when a file has to be opened "in that window over there".
	{
		"s1n7ax/nvim-window-picker",
		version = "2.*",
		lazy = true,
		config = function()
			require("window-picker").setup({
				filter_rules = {
					include_current_win = false,
					autoselect_one = true,
					bo = {
						filetype = { "neo-tree", "neo-tree-popup", "notify" },
						buftype = { "terminal", "quickfix" },
					},
				},
			})
		end,
	},
}
