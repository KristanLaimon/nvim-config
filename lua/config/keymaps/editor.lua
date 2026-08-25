-- ============================================================================
-- KEYMAPS: Editor -- text, clipboard, windows, buffers.
-- ============================================================================
-- WHAT IS HERE
--   Leader, comment toggling, save, clipboard bridges, undo/redo, window
--   navigation and resizing, buffer cycling, closing things, and the file
--   explorer sidebar toggle.
--
-- WHY SO MANY ALIASES
--   `Ctrl+'` and friends arrive differently depending on keyboard layout (US,
--   US-International, ES, Latam dead keys) and terminal. The lists below bind
--   every form the same action, so the config feels identical everywhere.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local is_mobile_ed = false
local env_ok_ed, env_mod_ed = pcall(require, "krs.core.environment")
if env_ok_ed then
	local env = env_mod_ed.detect()
	is_mobile_ed = env.is_mobile or env.is_termux or env.is_proot
else
	is_mobile_ed = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
end

M.settings = {
	--- Space, as the prefix for every `<leader>` mapping.
	leader = " ",

	keys = {
		--- Toggle comment. One entry per keyboard layout that produces it.
		comment = { "<C-'>", "<C-S-'>", '<C-">', "<C-`>", "<C-~>", "<C-^>", "<C-acute>" },
		save = { "<C-s>", "<C-S>" },
		copy = { "<C-c>", "<C-S-c>" },
		paste = { "<C-v>", "<C-S-v>" },
		undo = "<C-z>",
		redo = { "<C-y>", "<C-S-z>" },
		--- Close the current buffer/split/tab, smartly (see buffer_cleaner).
		close = "<C-w>",
		--- Move focus between windows.
		window_left = "<C-h>",
		window_right = "<C-l>",
		window_up = {
			"<C-S-A-k>",
			"<C-A-S-k>",
			"<C-S-M-k>",
			"<C-M-S-k>",
			"<C-S-A-K>",
			"<C-A-S-K>",
			"<C-S-M-K>",
			"<C-M-S-K>",
		},
		window_down = "<C-j>",
		--- Cycle buffers.
		buffer_prev = { "<A-h>", "<M-h>", "<A-Left>", "<M-Left>" },
		buffer_next = { "<A-l>", "<M-l>", "<A-Right>", "<M-Right>" },
		--- Toggle the neo-tree sidebar.
		explorer = { "<C-S-Space>", "<C-e>", "<C-E>", "<leader>e", "<leader>fe" },
		--- Netrw-style directory listing, kept as an escape hatch.
		netrw = nil,
		--- Pin active code buffer tab (<C-A-p> / <C-p> on Desktop, <A-p> on Mobile).
		pin_tab = is_mobile_ed
				and { "<C-A-p>", "<C-A-P>", "<C-M-p>", "<C-M-P>", "<A-p>", "<M-p>", "<leader>pin", "<leader>bp" }
			or { "<C-A-p>", "<C-A-P>", "<C-M-p>", "<C-M-P>", "<C-p>", "<C-P>", "<A-p>", "<M-p>", "<leader>pin", "<leader>bp" },
		--- Toggle fold at cursor / selection (HTML tags, functions, scopes via Alt+Y).
		fold_toggle = { "<A-y>", "<A-Y>", "<M-y>", "<M-Y>" },
	},

	--- Window resize step, in cells.
	resize_step = 2,
}

-- ============================================================================
-- LEADER
-- ============================================================================

vim.g.mapleader = M.settings.leader

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Standard mapping options, with a description.
--- @param desc string
--- @return table opts
local function opts(desc)
	return { noremap = true, silent = true, desc = desc }
end

--- Feeds `keys` after leaving terminal mode, so a mapping bound in every mode
--- also works while a terminal has focus.
--- @param keys string Keys to feed (already in normal-mode form).
local function feed_from_any_mode(keys)
	return function()
		if vim.api.nvim_get_mode().mode == "t" then
			pcall(vim.cmd, "stopinsert")
			pcall(vim.cmd, "wincmd p")
		end
		vim.api.nvim_feedkeys(keys, "m", false)
	end
end

--- Pastes the OS clipboard into a terminal buffer (`"+`, falling back to `"*`).
local function paste_clipboard_to_terminal()
	local clip = vim.fn.getreg("+")
	if not clip or clip == "" then
		clip = vim.fn.getreg("*")
	end
	if clip and clip ~= "" then
		vim.api.nvim_paste(clip, true, -1)
	end
end

-- ============================================================================
-- MAPPINGS
-- ============================================================================

if M.settings.keys.netrw then
	vim.keymap.set("n", M.settings.keys.netrw, vim.cmd.Ex, opts("Open netrw directory listing"))
end

