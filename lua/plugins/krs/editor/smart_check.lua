-- ============================================================================
-- KRS PLUGIN: Smart File Check -- auto-reload and deleted-file detection.
-- ============================================================================
-- WHAT IT DOES
--   Keeps buffers in sync with the disk (`checktime`) and tracks which files have
--   been deleted underneath you, so the bufferline can mark them.
--
-- WHY IT IS BUILT THIS WAY (this is a hot path -- it runs forever)
--   * State is CACHED on the buffer (`b:_krs_is_deleted`), so rendering a tabline
--     performs zero disk stats.
--   * The timer STOPS on FocusLost: no CPU or disk I/O while you are in another
--     application.
--   * `checktime` is throttled (`M.settings.throttle_ms`) and skipped entirely
--     while the command line or a terminal has focus, where it would interrupt.
--
-- PUBLIC GLOBAL
--   `_G.Is_File_Deleted(bufnr)` -- used by the bufferline; keep the name.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Shortest gap between two disk checks, in milliseconds.
	throttle_ms = 1200,

	--- Background timer interval, in milliseconds. Only runs while focused.
	poll_interval_ms = 2000,

	--- Buffer names matching any of these are virtual, not files on disk.
	virtual_patterns = { "^%a[%a%d+.-]+://", "^node:" },

	--- Events that trigger a throttled check.
	check_events = { "BufEnter", "BufWritePost", "CursorHold", "CursorHoldI", "WinEnter", "TermClose" },
}

-- ============================================================================
-- STATE
-- ============================================================================

local uv = vim.uv or vim.loop
local is_focused = true
local check_timer = nil
local last_check_time = 0

-- ============================================================================
-- BUFFER STATE
-- ============================================================================

--- True when the buffer is a real file on disk (not a terminal, not a URL).
--- @param bufnr integer
--- @return boolean
local function is_disk_file(bufnr)
	if vim.bo[bufnr].buftype ~= "" then
		return false
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return false
	end
	for _, pattern in ipairs(M.settings.virtual_patterns) do
		if name:match(pattern) then
			return false
		end
	end
	return true
end

--- True while the user is in the command line or a terminal, where a `checktime`
--- would steal focus or interrupt typing.
--- @return boolean
local function in_blocking_mode()
	local mode = vim.api.nvim_get_mode().mode
	return mode:find("^c") ~= nil or mode:find("^t") ~= nil
end

