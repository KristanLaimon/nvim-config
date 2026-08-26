-- ============================================================================
-- KRS PLUGIN: Workspaces -- named sessions per project.
-- ============================================================================
-- WHAT IT DOES
--   1. Saves the exact window/tab/buffer layout with `mksession!`.
--   2. Keeps every session file in `stdpath("data")/workspaces`, indexed by a
--      single `index.json` holding names, project paths, dates and open buffers.
--   3. Offers a Telescope picker (`<C-S-w>`) to load, delete, rename, overwrite,
--      or filter workspaces, plus Harpoon-style slots 1..9.
--   4. Returns to the dashboard with `<C-S-m>`, optionally saving first.
--
-- PICKER KEYS
--   <CR> load   d delete   r rename   a new   s overwrite   g all/current   1-9 slot
--
-- WHY NEO-TREE AND TERMINALS ARE PURGED AROUND A SESSION
--   `mksession!` serializes them as ordinary buffers, and restoring that produces
--   dead neo-tree windows and detached terminals. They are closed before saving,
--   re-opened after, and never written into the session file.
--
-- INDEX FORMAT -- `<data>/workspaces/index.json`
--   [{ "id": "ws_1712345678_4821", "name": "API work", "cwd": "C:/proj",
--      "cwd_name": "proj", "created_at": 0, "updated_at": 0,
--      "session_file": "<data>/workspaces/ws_....vim",
--      "buffers": ["src/app.ts"], "tab_count": 2, "neotree_open": true }]
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")

local M = {}

--- Currently active loaded workspace record.
M.current_workspace = nil

--- Returns the currently active workspace record, or nil.
--- @return table|nil
function M.get_active_workspace()
	return M.current_workspace
end

--- Sets the active workspace record.
--- @param ws table|nil
function M.set_active_workspace(ws)
	M.current_workspace = ws
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Where session files and the index live.
	storage_dir = vim.fn.stdpath("data") .. "/workspaces",

	--- Index file name inside `storage_dir`.
	index_file = "index.json",

	--- Title on every notification from this module.
	notify_title = "KRS Workspaces",

	--- What `mksession!` records. `terminal` is deliberately absent so workspaces
	--- never restore terminal splits.
	session_options = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions",

	--- Quick-load slots exposed as `<leader>w1..9` and `1..9` inside the picker.
	quick_slots = 9,

	--- Filetypes treated as transient UI: closed before saving, purged on load.
	transient_filetypes = { "TaskRunner", "toggleterm" },

	keys = {
		--- Open the workspace picker.
		select = { "<C-S-w>", "<C-S-W>", "<leader>ws" },
		--- Close everything and return to the dashboard.
		menu = { "<C-S-m>", "<C-S-M>", "<leader>wm" },
		--- Leader mappings: save, select, back to menu.
		leader_save = nil,
		leader_select = nil,
		leader_menu = nil,
		--- Prefix for quick slots, the slot number is appended.
		leader_slot_prefix = nil,
	},
}

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

-- ============================================================================
-- INDEX STORAGE
-- ============================================================================

--- Session storage directory, created on first use.
--- @return string dir
local function storage_dir()
	return path.ensure_dir(M.settings.storage_dir)
end

--- Absolute path of the index file.
--- @return string filepath
local function index_path()
	return path.join(storage_dir(), M.settings.index_file)
end

--- Loads the workspace index.
--- @return table[] index Possibly empty list of workspace records.
local function load_index()
	return store.load(index_path(), {})
end

--- Writes the workspace index back.
--- @param index table[] Workspace records.
--- @return boolean ok
local function save_index(index)
	return (store.save(index_path(), index))
end

--- Finds a workspace by record, id, or (case-insensitive) name.
--- @param index table[] Loaded index.
--- @param identifier table|string Workspace record, id, or name.
--- @return table|nil workspace
--- @return integer|nil position Index in the list, for removal.
local function find_workspace(index, identifier)
	for idx, item in ipairs(index) do
		local matches = (type(identifier) == "table" and item.id == identifier.id)
			or (type(identifier) == "string" and (item.id == identifier or item.name:lower() == identifier:lower()))
		if matches then
			return item, idx
		end
	end
	return nil, nil
end

-- ============================================================================
-- SESSION SNAPSHOTTING
-- ============================================================================

