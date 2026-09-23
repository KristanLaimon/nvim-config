-- ============================================================================
-- KRS PLUGIN: Multi-Terminal -- nine lazily created terminals in one dock slot.
-- ============================================================================
-- WHAT IT DOES
--   1. Manages `M.settings.count` independent terminals, created on first use.
--   2. <A-1>..<A-9> selects a terminal and shows it in the dock's terminal pane.
--   3. <C-;> / <A-;> toggles the SELECTED terminal open and hidden.
--   4. Remembers the code window you came from, so closing returns focus there.
--   5. Survives a config reload: the terminal table lives on `_G`, and
--      `sync_terminals` re-adopts terminal buffers that lost their slot.
--
-- WHY BUFFER VARIABLES
--   `krs_term_num` (slot) and `krs_is_multi_term` (ownership) live on the buffer
--   itself, so a reload, a session restore or a stray `:terminal` can be mapped
--   back to a slot without keeping a parallel registry in sync.
--
-- COLLABORATORS
--   krs.core.dock      Bottom dock shared with the task runner.
--   plugins.krs.tools.wsl    Chooses the WSL shell when the project lives under WSL.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local dock = lazy_req("krs.core.dock")
local store = lazy_req("krs.core.store")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- How many terminals exist. `<A-n>` is bound for each.
	count = 9,

	--- Height of a freshly opened terminal split, when nothing is saved yet.
	default_height = 10,

	--- Accepted range for the remembered height; anything else is ignored.
	min_height = 3,
	max_height = 100,

	--- Where the last used terminal height is remembered.
	height_file = vim.fn.stdpath("state") .. "/terminal_height",

	--- Where the last used centered floating terminal height is remembered.
	float_height_file = vim.fn.stdpath("state") .. "/terminal_float_height",

	--- Where the last used bottom floating terminal height is remembered.
	bottom_float_height_file = vim.fn.stdpath("state") .. "/terminal_bottom_float_height",

	--- Default layout mode on fresh install: "dock" (bottom split dock).
	--- Can be changed to "float" (centered floating popup) or "bottom_float" (bottom overlay).
	layout = "dock",

	--- Where the last used layout preference is remembered across sessions.
	layout_file = vim.fn.stdpath("state") .. "/terminal_layout",

	--- Step size in rows for stretching / shrinking terminal height (<C-Up> / <C-Down>).
	resize_step = 2,

	--- Floating window dimensions & border options (used when layout is "float" or "bottom_float")
	float = {
		width = 0.85,
		height = 0.80,
		border = "rounded",
	},

	--- Top border row threshold for mouse height resizing/dragging (in rows).
	--- Clicking within this top threshold allows dragging the window height instead of entering terminal insert mode.
	resize_drag_threshold = 2,

	keys = {
		--- Prefix for per-terminal selection; the number is appended (`<A-1>`).
		select_prefix = "<A-",
		--- Toggle the selected terminal.
		toggle = { "<C-t>", "<C-T>", "<C-\\>", "<leader>t", "<leader>ft", "<F4>", "<C-;>", "<A-;>" },
		--- Close the terminal window from inside terminal mode.
		close = "<C-w>",
		--- Stretch terminal bigger (<C-Up>).
		resize_up = { "<C-Up>", "<C-S-Up>" },
		--- Shrink terminal smaller (<C-Down>).
		resize_down = { "<C-Down>", "<C-S-Down>" },
		--- Clipboard bridges, because a terminal has no access to registers.
		paste = { "<C-v>", "<C-S-v>" },
		copy = { "<C-c>", "<C-S-c>" },
	},
}

-- ============================================================================
-- STATE -- kept on _G so a config reload does not orphan open terminals
-- ============================================================================

_G._krs_terminals = _G._krs_terminals or {}
_G._krs_selected_terminal = _G._krs_selected_terminal or 1

--- `[n] = { buf = integer|nil, win = integer|nil }`
local terminals = _G._krs_terminals

--- Window to return to when the terminal is dismissed.
local code_win = nil

