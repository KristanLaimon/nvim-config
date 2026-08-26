-- ============================================================================
-- KRS PLUGIN: Caps Lock Warning -- toast notification on active Caps Lock.
-- ============================================================================
-- WHAT IT DOES
--   Detects when Caps Lock ("Bloq Mayús") is active while navigating menus,
--   neo-tree, floating windows, or editor buffers. If Caps Lock remains ON for
--   ~3 seconds (configurable `delay_ms`), a toast notification is displayed via
--   `vim.notify` to alert the user that keyboard shortcuts may fail.
--
-- HOW IT WORKS
--   * State queries go through lua/krs/core/os/shared.lua, which on Windows uses
--     LuaJIT FFI with `user32.dll` (`GetKeyState(0x14)`) for zero-overhead, 0ms
--     latency; no other OS has an implementation yet (see that file for why).
--   * Uses a focus-aware libuv timer and autocmds (`CursorHold`, `WinEnter`, `BufEnter`,
--     `ModeChanged`) to check state without background CPU waste when unfocused.
--   * Throttles notifications so only one toast is shown per Caps Lock session.
--   * Automatically resets state when Caps Lock is toggled OFF.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Duration in milliseconds Caps Lock must remain ON before triggering toast.
	delay_ms = 3000,

	--- Background timer polling interval in milliseconds while focused.
	poll_interval_ms = 500,

	--- Title for the toast notification.
	notification_title = "Bloq Mayús / Caps Lock",

	--- Message for the toast notification.
	notification_msg = "⚠️ Bloq Mayús (Caps Lock) está activado. Los atajos de teclado pueden fallar.",

	--- Level used for vim.notify.
	notification_level = vim.log.levels.WARN,

	--- Events that trigger an immediate check.
	check_events = { "FocusGained", "CursorHold", "CursorHoldI", "WinEnter", "BufEnter", "ModeChanged" },
}

-- ============================================================================
-- STATE
-- ============================================================================

local uv = vim.uv or vim.loop
local is_focused = true
local check_timer = nil
local caps_on_since = nil
local notified = false

-- ============================================================================
-- API
-- ============================================================================

--- Checks whether Caps Lock is toggled ON.
--- @return boolean
function M.is_caps_lock_on()
	return require("krs.core.os.shared").is_caps_lock_on()
end

--- Identifies the user's current context name (e.g., Neo-tree, Menu, Telescope).
--- @return string|nil context_name
function M.get_current_context_name()
	local ft = vim.bo.filetype
	if ft == "neo-tree" then
		return "Neo-tree"
	elseif ft == "TelescopePrompt" then
		return "Telescope"
	elseif ft == "dashboard" or ft == "alpha" then
		return "Menu Principal"
	end

	local win_cfg = vim.api.nvim_win_get_config(0)
	if win_cfg and win_cfg.relative and win_cfg.relative ~= "" then
		return "Menu Flotante"
	end

	return "Editor"
end

--- Resets the tracking state (e.g. when Caps Lock is turned off).
function M.reset_state()
	caps_on_since = nil
	notified = false
end

--- Sets focus status (primarily for unit tests and Focus autocmds).
--- @param focused boolean
function M.set_focused(focused)
	is_focused = focused
end

--- Sets internal caps_on_since timestamp (for tests).
--- @param timestamp number|nil
function M.set_caps_on_since(timestamp)
	caps_on_since = timestamp
end

--- Returns current tracking status.
--- @return table
function M.get_state()
	return {
		is_focused = is_focused,
		caps_on_since = caps_on_since,
		notified = notified,
		is_on = M.is_caps_lock_on(),
	}
end

--- Main state evaluation function called periodically and on events.
--- @param force boolean|nil Bypass focus check (used for testing).
function M.check(force)
	if not is_focused and not force then
		return
	end

	local caps_on = M.is_caps_lock_on()
	local now = uv.now()

	if caps_on then
		if not caps_on_since then
			caps_on_since = now
		end

		local elapsed = now - caps_on_since
		if elapsed >= M.settings.delay_ms and not notified then
			notified = true
			local ctx = M.get_current_context_name()
			local msg = M.settings.notification_msg
			if ctx and ctx ~= "" and ctx ~= "Editor" then
				msg = string.format(
					"⚠️ Bloq Mayús (Caps Lock) está activado en %s. Los atajos de teclado pueden fallar.",
					ctx
				)
			end

			vim.schedule(function()
				vim.notify(msg, M.settings.notification_level, {
					title = M.settings.notification_title,
					id = "caps_lock_warning",
				})
			end)
		end
	else
		M.reset_state()
	end
end

-- ============================================================================
-- TIMER LIFECYCLE
-- ============================================================================

local function stop_timer()
	if check_timer then
		check_timer:stop()
	end
end

local function start_timer()
	if not is_focused then
		return
	end

	check_timer = check_timer or uv.new_timer()
	check_timer:stop()
	check_timer:start(
		M.settings.poll_interval_ms,
		M.settings.poll_interval_ms,
		vim.schedule_wrap(function()
			if not is_focused then
				stop_timer()
				return
			end
			M.check()
		end)
	)
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Wires focus-aware timers, autocmds, and user commands.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup("KRS_CapsLockWarning", { clear = true })

	vim.api.nvim_create_autocmd("FocusGained", {
		group = group,
		callback = function()
			is_focused = true
			M.check()
			start_timer()
		end,
	})

	vim.api.nvim_create_autocmd("FocusLost", {
		group = group,
		callback = function()
			is_focused = false
			stop_timer()
			M.reset_state()
		end,
	})

	vim.api.nvim_create_autocmd(M.settings.check_events, {
		group = group,
		callback = function()
			if is_focused then
				M.check()
			end
		end,
	})

	vim.api.nvim_create_user_command("CapsLockCheck", function()
		local is_on = M.is_caps_lock_on()
		local status = is_on and "ACTIVADO ⚠️" or "Desactivado ✓"
		vim.notify("Estado de Bloq Mayús: " .. status, vim.log.levels.INFO, {
			title = M.settings.notification_title,
		})
	end, { desc = "Check Caps Lock status and notify" })

	M.check()
	start_timer()
end

_G.CapsLock = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

M.name = "krs_caps_lock"
M.dir = require("krs.core.lazyspec").for_module()
M.event = "VeryLazy"
M.cmd = "CapsLockCheck"
M.config = M.setup

return M
