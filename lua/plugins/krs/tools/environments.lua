-- ============================================================================
-- KRS PLUGIN: Environments -- Multi-Project Workspace Container (Slots 1..9)
-- ============================================================================
-- WHAT IT DOES
--   1. Manages up to 9 concurrent, isolated project environments inside a single
--      Neovim instance without running multiple separate windows/processes.
--   2. Switch instantly between project cwds with <C-S-1>..<C-S-9> (and terminal
--      compat aliases <C-!>..<C-(>).
--   3. Provides a full interactive CRUD menu (<C-S-e> or :EnvironmentMenu) to
--      list, switch, create, rename, and close environment slots.
--   4. Scopes LSP servers per environment:
--      - On environment close: automatically stops all LSP clients whose root_dir
--        belongs to that closed environment.
--      - On environment switch: keeps dormant LSPs intact in memory (0% CPU)
--        instead of killing and cold-booting language servers.
--   5. Scopes terminals per environment:
--      - Each environment owns its own 9 terminal slots (<A-1>..<A-9>).
--      - Background terminal jobs keep running in their respective project roots.
--      - Closing an environment terminates its scoped terminal jobs.
--   6. Bufferline & UI Isolation:
--      - Bufferline tabs only show files belonging to the active environment.
--      - A discreet statusline indicator shows `󰒋 [Env N: name]` ONLY when > 1
--        environments are active. When only 1 environment is active, nothing is shown.
--   7. Full Persistence & Workspaces Compatibility:
--      - Saves environment layouts and metadata in stdpath("data")/environments.
--      - Can export any environment slot as a named Workspace (:EnvironmentSaveAsWorkspace)
--        or load any saved Workspace into a slot (:EnvironmentLoadWorkspace).
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Where environment session files and the index live.
	storage_dir = vim.fn.stdpath("data") .. "/environments",

	--- Index file name inside `storage_dir`.
	index_file = "index.json",

	--- Title on every notification from this module.
	notify_title = "KRS Environments",

	--- Maximum number of environment slots (1..9 for numeric pad/number row).
	max_slots = 9,

	--- Session options recorded for environment snapshots.
	session_options = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions",

	--- Filetypes treated as transient UI: closed before saving layout.
	transient_filetypes = { "TaskRunner", "toggleterm", "neo-tree", "alpha", "dashboard" },

	keys = {
		--- Open the Environments CRUD menu.
		menu = { "<C-S-e>", "<C-S-E>", "<leader>ee" },
		--- Quick slot selection prefix: the slot number is appended (<C-S-1>..<C-S-9>).
		slot_prefix = "<C-S-",
		--- Terminal-compatible symbol prefix when Shift+1..9 produces symbols under Ctrl.
		symbols = { "!", "@", "#", "$", "%", "^", "&", "*", "(" },
	},
}

-- ============================================================================
-- STATE (Global for reload survival and cross-module inspection)
-- ============================================================================

_G._krs_environments = _G._krs_environments or {}
_G._krs_active_env_slot = _G._krs_active_env_slot or 1

-- ============================================================================
-- STORAGE & PATH HELPERS
-- ============================================================================

local function storage_dir()
	return path.ensure_dir(M.settings.storage_dir)
end

local function index_path()
	return path.join(storage_dir(), M.settings.index_file)
end

local function session_path_for_slot(slot)
	return path.join(storage_dir(), string.format("env_slot_%d.vim", slot))
end

--- Notification helper.
--- @param msg string
--- @param level integer|nil
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

--- Formats relative elapsed time.
--- @param timestamp integer|nil
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

-- ============================================================================
-- INDEX PERSISTENCE
-- ============================================================================

--- Loads persisted environments index.
--- @return table
function M.load_index()
	local raw = store.load(index_path(), { active_slot = 1, slots = {} })
	if type(raw) ~= "table" then
		raw = { active_slot = 1, slots = {} }
	end
	raw.slots = raw.slots or {}
	return raw
end

--- Saves environments index to disk.
--- @param data table|nil
--- @return boolean ok
function M.save_index(data)
	if not data then
		local slots_data = {}
		for slot = 1, M.settings.max_slots do
			local env = _G._krs_environments[slot]
			if env then
				slots_data[tostring(slot)] = {
					slot = env.slot,
					id = env.id,
					name = env.name,
					cwd = env.cwd,
					cwd_name = env.cwd_name,
					session_file = env.session_file,
					created_at = env.created_at,
					updated_at = env.updated_at,
					buffers = env.buffers or {},
					neotree_open = env.neotree_open,
				}
			end
		end
		data = {
			active_slot = _G._krs_active_env_slot or 1,
			slots = slots_data,
		}
	end
	return store.save(index_path(), data)
end

-- ============================================================================
-- QUERY & METRIC API
-- ============================================================================

--- Returns the currently active environment slot number (1..9).
--- @return integer
function M.get_active_slot()
	return _G._krs_active_env_slot or 1
end

--- Returns environment record for a slot, or nil.
--- @param slot integer
--- @return table|nil
function M.get_environment(slot)
	return _G._krs_environments[slot]
end