--- Refreshes the cached deleted-state of one buffer, redrawing the tabline when
--- it changed.
---
--- @param bufnr integer
--- @return boolean is_deleted
function M.update_buf_state(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	if not is_disk_file(bufnr) then
		vim.b[bufnr]._krs_is_deleted = false
		return false
	end

	local is_deleted = uv.fs_stat(vim.api.nvim_buf_get_name(bufnr)) == nil
	local previous = vim.b[bufnr]._krs_is_deleted
	vim.b[bufnr]._krs_is_deleted = is_deleted

	if previous ~= nil and previous ~= is_deleted then
		pcall(vim.cmd, "redrawtabline")
	end
	return is_deleted
end

--- Cached "has this file been deleted?" lookup. Zero disk I/O on a warm cache,
--- which is what makes it safe to call from tabline rendering.
---
--- @param bufnr integer|nil Defaults to the current buffer.
--- @return boolean is_deleted
_G.Is_File_Deleted = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local cached = vim.b[bufnr]._krs_is_deleted
	if cached ~= nil then
		return cached
	end
	return M.update_buf_state(bufnr)
end

--- Re-checks every listed file buffer, then runs `checktime` once.
--- @param force boolean|nil Ignore the throttle window.
function M.check_all_buffers(force)
	local now = uv.now()
	if not force and (now - last_check_time) < M.settings.throttle_ms then
		return
	end
	last_check_time = now

	local file_buffers = 0
	local state_changed = false

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1 and is_disk_file(buf) then
			file_buffers = file_buffers + 1
			local previous = vim.b[buf]._krs_is_deleted
			local current = M.update_buf_state(buf)
			if previous ~= nil and previous ~= current then
				state_changed = true
			end
		end
	end

	-- `checktime` on an editor with no file buffers is pure overhead.
	if file_buffers > 0 then
		pcall(vim.cmd, "checktime")
	end
	if state_changed then
		pcall(vim.cmd, "redrawtabline")
	end
end

--- Returns true if running on a desktop platform (Windows, macOS, Linux, WSL).
local function is_desktop_env()
	local env_ok, env_mod = pcall(require, "krs.core.environment")
	if env_ok and env_mod.detect then
		local env = env_mod.detect()
		return not (env.is_mobile or env.is_termux or env.is_proot)
	end
	return true
end

-- ============================================================================
-- TIMER LIFECYCLE
-- ============================================================================

local function stop_timer()
	if check_timer then
		check_timer:stop()
	end
end

--- Starts (or restarts) the polling timer. Keeps running on desktop for live side-by-side edits.
local function start_timer()
	local is_desktop = is_desktop_env()
	if not is_focused and not is_desktop then
		return
	end

	check_timer = check_timer or uv.new_timer()
	check_timer:stop()
	check_timer:start(
		M.settings.poll_interval_ms,
		M.settings.poll_interval_ms,
		vim.schedule_wrap(function()
			if not is_focused and not is_desktop_env() then
				stop_timer()
				return
			end
			if not in_blocking_mode() then
				M.check_all_buffers(false)
			end
		end)
	)
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Enables `autoread`, wires the focus-aware timer and the event checks.
function M.setup()
	vim.opt.autoread = true

	local group = vim.api.nvim_create_augroup("KRSSmartCheckAutoRead", { clear = true })

	vim.api.nvim_create_autocmd("FocusGained", {
		group = group,
		callback = function()
			is_focused = true
			M.check_all_buffers(true)
			start_timer()
		end,
	})

	vim.api.nvim_create_autocmd("FocusLost", {
		group = group,
		callback = function()
			is_focused = false
			if not is_desktop_env() then
				stop_timer()
			end
		end,
	})

	vim.api.nvim_create_autocmd(M.settings.check_events, {
		group = group,
		callback = function(ev)
			if not in_blocking_mode() then
				local force = (ev.event == "BufEnter" or ev.event == "WinEnter")
				M.check_all_buffers(force)
			end
		end,
	})

	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		group = group,
		callback = function(ev)
			pcall(vim.cmd, "redrawtabline")
			if ev and ev.buf and vim.api.nvim_buf_is_valid(ev.buf) then
				local name = vim.api.nvim_buf_get_name(ev.buf)
				if name ~= "" then
					local filename = vim.fn.fnamemodify(name, ":t")
					vim.notify("🔄 Reloaded externally modified file: " .. filename, vim.log.levels.INFO, {
						title = "External File Change",
					})
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("FileChangedShell", {
		group = group,
		callback = function(ev)
			if ev and ev.buf and vim.api.nvim_buf_is_valid(ev.buf) then
				if vim.bo[ev.buf].modified then
					local name = vim.api.nvim_buf_get_name(ev.buf)
					local filename = vim.fn.fnamemodify(name, ":t")
					vim.notify(
						"⚠️ File changed on disk (" .. filename .. "), but you have unsaved changes in Neovim!",
						vim.log.levels.WARN,
						{ title = "External Edit Conflict" }
					)
				end
			end
		end,
	})

	local function run_manual_check()
		M.check_all_buffers(true)
		vim.notify("🔄 Checked for external file changes across all open buffers.", vim.log.levels.INFO, {
			title = "Smart File Check",
		})
	end

	vim.api.nvim_create_user_command(
		"SmartCheck",
		run_manual_check,
		{ desc = "Check for external file changes across open buffers" }
	)
	vim.api.nvim_create_user_command(
		"KrsSmartCheck",
		run_manual_check,
		{ desc = "Check for external file changes across open buffers" }
	)

	M.check_all_buffers(true)
	start_timer()
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.SmartCheck = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_smart_check",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = false,
	cmd = { "SmartCheck", "KrsSmartCheck" },
	config = M.setup,
}, { __index = M })