--- "5 mins ago" style stamp used by the picker.
--- @param timestamp integer|nil Unix time.
--- @return string
local function format_relative_time(timestamp)
	if not timestamp then
		return ""
	end

	local diff = os.time() - timestamp
	if diff < 60 then
		return "just now"
	end

	local units = {
		{ limit = 3600, seconds = 60, label = "min" },
		{ limit = 86400, seconds = 3600, label = "hour" },
		{ limit = math.huge, seconds = 86400, label = "day" },
	}
	for _, unit in ipairs(units) do
		if diff < unit.limit then
			local value = math.floor(diff / unit.seconds)
			return string.format("%d %s%s ago", value, unit.label, value > 1 and "s" or "")
		end
	end
	return ""
end

--- Listed file buffers, as paths relative to the working directory.
--- @return string[] paths
local function get_current_buffers()
	local buflist = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if vim.fn.buflisted(buf) == 1 and name ~= "" and vim.bo[buf].buftype == "" then
			table.insert(buflist, vim.fn.fnamemodify(name, ":."))
		end
	end
	return buflist
end

--- True when a buffer belongs to neo-tree.
--- @param buf integer
--- @return boolean
local function is_neotree_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	return vim.bo[buf].filetype == "neo-tree" or vim.api.nvim_buf_get_name(buf):match("neo%-tree") ~= nil
end

--- True when neo-tree occupies any window.
--- @return boolean
local function is_neotree_open()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and is_neotree_buffer(vim.api.nvim_win_get_buf(win)) then
			return true
		end
	end
	return false
end

--- Deletes every neo-tree buffer, so `mksession!` cannot serialize a dead one.
local function purge_neotree_buffers()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_neotree_buffer(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end

--- Re-opens neo-tree on a directory and refreshes it.
--- @param dir string Directory to show.
local function show_neotree(dir)
	pcall(vim.cmd, "Neotree show dir=" .. vim.fn.fnameescape(dir))
	pcall(function()
		require("neo-tree.sources.manager").refresh("filesystem")
	end)
end

--- True when a buffer is a terminal or one of the transient UI filetypes.
--- @param buf integer
--- @return boolean
local function is_transient_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype == "terminal" or vim.b[buf].krs_is_task then
		return true
	end
	return vim.tbl_contains(M.settings.transient_filetypes, vim.bo[buf].filetype)
end

--- Writes the current layout to `session_path`.
--- Neo-tree and terminals are closed first and restored afterwards.
---
--- @param session_path string Destination `.vim` session file.
--- @return boolean ok
--- @return string|nil err
--- @return boolean neotree_was_open Whether neo-tree should reopen on load.
local function save_session_file(session_path)
	vim.opt.sessionoptions = M.settings.session_options

	local neotree_was_open = is_neotree_open()
	pcall(vim.cmd, "Neotree close")

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and is_transient_buffer(vim.api.nvim_win_get_buf(win)) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	purge_neotree_buffers()

	local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(session_path))

	if neotree_was_open then
		show_neotree(vim.fn.getcwd())
	end

	return ok, err, neotree_was_open
end

-- ============================================================================
-- WORKSPACE OPERATIONS
-- ============================================================================