--- Returns the currently active environment record, or nil.
--- @return table|nil
function M.get_active_environment()
	return _G._krs_environments[M.get_active_slot()]
end

--- Returns total number of currently configured active environments.
--- @return integer
function M.get_active_count()
	local count = 0
	for slot = 1, M.settings.max_slots do
		if _G._krs_environments[slot] ~= nil then
			count = count + 1
		end
	end
	return count
end

--- True when more than one environment is active.
--- @return boolean
function M.has_multiple_environments()
	return M.get_active_count() > 1
end

--- Formats statusline indicator badge for the active environment.
--- Returns an empty string when <= 1 environment is active, so Lualine renders nothing.
--- @return string
function M.indicator_status()
	if not M.has_multiple_environments() then
		return ""
	end
	local cur_slot = M.get_active_slot()
	local env = M.get_environment(cur_slot)
	local label = env and (env.name or env.cwd_name) or ("Env " .. cur_slot)
	return string.format("󰒋 [%d: %s]", cur_slot, label)
end

-- ============================================================================
-- BUFFER & LSP SCOPING HELPERS
-- ============================================================================

--- Checks if a buffer belongs to neo-tree or transient UI.
--- @param buf integer
--- @return boolean
local function is_transient_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	local bt = vim.bo[buf].buftype
	local ft = vim.bo[buf].filetype
	if bt == "terminal" or ft == "neo-tree" or vim.b[buf].krs_is_task then
		return true
	end
	return vim.tbl_contains(M.settings.transient_filetypes, ft)
end

--- Checks if neo-tree occupies any window.
--- @return boolean
local function is_neotree_open()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if
				vim.api.nvim_buf_is_valid(buf)
				and (vim.bo[buf].filetype == "neo-tree" or vim.api.nvim_buf_get_name(buf):match("neo%-tree"))
			then
				return true
			end
		end
	end
	return false
end

--- Closes and purges neo-tree buffers before saving layout.
local function purge_neotree()
	pcall(vim.cmd, "Neotree close")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(buf)
			and (vim.bo[buf].filetype == "neo-tree" or vim.api.nvim_buf_get_name(buf):match("neo%-tree"))
		then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end

--- Collects relative paths of listed file buffers.
--- @return string[]
local function get_listed_buffer_names()
	local list = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1 then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" and vim.bo[buf].buftype == "" then
				table.insert(list, vim.fn.fnamemodify(name, ":."))
			end
		end
	end
	return list
end

--- Checks whether a buffer belongs to the currently active environment.
--- Used by bufferline custom_filter and buffer management tools.
--- @param bufnr integer
--- @return boolean
function M.is_buffer_in_current_environment(bufnr)
	if not M.has_multiple_environments() then
		return true
	end
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local cur_slot = M.get_active_slot()
	local assigned_slot = vim.b[bufnr].krs_env_slot

	if assigned_slot ~= nil then
		return assigned_slot == cur_slot
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		-- Unnamed buffer belongs to the current session
		return true
	end

	local cur_env = M.get_environment(cur_slot)
	if cur_env and cur_env.cwd then
		local norm_cwd = path.normalize(cur_env.cwd)
		local norm_name = path.normalize(name)
		if path.relative_to(norm_name, norm_cwd) ~= nil then
			vim.b[bufnr].krs_env_slot = cur_slot
			return true
		end
	end

	-- Check if it belongs to another active environment
	for slot = 1, M.settings.max_slots do
		if slot ~= cur_slot and _G._krs_environments[slot] then
			local other_env = _G._krs_environments[slot]
			if other_env.cwd then
				local norm_other = path.normalize(other_env.cwd)
				local norm_name = path.normalize(name)
				if path.relative_to(norm_name, norm_other) ~= nil then
					vim.b[bufnr].krs_env_slot = slot
					return false
				end
			end
		end
	end

	-- Default unassigned buffer in current environment
	vim.b[bufnr].krs_env_slot = cur_slot
	return true
end

--- Returns active LSP client names attached to buffers in the given environment.
--- @param env table
--- @return string[] client_names
function M.get_environment_lsps(env)
	if not env or not env.cwd then
		return {}
	end
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	if not get_clients then
		return {}
	end

	local norm_cwd = path.normalize(env.cwd)
	local seen = {}
	local names = {}

	for _, client in ipairs(get_clients()) do
		local root = client.config and client.config.root_dir or client.root_dir
		if root then
			local norm_root = path.normalize(root)
			if path.equals(norm_root, norm_cwd) or path.relative_to(norm_root, norm_cwd) ~= nil then
				if not seen[client.name] then
					seen[client.name] = true
					table.insert(names, client.name)
				end
			end
		end
	end
	return names
end

--- Stops all LSP clients strictly scoped to an environment being closed,
--- provided no other active environment shares the exact same cwd.
--- @param env table
function M.stop_environment_lsps(env)
	if not env or not env.cwd then
		return
	end
	local norm_cwd = path.normalize(env.cwd)

	-- Check if any remaining active environment shares this cwd
	for slot = 1, M.settings.max_slots do
		local other = _G._krs_environments[slot]
		if other and other ~= env and other.cwd and path.equals(path.normalize(other.cwd), norm_cwd) then
			return
		end
	end

	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	if not get_clients then
		return
	end

	for _, client in ipairs(get_clients()) do
		local root = client.config and client.config.root_dir or client.root_dir
		if root then
			local norm_root = path.normalize(root)
			if path.equals(norm_root, norm_cwd) or path.relative_to(norm_root, norm_cwd) ~= nil then
				pcall(function()
					client:stop()
				end)
			end
		end
	end