--- Current terminal split height, persisted across sessions.
local terminal_height_cached = nil

-- ============================================================================
-- HEIGHT PERSISTENCE
-- ============================================================================

--- Reads the remembered height, falling back to the default.
--- @return integer height
local function load_saved_height()
	local raw = store.read_file(M.settings.height_file)
	local height = raw and tonumber(raw) or nil
	if height and height >= M.settings.min_height and height <= M.settings.max_height then
		return height
	end
	return M.settings.default_height
end

local function get_terminal_height()
	if not terminal_height_cached then
		terminal_height_cached = load_saved_height()
	end
	return terminal_height_cached
end

--- Remembers a new height when it is in range and actually changed.
--- @param height integer
local function save_height(height)
	if type(height) ~= "number" or height < M.settings.min_height or height > M.settings.max_height then
		return
	end
	if height == get_terminal_height() then
		return
	end
	terminal_height_cached = height
	store.write_file(M.settings.height_file, tostring(height))
end

local function load_saved_float_height()
	local raw = store.read_file(M.settings.float_height_file)
	local height = raw and tonumber(vim.trim(raw)) or nil
	if height and height >= M.settings.min_height and height <= M.settings.max_height then
		return height
	end
	local total_h = vim.o.lines or 24
	return math.max(5, math.floor(total_h * (M.settings.float.height or 0.80)))
end

local function get_float_height()
	if not _G._krs_terminal_float_height then
		_G._krs_terminal_float_height = load_saved_float_height()
	end
	return _G._krs_terminal_float_height
end

local function save_float_height(height)
	if type(height) ~= "number" or height < M.settings.min_height or height > M.settings.max_height then
		return
	end
	if height == get_float_height() then
		return
	end
	_G._krs_terminal_float_height = height
	store.write_file(M.settings.float_height_file, tostring(height))
end

local function load_saved_bottom_float_height()
	local raw = store.read_file(M.settings.bottom_float_height_file)
	local height = raw and tonumber(vim.trim(raw)) or nil
	if height and height >= M.settings.min_height and height <= M.settings.max_height then
		return height
	end
	return get_terminal_height()
end

local function get_bottom_float_height()
	if not _G._krs_terminal_bottom_float_height then
		_G._krs_terminal_bottom_float_height = load_saved_bottom_float_height()
	end
	return _G._krs_terminal_bottom_float_height
end

local function save_bottom_float_height(height)
	if type(height) ~= "number" or height < M.settings.min_height or height > M.settings.max_height then
		return
	end
	if height == get_bottom_float_height() then
		return
	end
	_G._krs_terminal_bottom_float_height = height
	store.write_file(M.settings.bottom_float_height_file, tostring(height))
end

-- ============================================================================
-- LAYOUT PERSISTENCE
-- ============================================================================

--- Reads the remembered layout ("dock", "float", "bottom_float"), falling back to default ("dock").
--- @return string layout
local function load_saved_layout()
	local raw = store.read_file(M.settings.layout_file)
	if raw then
		raw = vim.trim(raw)
	end
	if raw and (raw == "dock" or raw == "float" or raw == "bottom_float") then
		return raw
	end
	return M.settings.layout or "dock"
end

local function get_terminal_layout()
	if not _G._krs_terminal_layout then
		_G._krs_terminal_layout = load_saved_layout()
	end
	return _G._krs_terminal_layout
end

--- Remembers a new layout preference.
--- @param layout string
local function save_layout(layout)
	if layout ~= "dock" and layout ~= "float" and layout ~= "bottom_float" then
		return
	end
	_G._krs_terminal_layout = layout
	store.write_file(M.settings.layout_file, layout)
end

-- ============================================================================
-- SLOT BOOKKEEPING
-- ============================================================================

--- @param win integer|nil
--- @return boolean
local function is_valid_win(win)
	return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

--- @param buf integer|nil
--- @return boolean
local function is_valid_buf(buf)
	return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