--- Saves the current layout as a workspace.
--- With no name: overwrites this project's first workspace, or prompts for a name
--- when the project has none yet.
---
--- @param name string|nil Workspace name.
--- @param callback function|nil Called after a successful save.
function M.save_workspace(name, callback)
	local cwd = vim.fn.getcwd()
	local cwd_name = vim.fn.fnamemodify(cwd, ":t")
	local index = load_index()

	local function perform_save(ws_name)
		if not ws_name or ws_name == "" then
			local count = 1
			for _, item in ipairs(index) do
				if item.cwd == cwd then
					count = count + 1
				end
			end
			ws_name = string.format("%s (Workspace %d)", cwd_name, count)
		end

		local ws_item
		for _, item in ipairs(index) do
			if item.name:lower() == ws_name:lower() and item.cwd == cwd then
				ws_item = item
				break
			end
		end

		local id = ws_item and ws_item.id or ("ws_" .. os.time() .. "_" .. math.random(1000, 9999))
		local session_path = path.join(storage_dir(), id .. ".vim")

		local ok, err, neotree_open = save_session_file(session_path)
		if not ok then
			vim.notify("Error saving workspace: " .. tostring(err), vim.log.levels.ERROR)
			return
		end

		local snapshot = {
			updated_at = os.time(),
			buffers = get_current_buffers(),
			tab_count = #vim.api.nvim_list_tabpages(),
			session_file = session_path,
			neotree_open = neotree_open,
		}

		if ws_item then
			for key, value in pairs(snapshot) do
				ws_item[key] = value
			end
		else
			table.insert(
				index,
				1,
				vim.tbl_extend("force", {
					id = id,
					name = ws_name,
					cwd = cwd,
					cwd_name = cwd_name,
					created_at = os.time(),
				}, snapshot)
			)
		end

		save_index(index)
		notify("Workspace '" .. ws_name .. "' saved successfully!")
		if callback then
			callback()
		end
	end

	if name and name ~= "" then
		perform_save(name)
		return
	end

	for _, item in ipairs(index) do
		if item.cwd == cwd then
			perform_save(item.name)
			return
		end
	end

	pcall(vim.ui.input, {
		prompt = "New Workspace Name: ",
		default = cwd_name .. " - " .. os.date("%H:%M"),
	}, function(input_name)
		if input_name and input_name ~= "" then
			perform_save(input_name)
		end
	end)
end

--- Resolves the argument of `load_workspace` into a workspace record.
--- @param index table[] Loaded index.
--- @param identifier table|string|number Record, id/name, or slot within this project.
--- @return table|nil workspace
local function resolve_load_target(index, identifier)
	if type(identifier) == "table" then
		return identifier
	end

	if type(identifier) == "number" then
		local cwd = vim.fn.getcwd()
		local count = 0
		for _, item in ipairs(index) do
			if item.cwd == cwd then
				count = count + 1
				if count == identifier then
					return item
				end
			end
		end
		return nil
	end

	if type(identifier) == "string" and identifier ~= "" then
		return (find_workspace(index, identifier))
	end
	return nil
end