end

-- ============================================================================
-- TERMINAL POOL MANAGEMENT
-- ============================================================================

--- Closes any visible terminal window to prevent orphaned splits during environment transitions.
local function dismiss_visible_terminals()
	if _G.TerminalManager and _G.TerminalManager.toggle_selected_terminal then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_is_valid(win) then
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].buftype == "terminal" or vim.b[buf].krs_is_multi_term) then
					pcall(vim.api.nvim_win_close, win, true)
				end
			end
		end
	end
end

--- Swaps global multi-terminal pool `_G._krs_terminals` in place so existing
--- local references held inside `terminal.lua` continue to work synchronously.
--- @param target_pool table|nil
local function swap_terminal_pool(target_pool)
	dismiss_visible_terminals()
	_G._krs_terminals = _G._krs_terminals or {}

	for k in pairs(_G._krs_terminals) do
		_G._krs_terminals[k] = nil
	end

	if target_pool and type(target_pool) == "table" then
		for k, v in pairs(target_pool) do
			_G._krs_terminals[k] = v
		end
	end
end

--- Safely terminates all background terminal processes belonging to an environment.
--- @param env table
local function kill_environment_terminals(env)
	if not env or not env.terminals then
		return
	end
	for _, term in pairs(env.terminals) do
		if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
			pcall(vim.api.nvim_buf_delete, term.buf, { force = true })
		end
	end
end

-- ============================================================================
-- SNAPSHOT & RESTORE
-- ============================================================================

--- Ensures slot 1 is properly initialized representing the current working directory
--- if multiple environments are created while slot 1 is still unset.
local function ensure_current_slot_initialized()
	local active_slot = M.get_active_slot()
	if not _G._krs_environments[active_slot] then
		local cwd = vim.fn.getcwd()
		local cwd_name = vim.fn.fnamemodify(cwd, ":t")
		_G._krs_environments[active_slot] = {
			slot = active_slot,
			id = string.format("env_%d_%d", active_slot, os.time()),
			name = cwd_name,
			cwd = cwd,
			cwd_name = cwd_name,
			created_at = os.time(),
			updated_at = os.time(),
			session_file = session_path_for_slot(active_slot),
			buffers = get_listed_buffer_names(),
			terminals = vim.deepcopy(_G._krs_terminals or {}),
			neotree_open = is_neotree_open(),
		}
	end
end

--- Saves the layout and state of the currently active environment to its session file.
--- @param env table|nil
--- @return boolean ok
local function snapshot_active_environment(env)
	env = env or M.get_active_environment()
	if not env then
		return false
	end

	vim.opt.sessionoptions = M.settings.session_options
	local neotree_was_open = is_neotree_open()
	purge_neotree()
	dismiss_visible_terminals()

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1 then
			if vim.b[buf].krs_env_slot == nil or vim.b[buf].krs_env_slot == env.slot then
				vim.b[buf].krs_env_slot = env.slot
			end
		end
	end

	env.session_file = env.session_file or session_path_for_slot(env.slot)
	pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(env.session_file))

	env.updated_at = os.time()
	env.buffers = get_listed_buffer_names()
	env.terminals = vim.deepcopy(_G._krs_terminals or {})
	env.neotree_open = neotree_was_open

	if neotree_was_open then
		pcall(vim.cmd, "Neotree focus dir=" .. vim.fn.fnameescape(env.cwd or vim.fn.getcwd()))
	end

	return true
end

-- ============================================================================
-- ENVIRONMENT CRUD OPERATIONS
-- ============================================================================

--- Creates a new environment in `slot` pointing to `dir`.
--- @param slot integer Target slot 1..9.
--- @param dir string Target directory path.
--- @param name string|nil Custom friendly label.
--- @param auto_switch boolean|nil Whether to switch immediately after creation.
--- @return table|nil env Created environment record.
function M.create_environment(slot, dir, name, auto_switch)
	if type(slot) ~= "number" or slot < 1 or slot > M.settings.max_slots then
		notify("Slot must be a number between 1 and " .. M.settings.max_slots, vim.log.levels.ERROR)
		return nil
	end

	dir = path.normalize(dir or vim.fn.getcwd())
	if vim.fn.isdirectory(dir) == 0 then
		notify("Directory does not exist: " .. dir, vim.log.levels.ERROR)
		return nil
	end

	-- Make sure slot 1 is captured if we are adding another environment
	ensure_current_slot_initialized()

	local cwd_name = vim.fn.fnamemodify(dir, ":t")
	if cwd_name == "" then
		cwd_name = dir
	end

	name = (name and name ~= "") and name or cwd_name

	local env = {
		slot = slot,
		id = string.format("env_%d_%d", slot, os.time()),
		name = name,
		cwd = dir,
		cwd_name = cwd_name,
		created_at = os.time(),
		updated_at = os.time(),
		session_file = session_path_for_slot(slot),
		buffers = {},
		terminals = {},
		neotree_open = true,
	}

	_G._krs_environments[slot] = env
	M.save_index()
	notify(string.format("Created Environment #%d: '%s' (%s)", slot, name, cwd_name))

	if auto_switch ~= false then
		M.switch_environment(slot)
	end

	return env