-- Comments: `gcc` for a line, `gc` for a selection, from any mode.
for _, key in ipairs(M.settings.keys.comment) do
	vim.keymap.set("n", key, feed_from_any_mode("gcc"), opts("Comment line"))
	vim.keymap.set("v", key, feed_from_any_mode("gc"), opts("Comment selection"))
	vim.keymap.set("i", key, function()
		vim.cmd("stopinsert")
		feed_from_any_mode("gcc")()
	end, opts("Comment line"))
	vim.keymap.set("t", key, feed_from_any_mode("gcc"), opts("Comment line from terminal"))
end

local save_keys = type(M.settings.keys.save) == "table" and M.settings.keys.save or { M.settings.keys.save }
for _, key in ipairs(save_keys) do
	vim.keymap.set({ "n", "v", "i" }, key, "<Cmd>w<CR>", opts("Save file"))
end

for _, key in ipairs(M.settings.keys.pin_tab) do
	vim.keymap.set({ "n", "v", "i" }, key, function()
		if vim.fn.mode() == "i" then
			pcall(vim.cmd, "stopinsert")
		end
		require("plugins.krs.pinned_tabs").toggle_pin()
	end, opts("Toggle pin tab (code buffer only)"))
end

for _, key in ipairs(M.settings.keys.fold_toggle or {}) do
	vim.keymap.set({ "n", "v", "i", "t" }, key, function()
		require("plugins.krs.folding").toggle_fold()
	end, opts("Toggle fold at cursor (HTML, functions, scopes)"))
end

-- Clipboard: the OS clipboard, not vim registers, because that is what the rest
-- of the desktop means by copy and paste.
for _, key in ipairs(M.settings.keys.copy) do
	vim.keymap.set("v", key, '"+y', opts("Copy to OS clipboard"))
end
vim.keymap.set({ "n", "v" }, "<C-v>", '"+p', opts("Paste from system clipboard"))
vim.keymap.set({ "i", "c" }, "<C-v>", "<C-r>+", opts("Paste from system clipboard"))
for _, key in ipairs(M.settings.keys.paste) do
	vim.keymap.set("t", key, paste_clipboard_to_terminal, opts("Paste OS clipboard into terminal"))
end

vim.keymap.set("n", M.settings.keys.undo, "u", opts("Undo"))
vim.keymap.set("v", M.settings.keys.undo, "<Esc>u", opts("Undo"))
vim.keymap.set("i", M.settings.keys.undo, "<C-o>u", opts("Undo"))
for _, key in ipairs(M.settings.keys.redo) do
	vim.keymap.set("n", key, "<C-r>", opts("Redo"))
	vim.keymap.set("i", key, "<C-o><C-r>", opts("Redo"))
end

