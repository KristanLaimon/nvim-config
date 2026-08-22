-- ============================================================================
-- KRS PLUGIN: Persistent DAP Breakpoints -- `.krsnvim/breakpoints.json`
-- ============================================================================
-- WHAT IT DOES
--   Saves DAP breakpoints per project and restores them when the file is opened
--   again, including breakpoints that are DISABLED rather than removed.
--
-- WHY DISABLED BREAKPOINTS NEED CODE AT ALL
--   nvim-dap has no concept of a disabled breakpoint: it exists or it does not.
--   A disabled one is therefore removed from nvim-dap (so the adapter never binds
--   it) and kept here as our own sign, in our own sign group, carrying the options
--   it had. Signs -- not raw line numbers -- so a disabled breakpoint drifts with
--   edits exactly like a live one.
--
-- COMMANDS
--   :DapBreakpointToggleEnabled   Flip the breakpoint under the cursor.
--   :DapBreakpointsEnableAll      Re-enable every disabled breakpoint.
--   :DapBreakpointsDisableAll     Disable every breakpoint, keeping them.
--   :DapBreakpointsRemoveAll      Remove everything.
--
-- FILE FORMAT -- paths are relative to the project root
--   { "breakpoints": {
--       "src/app.ts": [
--         { "line": 12, "enabled": true },
--         { "line": 40, "enabled": false, "condition": "i > 3" }
--       ] } }
--   A missing `enabled` field counts as true, so files written by older versions
--   still load correctly.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path = lazy_req("krs.core.path")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Per-project file name, resolved inside `.krsnvim/` (see krs.core.project).
	config_file = "breakpoints.json",

	--- Sign group owning the disabled-breakpoint marks. Keep it unique: the whole
	--- group is unplaced at once by `remove_all`.
	sign_group = "krs_dap_disabled",

	--- Sign name, icon and colour of a disabled breakpoint.
	sign_name = "DapBreakpointDisabled",
	sign_text = "🐾",
	sign_color = "#7f848e",

	--- Above nvim-dap's own breakpoint sign (20), so a disabled mark stays visible.
	sign_priority = 21,

	--- Restore is deferred so DAP and the buffer's filetype settle first.
	--- `startup` covers files passed on the command line, which are read before
	--- this plugin's spec runs, so their BufReadPost has already fired.
	restore_delay_ms = 100,
	startup_restore_delay_ms = 150,
}

--- Options of every disabled breakpoint: `[bufnr][sign_id] = { condition, ... }`.
M.disabled = {}

-- ============================================================================
-- DISABLED BREAKPOINT SIGNS
-- ============================================================================

--- Current disabled signs in a buffer.
--- @param bufnr integer
--- @return table<integer,integer> lines Keyed by sign id, valued by line number.
local function disabled_signs(bufnr)
	local out = {}
	local ok, res = pcall(vim.fn.sign_getplaced, bufnr, { group = M.settings.sign_group })
	if ok and res and res[1] then
		for _, sign in ipairs(res[1].signs or {}) do
			out[sign.id] = sign.lnum
		end
	end
	return out
end

--- Id of the disabled sign on a line, if any.
--- @param bufnr integer
--- @param line integer
--- @return integer|nil sign_id
local function disabled_at(bufnr, line)
	for sign_id, lnum in pairs(disabled_signs(bufnr)) do
		if lnum == line then
			return sign_id
		end
	end
	return nil
end

--- Places a disabled sign and remembers the breakpoint options it stands for.
--- @param bufnr integer
--- @param line integer
--- @param opts table|nil `{ condition, hit_condition, log_message }`
--- @return integer sign_id -1 when the sign could not be placed.
local function place_disabled(bufnr, line, opts)
	local sign_id = vim.fn.sign_place(0, M.settings.sign_group, M.settings.sign_name, bufnr, {
		lnum = line,
		priority = M.settings.sign_priority,
	})
	if sign_id ~= -1 then
		M.disabled[bufnr] = M.disabled[bufnr] or {}
		M.disabled[bufnr][sign_id] = opts or {}
	end
	return sign_id
end