end

--- Switches to the target environment slot.
--- @param target_slot integer Target slot 1..9.
--- @param callback function|nil
--- @return boolean ok
function M.switch_environment(target_slot, callback)
	if type(target_slot) ~= "number" or target_slot < 1 or target_slot > M.settings.max_slots then
		notify("Target slot must be between 1 and " .. M.settings.max_slots, vim.log.levels.ERROR)
		return false
	end

	local cur_slot = M.get_active_slot()
	if target_slot == cur_slot and _G._krs_environments[target_slot] then
		notify(string.format("Already in Environment #%d (%s)", cur_slot, _G._krs_environments[cur_slot].name or ""))
		if callback then
			callback()
		end
		return true
	end

	local target_env = _G._krs_environments[target_slot]
	if not target_env then
		-- Prompt user to create it
		pcall(vim.ui.input, {
			prompt = string.format("Environment Slot #%d is empty. Enter project path: ", target_slot),
			default = vim.fn.getcwd(),
		}, function(input_path)
			if input_path and input_path ~= "" then
				M.create_environment(target_slot, input_path, nil, true)
			end
		end)
		return false
	end

	-- 1. Snapshot current active environment
	ensure_current_slot_initialized()
	local cur_env = _G._krs_environments[cur_slot]
	if cur_env then
		snapshot_active_environment(cur_env)
	end

	-- 2. Set directory with switching guard so DirChanged does not kill LSPs
	vim.g._krs_environment_switching = true
	if target_env.cwd and vim.fn.isdirectory(target_env.cwd) == 1 then
		pcall(vim.api.nvim_set_current_dir, target_env.cwd)
	end
	_G._krs_active_env_slot = target_slot
	vim.g._krs_environment_switching = false

	-- 3. Swap terminal pools
	swap_terminal_pool(target_env.terminals)

	-- 4. Restore window layout
	purge_neotree()
	pcall(vim.cmd, "silent! only")

	if target_env.session_file and path.is_file(target_env.session_file) then
		local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(target_env.session_file))
		if not ok then
			notify("Warning restoring environment session: " .. tostring(err), vim.log.levels.WARN)
			vim.cmd("enew")
		end
	else
		vim.cmd("enew")
	end

	-- Drop any neo-tree buffers that might have been saved in session
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) then
			local b = vim.api.nvim_win_get_buf(win)
			if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == "neo-tree" then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
	end

	-- 5. Restore Neo-tree
	if target_env.neotree_open ~= false then
		pcall(vim.cmd, "Neotree focus dir=" .. vim.fn.fnameescape(target_env.cwd or vim.fn.getcwd()))
		pcall(function()
			require("neo-tree.sources.manager").refresh("filesystem")
		end)
	end

	-- 6. Invalidate branch cache & refresh statusline / bufferline
	pcall(function()
		local sl = package.loaded["plugins.krs.ui.statusline_picker"]
		if sl and sl._branch_cache then
			sl._branch_cache = {}
		end
		local lualine = package.loaded["lualine"]
		if lualine then
			lualine.refresh()
		end
	end)

	pcall(function()
		require("plugins.krs.ui.pinned_tabs").restore_pins()
	end)

	vim.cmd("redrawtabline")
	vim.cmd("redrawstatus")

	target_env.updated_at = os.time()
	M.save_index()

	notify(string.format("🌿 Active Environment: #%d (%s)", target_slot, target_env.name or target_env.cwd_name))
	if callback then
		callback()
	end
	return true
end

--- Closes and unloads an environment, terminating its scoped LSPs, terminals, and buffers.
--- @param slot integer Target slot 1..9.
--- @param callback function|nil
function M.close_environment(slot, callback)
	slot = slot or M.get_active_slot()
	local env = _G._krs_environments[slot]
	if not env then
		notify("Environment slot #" .. slot .. " is not active", vim.log.levels.WARN)
		if callback then
			callback()
		end
		return
	end

	local confirm_msg = string.format(
		"Close Environment #%d ('%s')?\nThis stops its scoped LSPs, terminals and unloads its buffers.",
		slot,
		env.name
	)
	if vim.fn.confirm(confirm_msg, "&Yes\n&No", 2) ~= 1 then
		if callback then
			callback()
		end
		return
	end

	-- 1. Stop scoped LSPs
	M.stop_environment_lsps(env)

	-- 2. Kill scoped terminals
	kill_environment_terminals(env)

	-- 3. Delete buffers belonging to this slot
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			if vim.b[buf].krs_env_slot == slot then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
	end

	-- 4. Delete session file
	if env.session_file and path.is_file(env.session_file) then
		pcall(os.remove, env.session_file)
	end

	-- 5. Remove slot
	_G._krs_environments[slot] = nil

	-- 6. If we closed the active slot, switch to another remaining slot
	if slot == M.get_active_slot() then
		local next_slot = nil
		for s = 1, M.settings.max_slots do
			if _G._krs_environments[s] ~= nil then
				next_slot = s
				break
			end
		end

		if next_slot then
			M.switch_environment(next_slot)
		else
			-- No other environments active: reset to single editor mode
			_G._krs_active_env_slot = 1
			pcall(vim.cmd, "silent! only")
			vim.cmd("enew")
			pcall(function()
				local lualine = package.loaded["lualine"]
				if lualine then
					lualine.refresh()
				end
			end)
			vim.cmd("redrawtabline")
			vim.cmd("redrawstatus")
		end
	else
		pcall(function()
			local lualine = package.loaded["lualine"]
			if lualine then
				lualine.refresh()
			end
		end)
		vim.cmd("redrawtabline")
		vim.cmd("redrawstatus")
	end

	M.save_index()
	notify(string.format("Environment #%d ('%s') closed.", slot, env.name))
	if callback then
		callback()
	end