local function is_terminal_win(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	return (vim.bo[buf].buftype == "terminal" or vim.b[buf].krs_is_multi_term) and true or false
end

local function focus_window_left()
	local cur_win = vim.api.nvim_get_current_win()
	_G._krs_last_win_before_neotree = cur_win
	pcall(vim.cmd, "wincmd h")
	local new_win = vim.api.nvim_get_current_win()
	if is_terminal_win(new_win) and vim.api.nvim_get_mode().mode ~= "t" then
		pcall(vim.cmd, "startinsert")
	end
end

local function focus_window_right()
	local cur_win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(cur_win)
	local is_neotree = vim.bo[buf].filetype == "neo-tree"

	local target_win = _G._krs_last_win_before_neotree
	if
		is_neotree
		and target_win
		and vim.api.nvim_win_is_valid(target_win)
		and vim.api.nvim_win_get_tabpage(target_win) == vim.api.nvim_get_current_tabpage()
	then
		_G._krs_last_win_before_neotree = nil
		vim.api.nvim_set_current_win(target_win)
		if is_terminal_win(target_win) and vim.api.nvim_get_mode().mode ~= "t" then
			pcall(vim.cmd, "startinsert")
		end
		return
	end

	_G._krs_last_win_before_neotree = nil
	pcall(vim.cmd, "wincmd l")
	local new_win = vim.api.nvim_get_current_win()
	if is_terminal_win(new_win) and vim.api.nvim_get_mode().mode ~= "t" then
		pcall(vim.cmd, "startinsert")
	end
end

local function focus_window_up()
	pcall(vim.cmd, "wincmd k")
	local new_win = vim.api.nvim_get_current_win()
	if is_terminal_win(new_win) and vim.api.nvim_get_mode().mode ~= "t" then
		pcall(vim.cmd, "startinsert")
	end
end

local function focus_window_down()
	pcall(vim.cmd, "wincmd j")
	local new_win = vim.api.nvim_get_current_win()
	if is_terminal_win(new_win) and vim.api.nvim_get_mode().mode ~= "t" then
		pcall(vim.cmd, "startinsert")
	end
end

local function set_window_keymaps(keys, fn, desc)
	if not keys then
		return
	end
	local list = type(keys) == "table" and keys or { keys }
	for _, key in ipairs(list) do
		vim.keymap.set({ "n", "t" }, key, fn, opts(desc))
	end
end

set_window_keymaps(M.settings.keys.window_left, focus_window_left, "Move to left window")
set_window_keymaps(M.settings.keys.window_right, focus_window_right, "Move to right window")
set_window_keymaps(M.settings.keys.window_up, focus_window_up, "Move to upper window")
set_window_keymaps(M.settings.keys.window_down, focus_window_down, "Move to lower window")

-- Ctrl+W closes the smallest sensible thing in normal/insert/visual modes.
-- In terminal insert mode ('t'), Ctrl+W is preserved for shell word deletion.
vim.keymap.set({ "n", "i", "v" }, M.settings.keys.close, function()
	if _G.Neotree_Smart_Quit then
		_G.Neotree_Smart_Quit()
	else
		pcall(vim.cmd, "bdelete")
	end
end, { noremap = true, silent = true, nowait = true, desc = "Close Current Tab / Buffer Immediately" })

local step = M.settings.resize_step
local resize_modes = { "n", "i", "t" }

--- Performs directional window resizing so Ctrl+Arrow moves the separator in the direction of the arrow.
--- @param direction "left"|"right"|"up"|"down"
local function resize_dir(direction)
	return function()
		local win = vim.api.nvim_get_current_win()
		local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
		if is_float then
			local cfg = vim.api.nvim_win_get_config(win)
			if direction == "right" then
				pcall(vim.api.nvim_win_set_width, win, cfg.width + step)
			elseif direction == "left" then
				pcall(vim.api.nvim_win_set_width, win, math.max(1, cfg.width - step))
			elseif direction == "up" then
				pcall(vim.api.nvim_win_set_height, win, math.max(1, cfg.height - step))
			elseif direction == "down" then
				pcall(vim.api.nvim_win_set_height, win, cfg.height + step)
			end
			return
		end

		if direction == "right" then
			if vim.fn.winnr("l") ~= vim.fn.winnr() then
				pcall(vim.cmd, "vertical resize +" .. step)
			else
				pcall(vim.cmd, "vertical resize -" .. step)
			end
		elseif direction == "left" then
			if vim.fn.winnr("l") ~= vim.fn.winnr() then
				pcall(vim.cmd, "vertical resize -" .. step)
			else
				pcall(vim.cmd, "vertical resize +" .. step)
			end
		elseif direction == "down" then
			if vim.fn.winnr("j") ~= vim.fn.winnr() then
				pcall(vim.cmd, "resize +" .. step)
			else
				pcall(vim.cmd, "resize -" .. step)
			end
		elseif direction == "up" then
			if vim.fn.winnr("j") ~= vim.fn.winnr() then
				pcall(vim.cmd, "resize -" .. step)
			else
				pcall(vim.cmd, "resize +" .. step)
			end
		end
	end
end

for _, key in ipairs({ "<C-Right>", "<C-S-Right>" }) do
	vim.keymap.set(resize_modes, key, resize_dir("right"), opts("Resize window right"))
end
for _, key in ipairs({ "<C-Left>", "<C-S-Left>" }) do
	vim.keymap.set(resize_modes, key, resize_dir("left"), opts("Resize window left"))
end
for _, key in ipairs({ "<C-Up>", "<C-S-Up>" }) do
	vim.keymap.set(resize_modes, key, resize_dir("up"), opts("Resize window up"))
end
for _, key in ipairs({ "<C-Down>", "<C-S-Down>" }) do
	vim.keymap.set(resize_modes, key, resize_dir("down"), opts("Resize window down"))
end

--- Buffer cycling is disabled inside neo-tree, where those keys navigate the tree.
--- @param command string Ex command to run.
local function safe_buf_navigate(command)
	return function()
		if vim.bo.filetype == "neo-tree" then
			return
		end
		pcall(vim.cmd, command)
	end
end

for _, key in ipairs(M.settings.keys.buffer_prev) do
	vim.keymap.set("n", key, safe_buf_navigate("BufferLineCyclePrev"), opts("Previous buffer"))
end
for _, key in ipairs(M.settings.keys.buffer_next) do
	vim.keymap.set("n", key, safe_buf_navigate("BufferLineCycleNext"), opts("Next buffer"))
end

local function toggle_neotree()
	if _G.Neotree_Toggle then
		_G.Neotree_Toggle()
	else
		if vim.api.nvim_get_mode().mode == "t" then
			pcall(vim.cmd, "stopinsert")
		end
		vim.cmd("silent! Neotree toggle")
		pcall(function()
			require("krs.core.dock").enforce_neotree_layout()
		end)
	end
end

local exp_keys = type(M.settings.keys.explorer) == "table" and M.settings.keys.explorer or { M.settings.keys.explorer }
for _, key in ipairs(exp_keys) do
	vim.keymap.set({ "n", "i", "t" }, key, toggle_neotree, opts("Toggle Explorer"))
end

return M