--- Re-sends a buffer's breakpoints to every live session.
--- Adding or removing a breakpoint behind nvim-dap's back leaves a running adapter
--- with the old set. `get(bufnr)` returns an empty table when the buffer has none
--- left, which would skip the buffer entirely and keep a stale breakpoint bound --
--- hence the explicit key.
---
--- @param bufnr integer
local function sync_session(bufnr)
	local ok_dap, dap = pcall(require, "dap")
	if not ok_dap or not dap.session() then
		return
	end

	local bps = { [bufnr] = require("dap.breakpoints").get(bufnr)[bufnr] or {} }
	for _, session in pairs(dap.sessions() or {}) do
		pcall(function()
			session:set_breakpoints(bps)
		end)
	end
end

-- ============================================================================
-- ENABLE / DISABLE
-- ============================================================================

--- Turns a live breakpoint into a disabled one, keeping its options.
--- @param bufnr integer
--- @param line integer
--- @return boolean changed
function M.disable_at(bufnr, line)
	local ok_dap, dap_bp = pcall(require, "dap.breakpoints")
	if not ok_dap then
		return false
	end

	for _, bp in ipairs(dap_bp.get(bufnr)[bufnr] or {}) do
		if bp.line == line then
			-- dap.breakpoints.get() hands back the DAP spelling (hitCondition,
			-- logMessage); dap.breakpoints.set() expects the snake_case one.
			local opts = {
				condition = bp.condition,
				hit_condition = bp.hitCondition,
				log_message = bp.logMessage,
			}
			dap_bp.remove(bufnr, line)
			place_disabled(bufnr, line, opts)
			sync_session(bufnr)
			return true
		end
	end
	return false
end

--- Turns a disabled breakpoint back into a live one.
--- @param bufnr integer
--- @param line integer
--- @return boolean changed
function M.enable_at(bufnr, line)
	local sign_id = disabled_at(bufnr, line)
	if not sign_id then
		return false
	end

	local opts = (M.disabled[bufnr] or {})[sign_id] or {}
	vim.fn.sign_unplace(M.settings.sign_group, { buffer = bufnr, id = sign_id })
	if M.disabled[bufnr] then
		M.disabled[bufnr][sign_id] = nil
	end

	local ok_dap, dap_bp = pcall(require, "dap.breakpoints")
	if ok_dap then
		dap_bp.set(opts, bufnr, line)
		sync_session(bufnr)
	end
	return true
end

