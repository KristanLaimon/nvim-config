-- ============================================================================
-- KRS PLUGIN: Input Modal -- the one floating prompt every module reuses.
-- ============================================================================
-- WHAT IT DOES
--   A centered, self-resizing input box. It also REPLACES `vim.ui.input`, so
--   every prompt in the config (and in third-party plugins) looks the same.
--
-- USAGE
--   require("plugins.krs.ui.input_modal").open({
--     label = "Rename",            -- title; `title` and `prompt` also accepted
--     default_value = "old name",  -- initial text; `default` also accepted
--     relative = "editor",         -- or "cursor"
--     callback = function(ok, text) end,
--   })
--
-- BEHAVIOUR NOTES
--   * <CR> confirms, <S-CR>/<M-CR> inserts a newline, <Esc> leaves insert mode
--     and a second <Esc> (or q) cancels.
--   * The box grows with the text, up to the ratios in `M.settings`.
--   * `callback` is guaranteed to fire exactly once -- confirm, cancel, or the
--     window being closed by anything else.
--   * The buffer is `acwrite`, so `:w` inside the modal confirms too.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Largest the box may grow, as a fraction of the editor.
	max_width_ratio = 0.70,
	max_height_ratio = 0.70,

	--- Narrowest the box may be, and the padding added around the text.
	min_width = 36,
	label_padding = 10,
	text_padding = 6,

	--- Window border and title decoration.
	border = "rounded",
	title_icon = "📝",

	keys = {
		confirm = { "<CR>" },
		newline = { "<S-CR>", "<S-Enter>", "<M-CR>" },
		cancel = { "<Esc>", "q", "<C-c>" },
	},
}

-- ============================================================================
-- GEOMETRY
-- ============================================================================