--- True when bufnr belongs to a terminal.
--- @param bufnr integer|nil
--- @return boolean
local function is_term_buf(bufnr)
	return is_valid_buf(bufnr) and (vim.bo[bufnr].buftype == "terminal" or vim.b[bufnr].krs_is_multi_term)
end

--- True when win displays a terminal buffer.
--- @param win integer|nil
--- @return boolean
local function is_term_win(win)
	if not is_valid_win(win) then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return is_term_buf(buf)
end

--- Slot record for terminal `n`, created on demand.
--- @param n integer
--- @return table slot `{ buf, win }`
local function get_term(n)
	terminals[n] = terminals[n] or { buf = nil, win = nil }
	return terminals[n]
end

--- Claims `bufnr` for the first free slot, tagging the buffer with its number.
--- @param bufnr integer
--- @param winid integer|nil Window showing the buffer, when it has one.
--- @return integer|nil slot
local function adopt_buffer(bufnr, winid)
	for n = 1, M.settings.count do
		local t = get_term(n)
		if not is_valid_buf(t.buf) then
			t.buf = bufnr
			t.win = winid or t.win
			vim.b[bufnr].krs_term_num = n
			vim.b[bufnr].krs_is_multi_term = true
			return n
		end
	end
	return nil
end

--- True for a terminal buffer this plugin may own (task outputs are excluded).
--- @param bufnr integer
--- @return boolean
local function is_adoptable(bufnr)
	return vim.bo[bufnr].buftype == "terminal" and not vim.b[bufnr].krs_is_task
end

--- Reconciles the slot table with reality: drops dead handles, re-attaches
--- tagged buffers, and adopts untagged terminals (from a session or `:terminal`).
local function sync_terminals()
	for n = 1, M.settings.count do
		local t = terminals[n]
		if t then
			t.win = is_valid_win(t.win) and t.win or nil
			t.buf = is_valid_buf(t.buf) and t.buf or nil
		end
	end

	-- Visible terminals first, so a slot keeps the window it is displayed in.
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(winid) then
			local bufnr = vim.api.nvim_win_get_buf(winid)
			if vim.api.nvim_buf_is_valid(bufnr) then
				local term_num = vim.b[bufnr].krs_term_num
				if term_num and term_num >= 1 and term_num <= M.settings.count then
					local t = get_term(term_num)
					t.buf, t.win = bufnr, winid
				elseif is_adoptable(bufnr) then
					adopt_buffer(bufnr, winid)
				end
			end
		end
	end

	-- Then hidden terminal buffers, which have no window to record.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local term_num = vim.b[bufnr].krs_term_num
			if term_num and term_num >= 1 and term_num <= M.settings.count then
				local t = get_term(term_num)
				if not is_valid_buf(t.buf) then
					t.buf = bufnr
				end
			elseif is_adoptable(bufnr) then
				adopt_buffer(bufnr, nil)
			end
		end
	end
end

--- The window currently hosting a terminal: the selected one when it is visible,
--- otherwise any visible terminal.
--- @return integer|nil win
local function get_active_terminal_win()
	sync_terminals()

	local selected = terminals[_G._krs_selected_terminal or 1]
	if selected and is_valid_win(selected.win) then
		return selected.win
	end
	for _, t in pairs(terminals) do
		if is_valid_win(t.win) then
			return t.win
		end
	end
	return nil
end

-- ============================================================================
-- TERMINAL CREATION
-- ============================================================================

--- `:terminal` command for the current project, routed through WSL when the
--- project lives on a WSL path.
--- @return string cmd
local function terminal_open_cmd()
	local ok, wsl = pcall(require, "plugins.krs.tools.wsl")
	local wsl_cmd = ok and wsl.shell_command_for_cwd(vim.fn.getcwd()) or nil
	return wsl_cmd and ("terminal " .. wsl_cmd) or "terminal"
end

