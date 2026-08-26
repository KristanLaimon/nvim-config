-- ============================================================================
-- KRS PLUGIN: Sneak-Peek Project Modal -- preview a project in a 90% float.
-- ============================================================================
-- WHAT IT DOES
--   1. Triggered via `<C-S-o>` (only `<C-S-o>`).
--   2. Prompts to pick a folder using the Telescope folder browser.
--   3. Opens that folder in a centered floating modal window occupying 90% of app
--      width and 90% of app height.
--   4. Spawns a nested sub-Neovim process (`nvim <folder>`) in a terminal buffer.
--   5. Keeps the original CWD project and open buffers completely intact underneath.
--   6. Exiting the sneak peek (via `:q` inside sub-nvim or `<C-S-o>`) closes the
--      modal, kills the sub-nvim process AND all attached child LSP processes
--      (`*.exe` process tree termination on Windows), and returns focus seamlessly.
-- ============================================================================

local ui = require("krs.core.ui")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local is_mobile_sp = false
local env_ok, env_mod = pcall(require, "krs.core.environment")
if env_ok then
	local env = env_mod.detect()
	is_mobile_sp = env.is_mobile or env.is_termux or env.is_proot
else
	is_mobile_sp = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
end

M.settings = {
	--- Width as fraction of editor (0.90 = 90%).
	width = 0.90,

	--- Height as fraction of editor (0.90 = 90%).
	height = 0.90,

	--- Float window border style.
	border = "rounded",

	--- Keymaps to toggle / close sneak-peek.
	keys = {
		toggle = is_mobile_sp and { "<C-S-y>", "<C-S-Y>", "<C-Y>", "<C-y>" } or { "<C-S-y>", "<C-S-Y>" },
	},
}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
	win = nil,
	buf = nil,
	job_id = nil,
	child_pid = nil,
	target_dir = nil,
	active = false,
}

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Forcefully kills process tree on Windows or sends kill signal on Unix.
--- @param pid integer|nil Process ID of sub-nvim.
--- @param job_id integer|nil Job ID of termopen.
local function kill_process_tree(pid, job_id)
	if job_id then
		pcall(vim.fn.jobstop, job_id)
	end
	if pid and type(pid) == "number" and pid > 0 then
		if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 or os.getenv("OS") == "Windows_NT" then
			-- Kill the process and ALL its descendant processes (like lsp.exe, language servers, etc.)
			vim.fn.system(string.format("taskkill /F /T /PID %d 2>/dev/null", pid))
		else
			vim.fn.system(string.format("kill -9 -%d 2>/dev/null || kill -9 %d 2>/dev/null", pid, pid))
		end
	end
end

-- ============================================================================
-- API
-- ============================================================================

--- Closes and cleans up the active sneak-peek session.
function M.cleanup()
	if not state.active and not state.win then
		return
	end

	state.active = false

	-- Kill job and child process tree (LSP executables, sub-nvim, etc.)
	if state.child_pid or state.job_id then
		kill_process_tree(state.child_pid, state.job_id)
		state.child_pid = nil
		state.job_id = nil
	end

	-- Close window if valid
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
		state.win = nil
	end

	-- Delete buffer if valid
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
		state.buf = nil
	end

	state.target_dir = nil
end

--- Returns whether a sneak-peek modal is currently open.
--- @return boolean
function M.is_open()
	return state.active and state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Opens a folder in the 90%x90% sneak-peek modal window.