end

--- Renames an environment slot.
--- @param slot integer
--- @param new_name string|nil
--- @param callback function|nil
function M.rename_environment(slot, new_name, callback)
	slot = slot or M.get_active_slot()
	local env = _G._krs_environments[slot]
	if not env then
		notify("Environment slot #" .. slot .. " is not active", vim.log.levels.WARN)
		return
	end

	local function apply_rename(name)
		if name and name ~= "" then
			env.name = name
			env.updated_at = os.time()
			M.save_index()
			pcall(function()
				local lualine = package.loaded["lualine"]
				if lualine then
					lualine.refresh()
				end
			end)
			notify(string.format("Environment #%d renamed to '%s'", slot, name))
			if callback then
				callback()
			end
		end
	end

	if new_name and new_name ~= "" then
		apply_rename(new_name)
	else
		pcall(vim.ui.input, { prompt = "New Environment Name: ", default = env.name }, apply_rename)
	end
end

--- Saves all active environment snapshots and index to disk.
--- @param silent boolean|nil
function M.save_all(silent)
	ensure_current_slot_initialized()
	local cur_env = M.get_active_environment()
	if cur_env then
		snapshot_active_environment(cur_env)
	end
	M.save_index()
	if not silent then
		notify("All active environments saved!")
	end
end

--- Restores previously saved environments from index.
function M.restore_all()
	local index = M.load_index()
	if not index.slots or vim.tbl_isempty(index.slots) then
		notify("No saved environments found in index", vim.log.levels.WARN)
		return
	end

	for slot_str, data in pairs(index.slots) do
		local slot = tonumber(slot_str)
		if slot and slot >= 1 and slot <= M.settings.max_slots then
			_G._krs_environments[slot] = {
				slot = slot,
				id = data.id,
				name = data.name,
				cwd = data.cwd,
				cwd_name = data.cwd_name,
				created_at = data.created_at,
				updated_at = data.updated_at,
				session_file = data.session_file,
				buffers = data.buffers or {},
				terminals = {},
				neotree_open = data.neotree_open,
			}
		end
	end

	local target = index.active_slot or 1
	if _G._krs_environments[target] then
		M.switch_environment(target)
	else
		for s = 1, M.settings.max_slots do
			if _G._krs_environments[s] then
				M.switch_environment(s)
				break
			end
		end
	end
	notify("Restored saved environments session!")
end

-- ============================================================================
-- WORKSPACES INTEGRATION
-- ============================================================================

--- Saves an environment slot as a named Workspace in `workspaces.lua`.
--- @param slot integer|nil Slot number. Defaults to active slot.
--- @param name string|nil Custom workspace name.
function M.save_as_workspace(slot, name)
	slot = slot or M.get_active_slot()
	local env = _G._krs_environments[slot]
	if not env then
		notify("Environment slot #" .. slot .. " is empty", vim.log.levels.WARN)
		return
	end

	local ws_name = (name and name ~= "") and name or (env.name .. " (Env " .. slot .. ")")
	local ok, workspaces = pcall(require, "plugins.krs.tools.workspaces")
	if ok and workspaces.save_workspace then
		workspaces.save_workspace(ws_name, function()
			notify(string.format("Saved Environment #%d as Workspace '%s'", slot, ws_name))
		end)
	else
		notify("Workspaces plugin is not available", vim.log.levels.ERROR)
	end
end

--- Loads a saved Workspace from `workspaces.lua` into an environment slot.
--- @param slot integer Target slot 1..9.
--- @param ws_identifier table|string|nil
function M.load_from_workspace(slot, ws_identifier)
	slot = slot or M.get_active_slot()
	local ok, workspaces = pcall(require, "plugins.krs.tools.workspaces")
	if not ok then
		notify("Workspaces plugin is not available", vim.log.levels.ERROR)
		return
	end

	local function load_ws(target_ws)
		if not target_ws then
			return
		end
		M.create_environment(slot, target_ws.cwd, target_ws.name, false)
		M.switch_environment(slot, function()
			workspaces.load_workspace(target_ws)
		end)
	end

	if ws_identifier then
		load_ws(ws_identifier)
	else
		pcall(workspaces.select_workspace)
	end