--- Shows terminal `n` in `win`, spawning the shell when the slot has no buffer.
--- @param t table Slot record.
--- @param n integer Slot number.
--- @param win integer Window to fill.
local function fill_window(t, n, win)
	if is_valid_win(win) then
		vim.api.nvim_set_current_win(win)
	end

	if is_valid_buf(t.buf) then
		vim.api.nvim_win_set_buf(win, t.buf)
		return
	end

	local cwd = vim.fn.getcwd()
	local stat_fn = (vim.uv or vim.loop).fs_stat
	if stat_fn(cwd .. "/.krsnvim/secondary_repos.json") then
		local ok_sec, sec = pcall(require, "krs.git.secondary")
		if ok_sec and sec then
			sec.setup_environment(cwd)
		end
	end

	vim.cmd(terminal_open_cmd())
	t.buf = vim.api.nvim_get_current_buf()
	vim.bo[t.buf].buflisted = false
	vim.b[t.buf].krs_term_num = n
	vim.b[t.buf].krs_is_multi_term = true
end

-- ============================================================================
-- FLOATING WINDOW HELPERS
-- ============================================================================

--- Checks if a window is a floating window.
--- @param win integer|nil
--- @return boolean
local function is_floating_win(win)
	if not win or type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local cfg = vim.api.nvim_win_get_config(win)
	return cfg and cfg.relative and cfg.relative ~= ""
end

--- Opens a floating window for terminal `n`.
--- @param t table Slot record.
--- @param n integer Slot number.
--- @param layout string "float" or "bottom_float".
--- @return integer win Window handle.
local function open_floating_window(t, n, layout)
	local z_ok, z_index = pcall(require, "krs.core.z_index")
	local zidx = z_ok and z_index.next_zindex("terminal") or 50

	local total_w = vim.o.columns or 80
	local total_h = vim.o.lines or 24

	local w, h, r, c
	if layout == "bottom_float" then
		w = math.max(20, total_w - 2)
		h = math.min(total_h - 4, get_bottom_float_height())
		r = math.max(1, total_h - h - 3)
		c = 1
	else
		w = math.max(20, math.floor(total_w * (M.settings.float.width or 0.85)))
		h = math.min(total_h - 4, get_float_height())
		r = math.max(1, math.floor((total_h - h) / 2) - 1)
		c = math.max(1, math.floor((total_w - w) / 2))
	end

	local target_buf = is_valid_buf(t.buf) and t.buf or nil
	local scratch = nil
	if not target_buf then
		scratch = vim.api.nvim_create_buf(false, true)
		target_buf = scratch
	end

	local win = vim.api.nvim_open_win(target_buf, true, {
		relative = "editor",
		width = w,
		height = h,
		row = r,
		col = c,
		border = M.settings.float.border or "rounded",
		title = " 🖥️ Terminal #" .. n .. " ",
		title_pos = "center",
		zindex = zidx,
	})

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"

	if z_ok and z_index.register then
		z_index.register("terminal", win, { zindex = zidx })
	end

	fill_window(t, n, win)

	if scratch and is_valid_buf(scratch) and scratch ~= t.buf then
		pcall(vim.api.nvim_buf_delete, scratch, { force = true })
	end

	return win
end

--- Updates the title of a floating terminal window to reflect slot `n`.
--- @param win integer Window handle.
--- @param n integer Slot number.
local function update_float_title(win, n)
	if is_floating_win(win) then
		pcall(vim.api.nvim_win_set_config, win, {
			title = " 🖥️ Terminal #" .. n .. " ",
			title_pos = "center",
		})
	end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Currently selected terminal number.
--- @return integer n
function M.get_selected_terminal()
	return _G._krs_selected_terminal or 1
end

--- Selects terminal `n` and shows it, reusing the visible terminal window.
--- @param n integer Slot number.
function M.select_terminal(n)
	sync_terminals()
	_G._krs_selected_terminal = n

	local t = get_term(n)
	local current_win = vim.api.nvim_get_current_win()
	local active_win = get_active_terminal_win()

	if not active_win or current_win ~= active_win then
		code_win = current_win
	end

	if is_valid_win(active_win) then
		t.win = active_win
		vim.api.nvim_set_current_win(t.win)
		fill_window(t, n, t.win)
		if is_floating_win(t.win) then
			update_float_title(t.win, n)
		end
		vim.api.nvim_set_current_win(t.win)
		vim.cmd("startinsert")
	else
		M.open_terminal(n)
	end

	vim.notify("🖥️ Terminal #" .. n .. " active", vim.log.levels.INFO, { title = "Multi-Terminal" })