--- Computes the box size and position for the given content.
--- Height counts WRAPPED lines, so a long single line still gets the rows it
--- needs instead of scrolling inside a one-line window.
---
--- @param lines string[] Current buffer content.
--- @param label string Title text, which sets the minimum width.
--- @return integer width
--- @return integer height
--- @return integer row
--- @return integer col
local function measure(lines, label)
	local cols = vim.o.columns or 80
	local rows = vim.o.lines or 24

	local max_width = math.max(30, math.floor(cols * M.settings.max_width_ratio))
	local min_width = math.min(math.max(#label + M.settings.label_padding, M.settings.min_width), max_width)

	local longest = 0
	for _, line in ipairs(lines) do
		longest = math.max(longest, #line)
	end

	local width = math.min(math.max(longest + M.settings.text_padding, min_width), max_width)

	local wrapped = 0
	for _, line in ipairs(lines) do
		wrapped = wrapped + (#line == 0 and 1 or math.ceil(#line / math.max(width, 1)))
	end

	local max_height = math.max(3, math.floor(rows * M.settings.max_height_ratio))
	local height = math.min(math.max(wrapped, 1), max_height)

	return width,
		height,
		math.max(0, math.floor((rows - (height + 2)) / 2)),
		math.max(0, math.floor((cols - (width + 2)) / 2))
end

-- ============================================================================
-- API
-- ============================================================================

--- Opens the input modal.
--- @param opts table `{ label|title|prompt, default_value|default, relative, callback }`
function M.open(opts)
	opts = opts or {}

	local label = (opts.label or opts.title or opts.prompt or "Input"):gsub("^%s*", ""):gsub(":%s*$", "")
	--- @type fun(ok: boolean, text: string)
	local callback = opts.callback or function(_, _) end
	local relative = opts.relative or "editor"
	local orig_win = vim.api.nvim_get_current_win()

	local buf = vim.api.nvim_create_buf(false, true)
	-- `acwrite` so `:w` can be caught as "confirm" (see BufWriteCmd below).
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "krsinputmodal"
	vim.b[buf].completion = false
	vim.api.nvim_buf_set_name(buf, "Input: " .. label)

	local raw_default = (opts.default_value or opts.default or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = vim.split(raw_default, "\n", { plain = true })
	if #lines == 0 then
		lines = { "" }
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width, height, row, col = measure(lines, label)
	local win_opts = {
		relative = relative,
		width = width,
		height = height,
		style = "minimal",
		border = M.settings.border,
		title = " " .. M.settings.title_icon .. " " .. label .. " ",
		title_pos = "center",
	}
	if relative == "cursor" then
		win_opts.row, win_opts.col = 1, 0
	else
		win_opts.relative, win_opts.row, win_opts.col = "editor", row, col
	end

	local z_index = require("krs.core.z_index")
	local name = opts.name or "input_modal"
	local z_val = z_index.next_zindex(name, { parent = opts.parent, offset = opts.offset or 50 })
	win_opts.zindex = z_val

	local win = vim.api.nvim_open_win(buf, true, win_opts)
	z_index.register(name, win, { zindex = z_val, parent = opts.parent })
	for option, value in pairs({ wrap = true, linebreak = true, scrolloff = 0, cursorline = false }) do
		pcall(vim.api.nvim_set_option_value, option, value, { win = win })
	end

	vim.cmd("startinsert!")

	local finished = false

	--- Closes the float and hands focus back to the caller.
	--- `<CR>` confirms from insert mode, but closing the float does not leave it:
	--- focus would return to the caller's buffer still in insert, moving the cursor
	--- and firing blink.cmp there. Leave insert BEFORE giving the window back.
	local function close_win()
		vim.cmd("stopinsert")
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(function()
				vim.bo[buf].modified = false
			end)
		end
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
		if vim.api.nvim_win_is_valid(orig_win) then
			pcall(vim.api.nvim_set_current_win, orig_win)
		end
	end

	--- Ends the modal exactly once. `ok` false means cancelled.
	local function finish(ok)
		if finished then
			return
		end
		finished = true

		local text = ok and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") or ""
		close_win()
		callback(ok, text)
	end

	--- Re-measures the float after every edit.
	local function resize()
		if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
			return
		end

		local new_w, new_h, new_row, new_col = measure(vim.api.nvim_buf_get_lines(buf, 0, -1, false), label)
		local config = { width = new_w, height = new_h }
		if relative == "editor" then
			config.relative, config.row, config.col = "editor", new_row, new_col
		end

		pcall(vim.api.nvim_win_set_config, win, config)
		pcall(vim.api.nvim_win_call, win, function()
			vim.fn.winrestview({ topline = 1 })
		end)
	end

	--- Splits the current line at the cursor, since <CR> is taken by confirm.
	local function insert_newline()
		if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
			return
		end

		local cursor = vim.api.nvim_win_get_cursor(win)
		local cursor_row, cursor_col = cursor[1], cursor[2]
		local line = vim.api.nvim_buf_get_lines(buf, cursor_row - 1, cursor_row, false)[1] or ""
		vim.api.nvim_buf_set_lines(buf, cursor_row - 1, cursor_row, false, {
			line:sub(1, cursor_col),
			line:sub(cursor_col + 1),
		})
		vim.api.nvim_win_set_cursor(win, { cursor_row + 1, 0 })

		resize()
		pcall(vim.api.nvim_win_call, win, function()
			vim.fn.winrestview({ topline = 1 })
		end)
	end

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
		buffer = buf,
		callback = resize,
	})

	local kopts = { buffer = buf, noremap = true, silent = true }
	for _, key in ipairs(M.settings.keys.confirm) do
		vim.keymap.set({ "n", "i" }, key, function()
			finish(true)
		end, kopts)
	end
	for _, key in ipairs(M.settings.keys.newline) do
		vim.keymap.set({ "n", "i" }, key, insert_newline, kopts)
	end
	for _, key in ipairs(M.settings.keys.cancel) do
		vim.keymap.set("n", key, function()
			finish(false)
		end, kopts)
	end

	-- In insert mode <Esc> only leaves insert; cancelling takes a second press.
	vim.keymap.set("i", "<Esc>", "<Cmd>stopinsert<CR>", kopts)

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			finish(true)
		end,
	})

	-- Anything else that closes the window still has to report a cancellation.
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if finished then
				return
			end
			finished = true
			if vim.api.nvim_buf_is_valid(buf) then
				pcall(function()
					vim.bo[buf].modified = false
				end)
			end
			callback(false, "")
		end,
	})
end

--- Replaces `vim.ui.input` with this modal, so every prompt in the editor -- ours
--- and third-party -- shares one look.
function M.setup_ui_input_override()
	vim.ui.input = function(opts, on_confirm)
		opts = opts or {}
		M.open({
			label = opts.prompt or "Input",
			default_value = opts.default or "",
			relative = "editor",
			callback = function(ok, text)
				on_confirm(ok and text or nil)
			end,
		})
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.InputModal = M

M.setup_ui_input_override()

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_input_modal",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VeryLazy",
	config = M.setup_ui_input_override,
}, { __index = M })