end

-- ============================================================================
-- INTERACTIVE CRUD MENU (Telescope)
-- ============================================================================

--- Generates formatted rows for the CRUD Telescope picker.
--- @return table[]
local function get_picker_entries()
	ensure_current_slot_initialized()
	local active_slot = M.get_active_slot()
	local entries = {}

	for slot = 1, M.settings.max_slots do
		local env = _G._krs_environments[slot]
		local entry = { slot = slot, env = env }
		if env then
			local is_active = (slot == active_slot)
			local buf_cnt = #(env.buffers or {})
			local lsps = M.get_environment_lsps(env)
			local lsp_str = #lsps > 0 and table.concat(lsps, ", ") or "none"
			local term_cnt = 0
			for _, _ in pairs(env.terminals or {}) do
				term_cnt = term_cnt + 1
			end

			entry.is_active = is_active
			entry.display = string.format(
				"[%d] %s %-16s  📁 %-18s  •  %d buf%s, LSP: %s  (%s)",
				slot,
				is_active and "● [ACTIVE]" or "○ [IDLE]  ",
				env.name,
				env.cwd_name or vim.fn.fnamemodify(env.cwd, ":t"),
				buf_cnt,
				buf_cnt == 1 and "" or "s",
				lsp_str,
				format_relative_time(env.updated_at)
			)
			entry.ordinal = string.format("%d %s %s", slot, env.name, env.cwd)
		else
			entry.is_active = false
			entry.display = string.format("[%d] ➕ -- Empty Slot %d -- (Enter or 'a' to configure)", slot, slot)
			entry.ordinal = string.format("%d empty", slot)
		end
		table.insert(entries, entry)
	end
	return entries
end

--- Formats markdown preview for the selected environment slot.
--- @param entry table
--- @return string[]
local function format_preview(entry)
	local slot = entry.slot
	local env = entry.env
	if not env then
		return {
			string.format("# ➕ Environment Slot #%d (Empty)", slot),
			"",
			"This slot is currently empty.",
			"",
			"Press **<CR>** or **a** to assign a project directory to this slot.",
			"Press **1..9** to switch between configured slots directly.",
		}
	end

	local lsps = M.get_environment_lsps(env)
	local lsp_str = #lsps > 0 and table.concat(lsps, ", ") or "(no active LSP attached)"
	local term_cnt = 0
	for _, _ in pairs(env.terminals or {}) do
		term_cnt = term_cnt + 1
	end

	local lines = {
		string.format("# 󰒋 Environment Slot #%d: %s", slot, env.name),
		"",
		"| Property | Value |",
		"|---|---|",
		string.format("| **Status** | %s |", entry.is_active and "🟢 **ACTIVE**" or "⚪ IDLE"),
		string.format("| **Project Root** | `%s` |", env.cwd),
		string.format("| **Folder Name** | `%s` |", env.cwd_name or ""),
		string.format("| **Active LSPs** | `%s` |", lsp_str),
		string.format("| **Terminals** | %d running |", term_cnt),
		string.format("| **Last Updated** | %s |", os.date("%Y-%m-%d %H:%M:%S", env.updated_at or os.time())),
		"",
		"### 📄 Open Buffers (" .. #(env.buffers or {}) .. "):",
		"---",
	}

	for i, bname in ipairs(env.buffers or {}) do
		table.insert(lines, string.format("  %d. `%s`", i, bname))
	end
	if #(env.buffers or {}) == 0 then
		table.insert(lines, "  *(no files)*")
	end

	table.insert(lines, "")
	table.insert(lines, "### ⌨️ Available Actions:")
	table.insert(lines, "- **<CR>** / **Enter**: Switch to this slot (or Create if empty)")
	table.insert(lines, "- **a**: Add / Set project directory for this slot")
	table.insert(lines, "- **r** / **<F2>**: Rename this environment")
	table.insert(lines, "- **d** / **<Del>**: Close & delete this environment")
	table.insert(lines, "- **s**: Save all environments to disk")
	table.insert(lines, "- **w**: Export slot as a Workspace")
	table.insert(lines, "- **1..9**: Quick switch to slot number")

	return lines
end