end

--- Opens terminal `n`, creating the dock pane or floating window when there is none.
--- @param n integer|nil Slot number. Defaults to the selected terminal.
function M.open_terminal(n)
	sync_terminals()

	n = n or _G._krs_selected_terminal or 1
	_G._krs_selected_terminal = n

	local t = get_term(n)
	local current = vim.api.nvim_get_current_win()
	local active_win = get_active_terminal_win()

	if current ~= active_win then
		code_win = current
	end

	-- Already on screen: just focus it.
	if is_valid_win(t.win) then
		vim.api.nvim_set_current_win(t.win)
		vim.cmd("startinsert")
		return
	end

	-- Another terminal is on screen: take over its pane.
	if is_valid_win(active_win) then
		t.win = active_win
		vim.api.nvim_set_current_win(t.win)
		fill_window(t, n, t.win)
		if is_floating_win(t.win) then
			update_float_title(t.win, n)
		end
		vim.api.nvim_set_current_win(t.win)
		vim.cmd("startinsert")
		return
	end

	local layout = get_terminal_layout()
	if layout == "float" or layout == "bottom_float" then
		t.win = open_floating_window(t, n, layout)
	else
		t.win = dock.open({ prefer = "terminal", height = get_terminal_height() })
		vim.api.nvim_set_current_win(t.win)
		fill_window(t, n, t.win)
		dock.style(t.win)
	end
	vim.api.nvim_set_current_win(t.win)
	vim.cmd("startinsert")
end

--- Hides the terminal when focused, shows or creates it otherwise.
function M.toggle_selected_terminal()
	sync_terminals()

	local n = _G._krs_selected_terminal or 1
	local t = get_term(n)
	local current = vim.api.nvim_get_current_win()
	local active_win = get_active_terminal_win()

	if active_win and current == active_win then
		pcall(vim.cmd, "stopinsert")
		pcall(vim.api.nvim_win_close, active_win, true)

		-- Every slot sharing that pane loses its window handle, not just this one.
		for _, term in pairs(terminals) do
			if term.win == active_win then
				term.win = nil
			end
		end

		if is_valid_win(code_win) then
			pcall(vim.api.nvim_set_current_win, code_win)
		else
			vim.cmd("wincmd p")
		end
		return
	end

	if is_valid_win(t.win) then
		vim.api.nvim_set_current_win(t.win)
		vim.cmd("startinsert")
		return
	end

	M.open_terminal(n)
end

--- Gets current terminal layout ("dock", "float", or "bottom_float").
--- @return string
function M.get_layout()
	return get_terminal_layout()
end

--- Sets terminal layout mode and shows terminal in the new layout.
--- @param layout "dock"|"float"|"bottom_float"
function M.set_layout(layout)
	if layout ~= "dock" and layout ~= "float" and layout ~= "bottom_float" then
		return
	end
	save_layout(layout)

	local cur_n = _G._krs_selected_terminal or 1
	local active_win = get_active_terminal_win()
	if active_win and is_valid_win(active_win) then
		pcall(vim.cmd, "stopinsert")
		pcall(vim.api.nvim_win_close, active_win, true)
		for _, term in pairs(terminals) do
			if term.win == active_win then
				term.win = nil
			end
		end
	end
	M.open_terminal(cur_n)

	local label = layout == "dock" and "Docked Split (Bottom)"
		or (layout == "bottom_float" and "Bottom Floating Overlay" or "Centered Floating Popup")
	vim.notify("🖥️ Terminal layout set to: " .. label, vim.log.levels.INFO, { title = "Multi-Terminal" })
end

