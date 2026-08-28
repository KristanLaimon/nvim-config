-- ============================================================================
-- KEYMAPS: Debugging (DAP).
-- ============================================================================
-- KEYS
--   <A-b>   Toggle breakpoint            <F5>   Start / continue
--   <F10>   Step over                    <F11>  Step into
--   <F12>   Step out                     <S-F5> Terminate
--   <leader>du  Toggle the debugger UI
--   <A-h> / <C-S-h>  Enable/disable the breakpoint under the cursor
--   <C-S-j> Toggle the repl (bound in search.lua, implemented here)
--
-- WHY <A-h> IS BOUND ON VimEnter
--   Both <A-h> (cycle buffers) and <C-S-h> (split left, claimed by telescope's
--   lazy `keys` spec) already do something. Binding on VimEnter makes this the
--   last writer, and the previous mapping is REPLAYED whenever the cursor line
--   has no breakpoint to flip -- so nothing is actually lost.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	keys = {
		toggle_breakpoint = "<A-b>",
		continue = "<F5>",
		step_over = "<F10>",
		step_into = "<F11>",
		step_out = "<F12>",
		terminate = "<S-F5>",
		toggle_ui = nil,
		--- Flip a breakpoint between enabled and disabled, keeping the line.
		toggle_enabled = { "<A-h>", "<M-h>", "<C-S-h>", "<C-S-H>" },
	},

	--- dapui layout holding { repl, console }; layout 2 in the dap.lua setup.
	repl_layout = 2,

	--- Delay before persisting breakpoints, so nvim-dap has applied the change.
	save_delay_ms = 100,
}

-- ============================================================================
-- ACTIONS
-- ============================================================================

--- Calls `method` on nvim-dap when it is installed.
--- @param method string Function name on the `dap` module.
--- @return function handler
local function dap_action(method)
	return function()
		local ok, dap = pcall(require, "dap")
		if ok then
			-- Called with no arguments: nvim-dap reads an options TABLE here, so
			-- passing the module itself would be interpreted as options.
			dap[method]()
		end
	end
end

--- Toggles a breakpoint and persists the project's breakpoint file.
local function toggle_breakpoint()
	local ok, dap = pcall(require, "dap")
	if not ok then
		return
	end

	dap.toggle_breakpoint()
	vim.defer_fn(function()
		pcall(function()
			require("plugins.krs.dev.dap_breakpoints").save_breakpoints()
		end)
	end, M.settings.save_delay_ms)
end

--- Terminates the session and closes the debugger UI with it.
local function terminate()
	local ok, dap = pcall(require, "dap")
	if not ok then
		return
	end

	dap.terminate()
	pcall(function()
		require("dapui").close()
	end)
end

--- Toggles the DAP repl ("immediate window") during a session:
--- hidden -> open and focus, visible -> focus, already focused -> close.
---
--- @return boolean handled False when there is no session, so the caller can do
---   whatever the key normally does.
function M.toggle_repl()
	local dap_ok, dap = pcall(require, "dap")
	if not dap_ok or not dap.session() then
		return false
	end

	local dapui_ok, dapui = pcall(require, "dapui")
	if not dapui_ok then
		return false
	end

	local repl_win
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "dap-repl" then
			repl_win = win
			break
		end
	end

	if repl_win == vim.api.nvim_get_current_win() then
		pcall(dapui.close, { layout = M.settings.repl_layout })
	elseif repl_win then
		vim.api.nvim_set_current_win(repl_win)
	else
		pcall(dapui.open, { layout = M.settings.repl_layout })
		-- The window only exists after dapui has drawn it.
		vim.schedule(function()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "dap-repl" then
					vim.api.nvim_set_current_win(win)
					return
				end
			end
		end)
	end

	return true
end

-- ============================================================================
-- MAPPINGS
-- ============================================================================

local function opts(desc)
	return { noremap = true, silent = true, desc = desc }
end

local bindings = {
	{ key = M.settings.keys.toggle_breakpoint, fn = toggle_breakpoint, desc = "Toggle Breakpoint" },
	{ key = M.settings.keys.continue, fn = dap_action("continue"), desc = "Start/Continue Debugging" },
	{ key = M.settings.keys.step_over, fn = dap_action("step_over"), desc = "Step Over" },
	{ key = M.settings.keys.step_into, fn = dap_action("step_into"), desc = "Step Into" },
	{ key = M.settings.keys.step_out, fn = dap_action("step_out"), desc = "Step Out" },
	{ key = M.settings.keys.terminate, fn = terminate, desc = "Terminate Debugger" },
}

for _, binding in ipairs(bindings) do
	vim.keymap.set({ "n", "i", "v" }, binding.key, binding.fn, opts(binding.desc))
end

if M.settings.keys.toggle_ui then
	vim.keymap.set("n", M.settings.keys.toggle_ui, function()
		local ok, dapui = pcall(require, "dapui")
		if ok then
			dapui.toggle()
		end
	end, opts("Toggle Debugger UI"))
end

-- See the header: bound late, and falls through to whatever was bound before.
vim.api.nvim_create_autocmd("VimEnter", {
	group = vim.api.nvim_create_augroup("KrsDapBreakpointEnableKeys", { clear = true }),
	callback = function()
		for _, key in ipairs(M.settings.keys.toggle_enabled) do
			for _, mode in ipairs({ "n", "i", "v" }) do
				local previous = vim.fn.maparg(key, mode, false, true)

				--- Replays the mapping this one replaced.
				local function fallback()
					if type(previous) ~= "table" then
						return
					end
					if previous.callback then
						previous.callback()
					elseif previous.rhs and previous.rhs ~= "" then
						local keys = vim.api.nvim_replace_termcodes(previous.rhs, true, true, true)
						vim.api.nvim_feedkeys(keys, previous.noremap == 1 and "n" or "m", false)
					end
				end

				vim.keymap.set(mode, key, function()
					local ok, breakpoints = pcall(require, "plugins.krs.dev.dap_breakpoints")
					if ok and breakpoints.toggle_enabled({ silent = true }) then
						return
					end
					fallback()
				end, opts("Enable/Disable Breakpoint"))
			end
		end
	end,
})

return M