--- @param target_dir string Directory path.
function M.open(target_dir)
	if not target_dir or target_dir == "" then
		return
	end

	target_dir = vim.fn.expand(target_dir)
	if vim.fn.isdirectory(target_dir) == 0 then
		vim.notify("📁 Directory does not exist:\n" .. target_dir, vim.log.levels.ERROR, { title = "Sneak Peek" })
		return
	end

	-- Close any existing sneak-peek first
	if state.active then
		M.cleanup()
	end

	-- Calculate 90% width and 90% height
	local cols = vim.o.columns or 80
	local lines = vim.o.lines or 24
	local width = math.max(math.floor(cols * M.settings.width), 1)
	local height = math.max(math.floor(lines * M.settings.height), 1)
	local row, col = ui.center(width, height)

	-- Create scratch buffer for terminal
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local folder_name = vim.fn.fnamemodify(target_dir, ":t")
	if folder_name == "" then
		folder_name = target_dir
	end

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = M.settings.border,
		title = " 🔍 Sneak-Peek Project: " .. folder_name .. " (Press :q to exit) ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, win_opts)

	state.win = win
	state.buf = buf
	state.target_dir = target_dir
	state.active = true

	-- Determine nvim executable
	local nvim_bin = vim.v.progpath
	if not nvim_bin or nvim_bin == "" then
		nvim_bin = "nvim"
	end

	-- Set environment without NVIM variable to prevent nested nvim RPC confusion
	local env = vim.fn.environ()
	env["NVIM"] = nil

	vim.api.nvim_set_current_win(win)

	local job_id = vim.fn.termopen({ nvim_bin, target_dir }, {
		cwd = target_dir,
		env = env,
		on_exit = function()
			vim.schedule(function()
				M.cleanup()
			end)
		end,
	})

	state.job_id = job_id
	if job_id and job_id > 0 then
		local ok, pid = pcall(vim.fn.jobpid, job_id)
		if ok then
			state.child_pid = pid
		end
	end

	-- Bind <C-S-o> in buffer modes to close modal
	for _, key in ipairs(M.settings.keys.toggle) do
		vim.keymap.set({ "t", "n", "i", "v" }, key, function()
			M.cleanup()
		end, { buffer = buf, silent = true, noremap = true, desc = "Close Sneak Peek Modal" })
	end

	-- Automatically enter insert mode in terminal
	vim.cmd("startinsert")

	vim.notify("🔍 Opened sneak-peek project:\n" .. target_dir, vim.log.levels.INFO, { title = "Sneak Peek" })
end

--- Toggles off if open, or prompts to pick a folder to sneak peek.
function M.toggle_or_pick()
	if M.is_open() then
		M.cleanup()
		return
	end

	if _G.OpenFolderPicker then
		_G.OpenFolderPicker({ cwd = vim.fn.getcwd() }, function(selected_dir)
			M.open(selected_dir)
		end)
	else
		-- Fallback prompt if telescope folder picker is not initialized
		vim.ui.input({ prompt = "Sneak-Peek Folder Path: ", default = vim.fn.getcwd(), completion = "dir" }, function(input)
			if input and input ~= "" then
				M.open(input)
			end
		end)
	end
end

-- ============================================================================
-- SETUP & LAZY SPEC
-- ============================================================================

function M.setup()
	local group = vim.api.nvim_create_augroup("KRSSneakPeek", { clear = true })

	-- User commands
	vim.api.nvim_create_user_command("SneakPeek", function(opts)
		if opts.args and opts.args ~= "" then
			M.open(opts.args)
		else
			M.toggle_or_pick()
		end
	end, { nargs = "?", complete = "dir", desc = "Open a folder in a 90% sneak-peek project modal" })

	vim.api.nvim_create_user_command("SneakPeekClose", function()
		M.cleanup()
	end, { desc = "Close active sneak-peek project modal" })

	-- Clean up on editor leave
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.cleanup()
		end,
	})

	-- Keybindings
	local function from_any_mode(fn)
		return function()
			local mode = vim.fn.mode()
			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			fn()
		end
	end

	for _, key in ipairs(M.settings.keys.toggle) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.toggle_or_pick), {
			noremap = true,
			silent = true,
			desc = "Sneak-Peek Project Modal (90% Window)",
		})
	end
end

return setmetatable({
	name = "krs_sneak_peek",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "SneakPeek", "SneakPeekClose" },
	keys = is_mobile_sp and {
		{ "<C-S-y>", mode = { "n", "i" }, desc = "Sneak-Peek Project Modal" },
		{ "<C-Y>", mode = { "n", "i" }, desc = "Sneak-Peek Project Modal (Mobile)" },
	} or {
		{ "<C-S-y>", mode = { "n", "i" }, desc = "Sneak-Peek Project Modal" },
	},
	config = M.setup,
}, { __index = M })