--- Toggles terminal layout cycling through: dock -> bottom_float -> float -> dock.
function M.toggle_layout()
	local cur = get_terminal_layout()
	local target
	if cur == "dock" then
		target = "bottom_float"
	elseif cur == "bottom_float" then
		target = "float"
	else
		target = "dock"
	end
	M.set_layout(target)
end

M.is_term_buf = is_term_buf
M.is_term_win = is_term_win

--- Resizes the terminal height.
--- In bottom floating mode: stretches or shrinks from the top edge, keeping bottom edge anchored.
--- In centered floating mode: stretches or shrinks top and bottom edges simultaneously (centered).
--- In docked split mode: adjusts the split window height upwards or downwards.
--- Persists the new height globally across sessions in stdpath("state").
--- @param delta integer Positive to grow, negative to shrink.
--- @return boolean resized Whether resizing took place.
function M.resize_height(delta)
	delta = delta or M.settings.resize_step or 2
	local win = vim.api.nvim_get_current_win()
	local active_win = get_active_terminal_win()
	local target_win = nil

	if is_valid_win(win) and is_term_win(win) then
		target_win = win
	elseif is_valid_win(active_win) then
		target_win = active_win
	end

	if not target_win or not is_valid_win(target_win) then
		return false
	end

	local total_lines = vim.o.lines or 24
	local is_float = is_floating_win(target_win)

	if is_float then
		local cfg = vim.api.nvim_win_get_config(target_win)
		local cur_h = cfg.height
		local cur_r = type(cfg.row) == "table" and (cfg.row[false] or 1) or (tonumber(cfg.row) or 1)

		local layout = get_terminal_layout()
		local is_bottom = (layout == "bottom_float") or (cur_r + cur_h >= total_lines - 4)

		if is_bottom then
			-- Bottom floating: bottom edge is anchored; stretch or shrink from top edge
			local bottom_edge = cur_r + cur_h
			local max_h = math.max(M.settings.min_height, bottom_edge - 1)
			local new_h = math.min(max_h, math.max(M.settings.min_height, cur_h + delta))
			local new_r = bottom_edge - new_h

			if new_h ~= cur_h or new_r ~= cur_r then
				local ok = pcall(vim.api.nvim_win_set_config, target_win, {
					relative = cfg.relative or "editor",
					row = new_r,
					col = cfg.col,
					width = cfg.width,
					height = new_h,
				})
				if ok then
					save_bottom_float_height(new_h)
					return true
				end
			end
		else
			-- Centered floating: stretches or shrinks top and bottom edge at the same time (stays centered)
			local max_h = math.max(M.settings.min_height, total_lines - 4)
			local new_h = math.min(max_h, math.max(M.settings.min_height, cur_h + delta))
			local new_r = math.max(1, math.floor((total_lines - new_h) / 2) - 1)

			if new_h ~= cur_h or new_r ~= cur_r then
				local ok = pcall(vim.api.nvim_win_set_config, target_win, {
					relative = cfg.relative or "editor",
					row = new_r,
					col = cfg.col,
					width = cfg.width,
					height = new_h,
				})
				if ok then
					save_float_height(new_h)
					return true
				end
			end
		end
		return false
	end

	-- Docked bottom split: increasing height stretches from top edge upwards!
	local cur_h = vim.api.nvim_win_get_height(target_win)
	local max_h = math.max(M.settings.min_height, total_lines - 4)
	local new_h = math.min(max_h, math.max(M.settings.min_height, cur_h + delta))

	if new_h ~= cur_h then
		pcall(vim.api.nvim_win_set_height, target_win, new_h)
		save_height(new_h)
		return true
	end

	return false
end

--- Stretches the terminal height larger (<C-Up>).
function M.increase_height()
	local step = M.settings.resize_step or 2
	M.resize_height(step)
end

--- Shrinks the terminal height smaller (<C-Down>).
function M.decrease_height()
	local step = M.settings.resize_step or 2
	M.resize_height(-step)
end

--- Re-exported for callers that relied on this module owning the dock order.
M.enforce_bottom_layout = dock.enforce_order

-- ============================================================================
-- SETUP
-- ============================================================================