--- Restores a workspace: switches directory, sources the session, and rebuilds
--- the neo-tree / terminal state around it.
---
--- @param ws_or_identifier table|string|number Record, id/name, or slot number.
--- @return boolean loaded
function M.load_workspace(ws_or_identifier)
	local index = load_index()
	local target = resolve_load_target(index, ws_or_identifier)

	if not target then
		notify("Workspace not found", vim.log.levels.WARN)
		return false
	end
	if not path.is_file(target.session_file) then
		notify("Session file does not exist: " .. target.session_file, vim.log.levels.ERROR)
		return false
	end

	-- Staying inside the same project keeps its terminals and task outputs alive;
	-- switching projects clears them, because they belong to the old root.
	local is_same_project = path.equals(vim.fn.getcwd(), target.cwd or vim.fn.getcwd())
	local current_neotree_was_open = is_neotree_open()

	if target.cwd and vim.fn.getcwd() ~= target.cwd then
		pcall(vim.api.nvim_set_current_dir, target.cwd)
	end

	pcall(vim.cmd, "Neotree close")
	purge_neotree_buffers()

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and not (is_same_project and is_transient_buffer(buf)) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end

	local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(target.session_file))
	if not ok then
		notify("Error loading session: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	-- Older session files may still contain neo-tree windows; drop them.
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and is_neotree_buffer(vim.api.nvim_win_get_buf(win)) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	purge_neotree_buffers()

	if is_same_project then
		pcall(function()
			require("plugins.krs.dev.tasks").sync_task_slots()
		end)
	else
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if is_transient_buffer(buf) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
	end

	-- Workspaces open neo-tree by default unless explicitly disabled.
	if target.neotree_open ~= false then
		show_neotree(target.cwd or vim.fn.getcwd())
	end

	target.updated_at = os.time()
	save_index(index)
	M.current_workspace = target

	pcall(function()
		require("plugins.krs.ui.pinned_tabs").restore_pins()
	end)

	notify("Workspace '" .. target.name .. "' loaded!")
	return true
end

--- Deletes a workspace and its session file, after a confirmation prompt.
--- @param ws_or_id table|string Record, id, or name.
--- @param callback function|nil Called after deletion.
function M.delete_workspace(ws_or_id, callback)
	local index = load_index()
	local target, position = find_workspace(index, ws_or_id)

	if not target then
		notify("Workspace not found to delete", vim.log.levels.WARN)
		return
	end

	if vim.fn.confirm("Delete workspace '" .. target.name .. "'?", "&Yes\n&No", 2) ~= 1 then
		return
	end

	if path.is_file(target.session_file) then
		os.remove(target.session_file)
	end
	table.remove(index, position)
	save_index(index)

	notify("Workspace '" .. target.name .. "' deleted.")
	if callback then
		callback()
	end
end

--- Renames a workspace through a prompt.
--- @param ws_or_id table|string Record, id, or name.
--- @param callback function|nil Called after renaming.
function M.rename_workspace(ws_or_id, callback)
	local index = load_index()
	local target = find_workspace(index, ws_or_id)

	if not target then
		notify("Workspace not found to rename", vim.log.levels.WARN)
		return
	end

	pcall(vim.ui.input, { prompt = "New name for '" .. target.name .. "': ", default = target.name }, function(new_name)
		if new_name and new_name ~= "" and new_name ~= target.name then
			target.name = new_name
			target.updated_at = os.time()
			save_index(index)
			notify("Workspace renamed to '" .. new_name .. "'")
			if callback then
				callback()
			end
		end
	end)
end

--- Closes the session and returns to the dashboard, offering to save first.
function M.close_to_menu()
	if vim.bo.filetype == "alpha" then
		notify("Already at main menu")
		return
	end

	local function close_all_and_open_alpha()
		M.current_workspace = nil
		pcall(vim.cmd, "Neotree close")
		purge_neotree_buffers()
		pcall(vim.cmd, "only")
		vim.cmd("Alpha")

		local alpha_buf = vim.api.nvim_get_current_buf()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if buf ~= alpha_buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype ~= "alpha" then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
	end

	local choices = {
		"1. 💾 Save Workspace and return to Menu",
		"2. 🚪 Return to Menu without saving",
		"3. ❌ Cancel",
	}

	pcall(vim.ui.select, choices, {
		prompt = "🦊 Close session and return to Main Menu (Dashboard)?",
	}, function(choice)
		if not choice or choice:match("^3") then
			return
		end
		if choice:match("^1") then
			M.save_workspace(nil, close_all_and_open_alpha)
		else
			close_all_and_open_alpha()
		end
	end)
end

-- ============================================================================
-- PICKER (Telescope)
-- ============================================================================

--- One row of the picker.
--- @param entry table Workspace record with `slot_idx` set.
--- @param current_cwd string
--- @return string display
local function format_entry(entry, current_cwd)
	local buf_count = entry.buffers and #entry.buffers or 0
	local tab_count = entry.tab_count or 1

	return string.format(
		"[%d] %s  %s %s  •  %d buffer%s, %d tab%s  (%s)",
		entry.slot_idx,
		entry.name,
		entry.cwd == current_cwd and "📍" or "📁",
		entry.cwd_name or "",
		buf_count,
		buf_count == 1 and "" or "s",
		tab_count,
		tab_count == 1 and "" or "s",
		format_relative_time(entry.updated_at)
	)
end

--- Detail pane for the selected workspace.
--- @param ws table Workspace record.
--- @return string[] lines
local function format_preview(ws)
	local lines = {
		"📌 Name:         " .. ws.name,
		"📁 Project:      " .. (ws.cwd_name or ""),
		"🌐 CWD Path:     " .. ws.cwd,
		"🕒 Updated:      " .. os.date("%Y-%m-%d %H:%M:%S", ws.updated_at or os.time()),
		"📑 Tabs:         " .. tostring(ws.tab_count or 1),
		"",
		"📄 Saved Files (" .. #(ws.buffers or {}) .. "):",
		"----------------------------------------",
	}
	for i, buf in ipairs(ws.buffers or {}) do
		table.insert(lines, string.format("  %d. %s", i, buf))
	end
	if #(ws.buffers or {}) == 0 then
		table.insert(lines, "  (no files)")
	end
	return lines
end

--- Opens the workspace picker.
--- Workspaces of the current project sort first; `g` toggles between showing only
--- them and showing every workspace.
function M.select_workspace()
	if not pcall(require, "telescope") then
		notify("Telescope is not available", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")
	local themes = require("telescope.themes")

	local current_cwd = vim.fn.getcwd()

	-- Nothing saved for this project yet: start on the full list, or the picker
	-- would open empty.
	local show_all = true
	for _, item in ipairs(load_index()) do
		if item.cwd == current_cwd then
			show_all = false
			break
		end
	end

	--- Visible workspaces, current project first, newest first, slots assigned.
	local function get_results()
		local index = load_index()
		table.sort(index, function(a, b)
			local a_curr = a.cwd == current_cwd and 1 or 0
			local b_curr = b.cwd == current_cwd and 1 or 0
			if a_curr ~= b_curr then
				return a_curr > b_curr
			end
			return (a.updated_at or 0) > (b.updated_at or 0)
		end)

		local results = {}
		for _, item in ipairs(index) do
			if show_all or item.cwd == current_cwd then
				item.slot_idx = #results + 1
				table.insert(results, item)
			end
		end
		return results
	end

	local function open_picker()
		pickers
			.new(
				themes.get_dropdown({
					prompt_title = string.format(
						" 🦊 Workspaces [%s] (a: New | d: Delete | r: Rename | s: Overwrite | g: %s) ",
						vim.fn.fnamemodify(current_cwd, ":t"),
						show_all and "Current Project Only" or "View All"
					),
					width = 0.85,
					results_title = "Saved Workspaces",
				}),
				{
					finder = finders.new_table({
						results = get_results(),
						entry_maker = function(entry)
							return {
								value = entry,
								display = format_entry(entry, current_cwd),
								ordinal = entry.name .. " " .. (entry.cwd_name or "") .. " " .. tostring(entry.slot_idx),
							}
						end,
					}),
					sorter = conf.generic_sorter({}),
					previewer = previewers.new_buffer_previewer({
						title = "Workspace Details",
						define_preview = function(self, entry)
							vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, format_preview(entry.value))
							vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
							if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
								vim.wo[self.state.winid].conceallevel = 3
								vim.wo[self.state.winid].concealcursor = "nvic"
								local ok, rm_ui = pcall(require, "render-markdown.core.ui")
								if ok and rm_ui and type(rm_ui.update) == "function" then
									rm_ui.update(self.state.bufnr, self.state.winid, "UserCommand", true)
								end
							end
						end,
					}),
					attach_mappings = function(prompt_bufnr, map)
						--- Reopens the picker after an action that changed the list.
						local function reopen()
							vim.schedule(M.select_workspace)
						end

						--- Binds one action to several key/mode pairs.
						--- @param bindings table[] `{ mode, key }` pairs.
						--- @param fn function
						local function map_all(bindings, fn)
							for _, binding in ipairs(bindings) do
								map(binding[1], binding[2], fn)
							end
						end

						--- Current selection, or nil.
						local function selected()
							local selection = action_state.get_selected_entry()
							return selection and selection.value or nil
						end

						-- <Esc> in insert mode only leaves insert mode, so the normal-mode
						-- shortcuts below stay reachable without closing the picker.
						map("i", "<Esc>", function()
							pcall(vim.cmd, "stopinsert")
						end)
						map("n", "<Esc>", actions.close)
						map("n", "q", actions.close)

						actions.select_default:replace(function()
							local value = selected()
							actions.close(prompt_bufnr)
							if value then
								M.load_workspace(value)
							end
						end)

						map_all({ { "i", "<C-d>" }, { "n", "d" }, { "n", "D" }, { "i", "<Del>" } }, function()
							local value = selected()
							if value then
								M.delete_workspace(value, function()
									actions.close(prompt_bufnr)
									reopen()
								end)
							end
						end)

						map_all({ { "i", "<C-r>" }, { "n", "r" }, { "n", "R" }, { "n", "<F2>" } }, function()
							local value = selected()
							if value then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.rename_workspace(value, M.select_workspace)
								end)
							end
						end)

						map_all({ { "i", "<C-a>" }, { "n", "a" }, { "n", "A" } }, function()
							actions.close(prompt_bufnr)
							vim.schedule(function()
								M.save_workspace()
							end)
						end)

						map_all({ { "i", "<C-s>" }, { "i", "<C-S-s>" }, { "n", "s" }, { "n", "S" } }, function()
							local value = selected()
							if value then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.save_workspace(value.name)
								end)
							end
						end)

						map_all({ { "i", "<C-g>" }, { "n", "g" }, { "n", "G" } }, function()
							show_all = not show_all
							actions.close(prompt_bufnr)
							reopen()
						end)

						for slot = 1, M.settings.quick_slots do
							map("n", tostring(slot), function()
								local entries = get_results()
								if entries[slot] then
									actions.close(prompt_bufnr)
									M.load_workspace(entries[slot])
								else
									notify("Workspace #" .. slot .. " does not exist", vim.log.levels.WARN)
								end
							end)
						end

						return true
					end,
				}
			)
			:find()
	end

	open_picker()
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers the `:Workspace*` commands and every keymap.
--- Commands are only created when absent, so a config reload does not clobber a
--- command another plugin may already own.
function M.setup()
	local commands = {
		WorkspaceSave = {
			fn = function(opts)
				M.save_workspace(opts.args ~= "" and opts.args or nil)
			end,
			opts = { nargs = "?", desc = "Save state as workspace" },
		},
		WorkspaceLoad = {
			fn = function(opts)
				if opts.args == "" then
					M.select_workspace()
				else
					M.load_workspace(tonumber(opts.args) or opts.args)
				end
			end,
			opts = { nargs = "?", desc = "Load saved workspace" },
		},
		WorkspaceDelete = {
			fn = function(opts)
				M.delete_workspace(opts.args ~= "" and opts.args or nil)
			end,
			opts = { nargs = "?", desc = "Delete workspace" },
		},
		WorkspaceRename = {
			fn = function(opts)
				local args = vim.split(opts.args, "%s+", { trimempty = true })
				if #args >= 2 then
					M.rename_workspace(args[1], function() end)
				else
					M.select_workspace()
				end
			end,
			opts = { nargs = "*", desc = "Rename workspace" },
		},
		WorkspaceSelect = { fn = M.select_workspace, opts = { desc = "Open the workspace picker" } },
		Workspaces = { fn = M.select_workspace, opts = { desc = "Open the workspace picker" } },
		WorkspaceClose = { fn = M.close_to_menu, opts = { desc = "Close session and return to main menu" } },
		WorkspaceMenu = { fn = M.close_to_menu, opts = { desc = "Close session and return to main menu" } },
	}

	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, spec.fn, spec.opts)
		end
	end

	--- Leaves terminal mode first, so the mapping also works from a terminal.
	local function from_any_mode(fn)
		return function()
			local mode = vim.fn.mode()
			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			fn()
		end
	end

	for _, key in ipairs(M.settings.keys.select) do
		vim.keymap.set({ "n", "i", "v" }, key, from_any_mode(M.select_workspace), {
			noremap = true,
			silent = true,
			desc = "Open Workspaces UI",
		})
	end
	for _, key in ipairs(M.settings.keys.menu) do
		vim.keymap.set({ "n", "i", "v" }, key, from_any_mode(M.close_to_menu), {
			noremap = true,
			silent = true,
			desc = "Close and return to Menu",
		})
	end

	if M.settings.keys.leader_save then
		vim.keymap.set("n", M.settings.keys.leader_save, function()
			M.save_workspace()
		end, { desc = "Save Workspace" })
	end
	if M.settings.keys.leader_select then
		vim.keymap.set("n", M.settings.keys.leader_select, M.select_workspace, { desc = "Select Workspace" })
	end
	if M.settings.keys.leader_menu then
		vim.keymap.set("n", M.settings.keys.leader_menu, M.close_to_menu, { desc = "Close and return to Menu" })
	end

	if M.settings.keys.leader_slot_prefix then
		for slot = 1, M.settings.quick_slots do
			vim.keymap.set("n", M.settings.keys.leader_slot_prefix .. slot, function()
				M.load_workspace(slot)
			end, { desc = "Load Workspace slot " .. slot })
		end
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.Workspaces = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_workspaces",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "WorkspaceSelect", "Workspaces", "WorkspaceSave", "WorkspaceManage", "WorkspaceClose", "WorkspaceMenu" },
	keys = {
		{ "<C-S-w>", mode = { "n", "i" }, desc = "Select Workspace" },
		{ "<C-S-m>", mode = { "n", "i" }, desc = "Close Workspace" },
		{ "<leader>ws", mode = { "n" }, desc = "Select Workspace" },
		{ "<leader>wm", mode = { "n" }, desc = "Close Workspace" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope.nvim",
	},
	config = M.setup,
}, { __index = M })