--- Opens the interactive Environments CRUD menu.
function M.open_menu()
	if not pcall(require, "telescope") then
		notify("Telescope is required for the Environments menu", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")
	local themes = require("telescope.themes")

	local function open_picker()
		pickers
			.new(
				themes.get_dropdown({
					prompt_title = " 🌐 Environments (1..9) | <CR>: Switch | a: Add | r: Rename | d: Close | s: Save ",
					width = 0.88,
					results_title = "Active Project Slots",
				}),
				{
					finder = finders.new_table({
						results = get_picker_entries(),
						entry_maker = function(entry)
							return {
								value = entry,
								display = entry.display,
								ordinal = entry.ordinal,
							}
						end,
					}),
					sorter = conf.generic_sorter({}),
					previewer = previewers.new_buffer_previewer({
						title = "Environment Details",
						define_preview = function(self, entry)
							vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, format_preview(entry.value))
							vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
						end,
					}),
					attach_mappings = function(prompt_bufnr, map)
						local function selected()
							local sel = action_state.get_selected_entry()
							return sel and sel.value or nil
						end

						map("i", "<Esc>", function()
							pcall(vim.cmd, "stopinsert")
						end)
						map("n", "<Esc>", actions.close)
						map("n", "q", actions.close)

						-- Switch or configure on <CR>
						actions.select_default:replace(function()
							local val = selected()
							actions.close(prompt_bufnr)
							if not val then
								return
							end
							if val.env then
								M.switch_environment(val.slot)
							else
								pcall(vim.ui.input, {
									prompt = string.format("Configure Environment Slot #%d (Project Directory): ", val.slot),
									default = vim.fn.getcwd(),
								}, function(input_path)
									if input_path and input_path ~= "" then
										M.create_environment(val.slot, input_path, nil, true)
									end
								end)
							end
						end)

						-- 'a': Add / Configure slot
						local function handle_add()
							local val = selected()
							local target_slot = val and val.slot or 1
							actions.close(prompt_bufnr)
							vim.schedule(function()
								pcall(vim.ui.input, {
									prompt = string.format("Set Directory for Environment Slot #%d: ", target_slot),
									default = vim.fn.getcwd(),
								}, function(input_path)
									if input_path and input_path ~= "" then
										M.create_environment(target_slot, input_path, nil, true)
									end
								end)
							end)
						end
						map("n", "a", handle_add)
						map("i", "<C-a>", handle_add)

						-- 'd' / '<Del>': Close environment
						local function handle_delete()
							local val = selected()
							if val and val.env then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.close_environment(val.slot, M.open_menu)
								end)
							end
						end
						map("n", "d", handle_delete)
						map("n", "D", handle_delete)
						map("i", "<C-d>", handle_delete)
						map("n", "<Del>", handle_delete)

						-- 'r' / '<F2>': Rename environment
						local function handle_rename()
							local val = selected()
							if val and val.env then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.rename_environment(val.slot, nil, M.open_menu)
								end)
							end
						end
						map("n", "r", handle_rename)
						map("n", "R", handle_rename)
						map("n", "<F2>", handle_rename)
						map("i", "<C-r>", handle_rename)

						-- 's': Save all environments
						local function handle_save()
							actions.close(prompt_bufnr)
							vim.schedule(function()
								M.save_all()
							end)
						end
						map("n", "s", handle_save)
						map("i", "<C-s>", handle_save)

						-- 'w': Export slot as a Workspace
						local function handle_ws_save()
							local val = selected()
							if val and val.env then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.save_as_workspace(val.slot)
								end)
							end
						end
						map("n", "w", handle_ws_save)

						-- 1..9 numeric keys to switch directly
						for slot = 1, M.settings.max_slots do
							map("n", tostring(slot), function()
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.switch_environment(slot)
								end)
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
-- SETUP & KEYMAPS
-- ============================================================================