--- Pastes the OS clipboard into a terminal (`"+`, falling back to `"*`).
local function paste_clipboard()
	local clip = vim.fn.getreg("+")
	if not clip or clip == "" then
		clip = vim.fn.getreg("*")
	end
	if clip and clip ~= "" then
		vim.api.nvim_paste(clip, true, -1)
	end
end

--- Binds selection, toggling, closing and clipboard keys, and starts the
--- autocmd that remembers a resized terminal's height.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	sync_terminals()

	vim.api.nvim_create_autocmd("WinResized", {
		group = vim.api.nvim_create_augroup("KrsTerminalHeightSaver", { clear = true }),
		callback = function()
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(winid) then
					local bufnr = vim.api.nvim_win_get_buf(winid)
					if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal" then
						save_height(vim.api.nvim_win_get_height(winid))
					end
				end
			end
		end,
	})

	for n = 1, M.settings.count do
		for _, prefix in ipairs({ M.settings.keys.select_prefix, "<M-" }) do
			vim.keymap.set({ "n", "i", "t" }, prefix .. n .. ">", function()
				M.select_terminal(n)
			end, { noremap = true, silent = true, desc = "Select Terminal #" .. n })
		end
	end

	vim.api.nvim_create_user_command("TerminalToggle", function()
		M.toggle_selected_terminal()
	end, { desc = "Toggle selected terminal window" })

	vim.api.nvim_create_user_command("TerminalToggleLayout", function()
		M.toggle_layout()
	end, { desc = "Toggle terminal layout between Docked Split and Floating Overlay" })

	vim.api.nvim_create_user_command("TerminalLayout", function(opts)
		if opts.args and opts.args ~= "" then
			M.set_layout(opts.args)
		else
			M.toggle_layout()
		end
	end, {
		nargs = "?",
		complete = function()
			return { "dock", "float", "bottom_float" }
		end,
		desc = "Set or toggle terminal layout (dock, float, bottom_float)",
	})

	vim.api.nvim_create_user_command("TerminalIncreaseHeight", function()
		M.increase_height()
	end, { desc = "Increase terminal height (<C-Up>)" })

	vim.api.nvim_create_user_command("TerminalDecreaseHeight", function()
		M.decrease_height()
	end, { desc = "Decrease terminal height (<C-Down>)" })

	vim.api.nvim_create_user_command("TerminalSelect", function(opts)
		local num = tonumber(opts.args)
		if num then
			M.select_terminal(num)
		else
			M.toggle_selected_terminal()
		end
	end, { nargs = "?", desc = "Select terminal by number" })

	for _, key in ipairs(M.settings.keys.toggle) do
		vim.keymap.set({ "n", "i", "t" }, key, M.toggle_selected_terminal, {
			noremap = true,
			silent = true,
			desc = "Toggle Selected Terminal",
		})
	end
	vim.keymap.set({ "n", "i", "t" }, "<M-;>", M.toggle_selected_terminal, {
		noremap = true,
		silent = true,
		desc = "Toggle Selected Terminal",
	})

	-- Note: <C-w> in terminal mode is preserved for native shell word deletion (Ctrl+W)
	if M.settings.keys.close and M.settings.keys.close ~= "<C-w>" then
		vim.keymap.set("t", M.settings.keys.close, function()
			pcall(vim.cmd, "stopinsert")
			if _G.Neotree_Smart_Quit then
				_G.Neotree_Smart_Quit()
			else
				pcall(vim.cmd, "close")
			end
		end, { noremap = true, silent = true, nowait = true, desc = "Close Terminal Window" })
	end

	for _, key in ipairs(M.settings.keys.paste) do
		vim.keymap.set("t", key, paste_clipboard, {
			noremap = true,
			silent = true,
			desc = "Paste OS Clipboard to Terminal",
		})
	end
	for _, key in ipairs(M.settings.keys.copy) do
		vim.keymap.set("v", key, '"+y', {
			noremap = true,
			silent = true,
			desc = "Copy selection to OS Clipboard",
		})
	end

	-- Auto-enter terminal mode on buffer focus and mouse click.
	-- Ensures clicking inside a terminal window or returning to it (e.g. toggling Neo-tree off)
	-- automatically puts Neovim into terminal (insert) mode (`startinsert`).
	local auto_insert_group = vim.api.nvim_create_augroup("KrsTerminalAutoInsert", { clear = true })

	local threshold = M.settings.resize_drag_threshold or 2

	local function setup_term_buffer(bufnr)
		if is_term_buf(bufnr) then
			for _, k in ipairs(M.settings.keys.resize_up or {}) do
				pcall(vim.keymap.set, { "n", "t", "i" }, k, function()
					M.increase_height()
				end, {
					buffer = bufnr,
					noremap = true,
					silent = true,
					desc = "Terminal Stretch Bigger (Increase Height)",
				})
			end
			for _, k in ipairs(M.settings.keys.resize_down or {}) do
				pcall(vim.keymap.set, { "n", "t", "i" }, k, function()
					M.decrease_height()
				end, {
					buffer = bufnr,
					noremap = true,
					silent = true,
					desc = "Terminal Shrink Smaller (Decrease Height)",
				})
			end

			pcall(vim.keymap.set, "n", "<LeftMouse>", function()
				local mouse = vim.fn.getmousepos()
				-- If click is on statusline, winbar, separator, border, or within the top threshold zone
				-- (line <= 0 or winrow <= threshold), return "<LeftMouse>" so Neovim executes built-in split resize!
				if not mouse or mouse.line <= 0 or mouse.winrow <= threshold then
					return "<LeftMouse>"
				end
				-- If click is on a different window than current, let Neovim switch focus first
				if mouse.winid and mouse.winid ~= vim.api.nvim_get_current_win() then
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(mouse.winid) and vim.api.nvim_get_current_win() == mouse.winid then
							pcall(vim.cmd, "startinsert")
						end
					end)
					return "<LeftMouse>"
				end
				-- When inside terminal window in Normal mode, return <LeftMouse> so mouse clicking
				-- and mouse text selection (drag) work natively.
				return "<LeftMouse>"
			end, {
				buffer = bufnr,
				expr = true,
				noremap = true,
				silent = true,
				desc = "Enter Terminal Mode on Click",
			})
		end
	end

	local function enter_terminal_mode(bufnr)
		if not is_term_buf(bufnr) then
			return
		end
		if vim.api.nvim_get_current_buf() == bufnr and vim.api.nvim_get_mode().mode ~= "t" then
			pcall(vim.cmd, "startinsert")
		end
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_term_buf(bufnr) then
			setup_term_buffer(bufnr)
		end
	end

	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "WinEnter", "BufWinEnter" }, {
		group = auto_insert_group,
		callback = function(args)
			if is_term_buf(args.buf) then
				setup_term_buffer(args.buf)
				enter_terminal_mode(args.buf)
				vim.schedule(function()
					if vim.api.nvim_get_current_buf() == args.buf then
						enter_terminal_mode(args.buf)
					end
				end)
			end
		end,
	})
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.TerminalManager = M
package.loaded["plugins.krs.dev.terminal"] = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_terminal",
	dir = require("krs.core.lazyspec").for_module(),
	event = { "TermOpen" },
	cmd = {
		"TerminalToggle",
		"TerminalSelect",
		"TerminalToggleLayout",
		"TerminalLayout",
		"TerminalIncreaseHeight",
		"TerminalDecreaseHeight",
	},
	keys = {
		{ "<C-;>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal" },
		{ "<A-;>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal" },
		{ "<M-;>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal" },
		{ "<C-t>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal (Mobile)" },
		{ "<C-T>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal (Mobile)" },
		{ "<C-\\>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal (Mobile)" },
		{ "<leader>t", mode = { "n", "v" }, desc = "Toggle Selected Terminal" },
		{ "<F4>", mode = { "n", "i", "t" }, desc = "Toggle Selected Terminal (F4)" },
	},
	config = M.setup,
}, { __index = M })