--- Flips the breakpoint under the cursor, keeping it in place.
--- Returns whether there was one to flip, so a keymap sharing its key with another
--- action can fall through when there was not.
---
--- @param opts table|nil `{ silent = boolean }`
--- @return boolean changed
function M.toggle_enabled(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(0)[1]

	if not (M.enable_at(bufnr, line) or M.disable_at(bufnr, line)) then
		if not opts.silent then
			vim.notify("No breakpoint on this line", vim.log.levels.INFO)
		end
		return false
	end

	M.save_breakpoints()
	return true
end

--- Disables every live breakpoint in every loaded buffer.
function M.disable_all()
	local ok_dap, dap_bp = pcall(require, "dap.breakpoints")
	if not ok_dap then
		return
	end

	local count = 0
	for bufnr, bps in pairs(dap_bp.get()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			-- Collect first: disable_at mutates the list it would otherwise walk.
			local lines = {}
			for _, bp in ipairs(bps) do
				table.insert(lines, bp.line)
			end
			for _, line in ipairs(lines) do
				if M.disable_at(bufnr, line) then
					count = count + 1
				end
			end
		end
	end

	M.save_breakpoints()
	vim.notify("Disabled " .. count .. " breakpoint(s)", vim.log.levels.INFO)
end

--- Re-enables every disabled breakpoint.
function M.enable_all()
	local count = 0
	for bufnr, _ in pairs(M.disabled) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			for _, line in pairs(disabled_signs(bufnr)) do
				if M.enable_at(bufnr, line) then
					count = count + 1
				end
			end
		end
	end

	M.save_breakpoints()
	vim.notify("Enabled " .. count .. " breakpoint(s)", vim.log.levels.INFO)
end

--- Removes every breakpoint, live and disabled.
function M.remove_all()
	local ok_dap, dap = pcall(require, "dap")
	if ok_dap then
		dap.clear_breakpoints()
	end

	vim.fn.sign_unplace(M.settings.sign_group)
	M.disabled = {}
	M.save_breakpoints()
	vim.notify("Removed all breakpoints", vim.log.levels.INFO)
end

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

--- Project root for a buffer, shared with the task runner so both agree.
--- @param bufnr integer|nil
--- @return string root
function M.get_project_root(bufnr)
	local ok, tasks = pcall(require, "plugins.krs.tasks")
	if ok and tasks.get_project_root then
		return tasks.get_project_root()
	end
	return path.buffer_dir(bufnr or vim.api.nvim_get_current_buf())
end

--- Resolves `breakpoints.json` for a project.
--- @param root string|nil Project root.
--- @return string filepath
function M.get_breakpoints_filepath(root)
	return (project.config_path(M.settings.config_file, root or M.get_project_root()))
end

--- Path of a buffer relative to the project root, or its absolute path when the
--- file lives outside the project. This is the key used inside the JSON file.
---
--- @param buf_name string Absolute buffer name.
--- @param root string Project root.
--- @return string key
local function storage_key(buf_name, root)
	local normalized = path.normalize(vim.fs.normalize(buf_name))
	return path.relative_to(normalized, path.normalize(vim.fs.normalize(root))) or normalized
end

--- Collects live and disabled breakpoints, keyed by buffer.
--- @return table<integer,table[]> entries_by_buf
local function collect_entries()
	local entries_by_buf = {}

	local ok_dap, dap_bp = pcall(require, "dap.breakpoints")
	if ok_dap then
		for bufnr, bps in pairs(dap_bp.get()) do
			entries_by_buf[bufnr] = entries_by_buf[bufnr] or {}
			for _, bp in ipairs(bps) do
				table.insert(entries_by_buf[bufnr], {
					line = bp.line,
					condition = bp.condition,
					hit_condition = bp.hitCondition,
					log_message = bp.logMessage,
					enabled = true,
				})
			end
		end
	end

	for bufnr, opts_by_sign in pairs(M.disabled) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			entries_by_buf[bufnr] = entries_by_buf[bufnr] or {}
			for sign_id, lnum in pairs(disabled_signs(bufnr)) do
				local opts = opts_by_sign[sign_id] or {}
				table.insert(entries_by_buf[bufnr], {
					line = lnum,
					condition = opts.condition,
					hit_condition = opts.hit_condition,
					log_message = opts.log_message,
					enabled = false,
				})
			end
		end
	end

	return entries_by_buf
end

local _saved_cache = {}

--- Writes every breakpoint of the project to disk.
--- @param root string|nil Project root.
function M.save_breakpoints(root)
	root = root or M.get_project_root()
	if not pcall(require, "dap.breakpoints") then
		return
	end

	local data = { breakpoints = {} }
	for bufnr, entries in pairs(collect_entries()) do
		if vim.api.nvim_buf_is_valid(bufnr) and #entries > 0 then
			local buf_name = vim.api.nvim_buf_get_name(bufnr)
			if buf_name ~= "" then
				data.breakpoints[storage_key(buf_name, root)] = entries
			end
		end
	end

	local filepath = M.get_breakpoints_filepath(root)

	-- Don't create a .krsnvim/ in every project just to record "no breakpoints".
	-- An existing file is still rewritten, so clearing every breakpoint persists.
	if vim.tbl_isempty(data.breakpoints) and not path.is_file(filepath) then
		return
	end

	store.save(filepath, data)
	_saved_cache[root] = data.breakpoints
end

--- Reads the saved breakpoint map for a project.
--- @param root string Project root.
--- @return table|nil breakpoints Keyed by stored path, or nil when absent/invalid.
local function read_saved(root)
	if _saved_cache[root] ~= nil then
		return _saved_cache[root]
	end
	local data = store.load(M.get_breakpoints_filepath(root), nil)
	if type(data) ~= "table" or type(data.breakpoints) ~= "table" then
		_saved_cache[root] = nil
		return nil
	end
	_saved_cache[root] = data.breakpoints
	return data.breakpoints
end

--- Restores the saved breakpoints of ONE concrete buffer.
---
--- Buffer-scoped on purpose: an older version looked every saved path up with
--- `bufnr(path, true)`, which on Windows creates a second, forward-slash buffer
--- that is not the one on screen -- so the signs landed nowhere -- and re-added the
--- same breakpoints on every BufReadPost, stacking duplicates.
---
--- @param bufnr integer Buffer to restore into.
--- @param root string|nil Project root.
function M.restore_for_buffer(bufnr, root)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if buf_name == "" then
		return
	end

	root = root or M.get_project_root(bufnr)
	local saved = read_saved(root)
	if not saved then
		return
	end

	local ok_dap, dap_bp = pcall(require, "dap.breakpoints")
	if not ok_dap then
		return
	end

	local key = storage_key(buf_name, root)
	local bps
	for saved_path, saved_bps in pairs(saved) do
		if path.equals(saved_path, key) or saved_path:gsub("\\", "/"):lower() == key:lower() then
			bps = saved_bps
			break
		end
	end
	if not bps then
		return
	end

	-- Lines that already carry a breakpoint are skipped, so restoring twice does
	-- not stack duplicates.
	local existing = {}
	for _, bp in ipairs((dap_bp.get(bufnr) or {})[bufnr] or {}) do
		existing[bp.line] = true
	end
	for _, lnum in pairs(disabled_signs(bufnr)) do
		existing[lnum] = true
	end

	for _, bp in ipairs(bps) do
		if not existing[bp.line] then
			local opts = {
				condition = bp.condition,
				hit_condition = bp.hit_condition,
				log_message = bp.log_message,
			}
			if bp.enabled == false then
				place_disabled(bufnr, bp.line, opts)
			else
				dap_bp.set(opts, bufnr, bp.line)
			end
		end
	end
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Defines the disabled sign, the user commands, and the autocmds that keep the
--- file in sync (on open, when a debug session ends, and before quitting).
function M.setup()
	local group = vim.api.nvim_create_augroup("KrsDapBreakpoints", { clear = true })

	vim.api.nvim_set_hl(0, M.settings.sign_name, { fg = M.settings.sign_color, default = true })
	vim.fn.sign_define(M.settings.sign_name, {
		text = M.settings.sign_text,
		texthl = M.settings.sign_name,
		linehl = "",
		numhl = "",
	})

	local commands = {
		DapBreakpointToggleEnabled = { M.toggle_enabled, "Enable/disable the breakpoint under the cursor" },
		DapBreakpointsEnableAll = { M.enable_all, "Enable all disabled breakpoints" },
		DapBreakpointsDisableAll = { M.disable_all, "Disable all breakpoints (keeps them)" },
		DapBreakpointsRemoveAll = { M.remove_all, "Remove all breakpoints" },
	}
	for name, spec in pairs(commands) do
		vim.api.nvim_create_user_command(name, function()
			spec[1]()
		end, { desc = spec[2] })
	end

	-- Files passed on the command line are read before this spec runs, so their
	-- BufReadPost is already gone. Catch them here.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			vim.defer_fn(function()
				M.restore_for_buffer(bufnr)
			end, M.settings.startup_restore_delay_ms)
		end
	end

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
		group = group,
		callback = function(args)
			vim.defer_fn(function()
				M.restore_for_buffer(args.buf)
			end, M.settings.restore_delay_ms)
		end,
	})

	local function attach_dap_listeners()
		if package.loaded["dap"] then
			local dap = require("dap")
			for _, event in ipairs({ "event_terminated", "event_exited" }) do
				dap.listeners.after[event]["krs_breakpoints"] = function()
					M.save_breakpoints()
				end
			end
		end
	end
	attach_dap_listeners()

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.save_breakpoints(M.get_project_root())
		end,
	})
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.DapBreakpoints = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_dap_breakpoints",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = false,
	config = M.setup,
}, { __index = M })
