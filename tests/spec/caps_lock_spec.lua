-- ============================================================================
-- tests/spec/caps_lock_spec.lua -- Caps Lock warning plugin tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach
local caps_lock = require("plugins.krs.editor.caps_lock")

local scratch_buffers = {}

--- Opens a scratch buffer with the given filetype and focuses it.
--- @param filetype string
local function open_buffer(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = filetype
	table.insert(scratch_buffers, buf)
	return buf
end

describe("plugins.krs.editor.caps_lock context detection", function()
	afterEach(function()
		for _, buf in ipairs(scratch_buffers) do
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
		scratch_buffers = {}
		caps_lock.reset_state()
	end)

	it("detects Neo-tree filetype context", function()
		open_buffer("neo-tree")
		expect(caps_lock.get_current_context_name()).toBe("Neo-tree")
	end)

	it("detects Telescope context", function()
		open_buffer("TelescopePrompt")
		expect(caps_lock.get_current_context_name()).toBe("Telescope")
	end)

	it("detects dashboard main menu context", function()
		open_buffer("dashboard")
		expect(caps_lock.get_current_context_name()).toBe("Menu Principal")
	end)

	it("falls back to Editor context for standard buffers", function()
		open_buffer("lua")
		expect(caps_lock.get_current_context_name()).toBe("Editor")
	end)
end)

describe("plugins.krs.editor.caps_lock state management and notification trigger", function()
	local original_is_caps_on = caps_lock.is_caps_lock_on
	local original_notify = vim.notify
	local notified_messages = {}

	afterEach(function()
		caps_lock.is_caps_lock_on = original_is_caps_on
		vim.notify = original_notify
		notified_messages = {}
		caps_lock.set_focused(true)
		caps_lock.reset_state()
	end)

	it("returns a boolean for is_caps_lock_on", function()
		local status = caps_lock.is_caps_lock_on()
		expect(type(status)).toBe("boolean")
	end)

	it("resets tracking state correctly", function()
		caps_lock.reset_state()
		local st = caps_lock.get_state()
		expect(st.caps_on_since).toBeNil()
		expect(st.notified).toBe(false)
	end)

	it("registers user command CapsLockCheck", function()
		caps_lock.setup()
		expect(vim.fn.exists(":CapsLockCheck")).toBe(2)
	end)

	it("does not notify before 3 seconds elapse", function()
		caps_lock.is_caps_lock_on = function()
			return true
		end
		vim.notify = function(msg)
			table.insert(notified_messages, msg)
		end

		caps_lock.check(true)
		local st = caps_lock.get_state()

		expect(st.caps_on_since).toBeDefined()
		expect(st.notified).toBe(false)
		expect(#notified_messages).toBe(0)
	end)

	it("notifies when Caps Lock has been active for 3 seconds", function()
		caps_lock.is_caps_lock_on = function()
			return true
		end

		vim.notify = function(msg, level, opts)
			table.insert(notified_messages, { msg = msg, level = level, opts = opts })
		end

		open_buffer("neo-tree")
		caps_lock.check(true)

		-- Simulate 3.5 seconds elapsed (3500ms)
		local uv = vim.uv or vim.loop
		local now = uv.now()
		caps_lock.set_caps_on_since(now - 3500)

		caps_lock.check(true)
		vim.wait(50)

		local state = caps_lock.get_state()
		expect(state.notified).toBe(true)
		expect(#notified_messages).toBe(1)
		expect(notified_messages[1].msg:len() > 0).toBe(true)
	end)

	it("resets state when Caps Lock turns off", function()
		local caps_status = true
		caps_lock.is_caps_lock_on = function()
			return caps_status
		end

		caps_lock.check(true)
		expect(caps_lock.get_state().caps_on_since).toBeDefined()

		caps_status = false
		caps_lock.check(true)
		expect(caps_lock.get_state().caps_on_since).toBeNil()
		expect(caps_lock.get_state().notified).toBe(false)
	end)
end)