--- Registers all User Commands and global Keymaps.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local commands = {
		EnvironmentMenu = { fn = M.open_menu, opts = { desc = "Open Environments Manager CRUD menu" } },
		Environments = { fn = M.open_menu, opts = { desc = "Open Environments Manager CRUD menu" } },
		EnvironmentSwitch = {
			fn = function(opts)
				local slot = tonumber(opts.args)
				if slot then
					M.switch_environment(slot)
				else
					M.open_menu()
				end
			end,
			opts = { nargs = "?", desc = "Switch to environment slot 1..9" },
		},
		EnvironmentNew = {
			fn = function(opts)
				local args = vim.split(opts.args, "%s+", { trimempty = true })
				local slot = tonumber(args[1])
				local dir = args[2]
				local name = args[3]
				if not slot then
					for s = 1, M.settings.max_slots do
						if _G._krs_environments[s] == nil then
							slot = s
							break
						end
					end
				end
				slot = slot or 1
				M.create_environment(slot, dir or vim.fn.getcwd(), name, true)
			end,
			opts = { nargs = "*", desc = "Create new environment in a slot [slot] [dir] [name]" },
		},
		EnvironmentClose = {
			fn = function(opts)
				local slot = tonumber(opts.args) or M.get_active_slot()
				M.close_environment(slot)
			end,
			opts = { nargs = "?", desc = "Close environment slot and stop scoped LSPs/terminals" },
		},
		EnvironmentRename = {
			fn = function(opts)
				local args = vim.split(opts.args, "%s+", { trimempty = true })
				local slot = tonumber(args[1])
				local name = args[2]
				if not slot then
					slot = M.get_active_slot()
					name = args[1]
				end
				M.rename_environment(slot, name)
			end,
			opts = { nargs = "*", desc = "Rename environment slot [slot] [name]" },
		},
		EnvironmentSave = {
			fn = function()
				M.save_all()
			end,
			opts = { desc = "Save all environments state" },
		},
		EnvironmentRestore = { fn = M.restore_all, opts = { desc = "Restore saved environments session" } },
		EnvironmentSaveAsWorkspace = {
			fn = function(opts)
				local args = vim.split(opts.args, "%s+", { trimempty = true })
				local slot = tonumber(args[1]) or M.get_active_slot()
				local name = args[2]
				M.save_as_workspace(slot, name)
			end,
			opts = { nargs = "*", desc = "Save environment slot as a Workspace" },
		},
		EnvironmentLoadWorkspace = {
			fn = function(opts)
				local args = vim.split(opts.args, "%s+", { trimempty = true })
				local slot = tonumber(args[1]) or M.get_active_slot()
				local ws_name = args[2]
				M.load_from_workspace(slot, ws_name)
			end,
			opts = { nargs = "*", desc = "Load Workspace into an environment slot" },
		},
		EnvironmentList = {
			fn = function()
				local lines = { "🌐 KRS Environments:" }
				local active_slot = M.get_active_slot()
				for s = 1, M.settings.max_slots do
					local env = _G._krs_environments[s]
					if env then
						local mark = (s == active_slot) and "● [ACTIVE]" or "○"
						local lsps = M.get_environment_lsps(env)
						local lsp_str = #lsps > 0 and (" (LSPs: " .. table.concat(lsps, ", ") .. ")") or ""
						table.insert(lines, string.format("  [%d] %s %s -> %s%s", s, mark, env.name, env.cwd, lsp_str))
					else
						table.insert(lines, string.format("  [%d] -- Empty --", s))
					end
				end
				notify(table.concat(lines, "\n"))
			end,
			opts = { desc = "List status of all environment slots" },
		},
	}

	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, spec.fn, spec.opts)
		end
	end

	local function from_any_mode(fn)
		return function()
			local mode = vim.fn.mode()
			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			fn()
		end
	end

	-- Keymaps for switching slots: <C-S-1>..<C-S-9> and terminal symbols <C-!>..<C-(>
	for slot = 1, M.settings.max_slots do
		local key = M.settings.keys.slot_prefix .. slot .. ">"
		vim.keymap.set(
			{ "n", "i", "v", "t" },
			key,
			from_any_mode(function()
				M.switch_environment(slot)
			end),
			{
				noremap = true,
				silent = true,
				desc = "Switch to Environment #" .. slot,
			}
		)

		-- Terminal compatibility alias
		local sym = M.settings.keys.symbols[slot]
		if sym then
			vim.keymap.set(
				{ "n", "i", "v", "t" },
				"<C-" .. sym .. ">",
				from_any_mode(function()
					M.switch_environment(slot)
				end),
				{
					noremap = true,
					silent = true,
					desc = "Switch to Environment #" .. slot,
				}
			)
		end
	end

	-- Keymap for opening menu
	for _, key in ipairs(M.settings.keys.menu) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.open_menu), {
			noremap = true,
			silent = true,
			desc = "Open Environments Manager",
		})
	end

	-- Autocmd to auto-tag buffers with active slot when opened
	local auto_tag_group = vim.api.nvim_create_augroup("KrsEnvironmentsBufferTagger", { clear = true })
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
		group = auto_tag_group,
		callback = function(args)
			if vim.api.nvim_buf_is_valid(args.buf) and not is_transient_buffer(args.buf) then
				if vim.b[args.buf].krs_env_slot == nil then
					local cur_slot = M.get_active_slot()
					local cur_env = M.get_environment(cur_slot)
					local buf_path = vim.api.nvim_buf_get_name(args.buf)
					if buf_path ~= "" and cur_env and cur_env.cwd then
						local norm_cwd = path.normalize(cur_env.cwd)
						local norm_name = path.normalize(buf_path)
						if path.relative_to(norm_name, norm_cwd) ~= nil then
							vim.b[args.buf].krs_env_slot = cur_slot
						end
					else
						vim.b[args.buf].krs_env_slot = cur_slot
					end
				end
			end
		end,
	})

	-- Autocmd on VimLeavePre to save active environments if > 1 environments are running
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("KrsEnvironmentsAutoSaver", { clear = true }),
		callback = function()
			if M.has_multiple_environments() then
				M.save_all(true)
			end
		end,
	})
end

-- Export global reference for legacy/cross-module access
_G.Environments = M
package.loaded["plugins.krs.tools.environments"] = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_environments",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = {
		"EnvironmentMenu",
		"Environments",
		"EnvironmentSwitch",
		"EnvironmentNew",
		"EnvironmentClose",
		"EnvironmentRename",
		"EnvironmentSave",
		"EnvironmentRestore",
		"EnvironmentList",
		"EnvironmentSaveAsWorkspace",
		"EnvironmentLoadWorkspace",
	},
	keys = {
		{ "<C-S-e>", mode = { "n", "i", "v", "t" }, desc = "Open Environments Manager" },
		{ "<leader>ee", mode = { "n" }, desc = "Open Environments Manager" },
		{ "<C-S-1>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #1" },
		{ "<C-S-2>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #2" },
		{ "<C-S-3>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #3" },
		{ "<C-S-4>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #4" },
		{ "<C-S-5>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #5" },
		{ "<C-S-6>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #6" },
		{ "<C-S-7>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #7" },
		{ "<C-S-8>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #8" },
		{ "<C-S-9>", mode = { "n", "i", "v", "t" }, desc = "Switch to Environment #9" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope.nvim",
	},
	config = M.setup,
}, { __index = M })
