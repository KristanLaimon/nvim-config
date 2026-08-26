--- @module "krsnvim.cli"
--- Powerful CLI Mini-Framework, ASCII Art Generator, Argument Parser, and Interactive Menu Suite for `krsnvimscript`.
--- Provides Vim/Arrow/Mouse-navigable menus, checkbox multi-selection, formatted boxes, tables, spinners, ANSI colors, and argument parsing.
---
--- Documentation & Usage Guide:
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local cli = import("krsnvim.cli")
--- print(cli.ascii_title("KRSNVIM"))
--- cli.menu("Select Environment", { "Development", "Staging", "Production" }, function(choice, idx)
---     print("Selected:", choice)
--- end)

local M = {}

-- ============================================================================
-- ANSI COLORS & STYLING
-- ============================================================================

--- ANSI escape sequences for text formatting and terminal colors.
M.colors = {
	reset = "\27[0m",
	bold = "\27[1m",
	dim = "\27[2m",
	italic = "\27[3m",
	underline = "\27[4m",
	black = "\27[30m",
	red = "\27[31m",
	green = "\27[32m",
	yellow = "\27[33m",
	blue = "\27[34m",
	magenta = "\27[35m",
	cyan = "\27[36m",
	white = "\27[37m",
	bg_black = "\27[40m",
	bg_red = "\27[41m",
	bg_green = "\27[42m",
	bg_yellow = "\27[43m",
	bg_blue = "\27[44m",
	bg_magenta = "\27[45m",
	bg_cyan = "\27[46m",
	bg_white = "\27[47m",
}

--- Checks whether stdout (fd 1) is an interactive terminal TTY.
--- @return boolean
local function is_stdout_tty()
	local uv = vim and (vim.uv or vim.loop)
	if uv and uv.guess_handle_type then
		local handle_type = uv.guess_handle_type(1)
		return handle_type == "tty"
	end
	return false
end

--- Force ANSI colors even when stdout is not a TTY (used by tests / redirected logs).
M.force_color = false

--- Wraps a text string with ANSI color styling codes (only when stdout is a TTY).
---
--- @param text string Text string to format.
--- @param color_code string ANSI color code from `cli.colors` (e.g. `cli.colors.cyan`).
--- @return string formatted_text Colorized string with reset suffix (or plain text if non-TTY).
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- print(cli.colorize("Success!", cli.colors.green))
function M.colorize(text, color_code)
	if not color_code or vim.env.NO_COLOR then
		return tostring(text or "")
	end
	if not M.force_color and not is_stdout_tty() then
		return tostring(text)
	end
	return color_code .. tostring(text) .. M.colors.reset
end

--- Strips all ANSI color and formatting escape sequences from a text string.
---
--- @param text string Text string containing ANSI escape sequences.
--- @return string plain_text Text without ANSI escape codes.
function M.strip_ansi(text)
	if not text then
		return ""
	end
	local str = tostring(text)
	str = str:gsub("\27%[[%d;]*[a-zA-Z]", "")
	str = str:gsub("\27%]%d+;.-%a", "")
	return str
end

-- ============================================================================
-- ASCII ART TITLE GENERATOR
-- ============================================================================

--- 5-row glyph map for generating clean ASCII art banners.
local ASCII_FONT = {
	A = { " ▄▀▄ ", "█───█", "█████", "█───█", "█───█" },
	B = { "████ ", "█───█", "████ ", "█───█", "████ " },
	C = { " ████", "█────", "█────", "█────", " ████" },
	D = { "████ ", "█───█", "█───█", "█───█", "████ " },
	E = { "█████", "█────", "████ ", "█────", "█████" },
	F = { "█████", "█────", "████ ", "█────", "█────" },
	G = { " ████", "█────", "█─███", "█───█", " ████" },
	H = { "█───█", "█───█", "█████", "█───█", "█───█" },
	I = { "█████", "  █  ", "  █  ", "  █  ", "█████" },
	J = { "█████", "   █ ", "   █ ", "█  █ ", " ██  " },
	K = { "█───█", "█──█ ", "███  ", "█──█ ", "█───█" },
	L = { "█────", "█────", "█────", "█────", "█████" },
	M = { "█───█", "██─██", "█─█─█", "█───█", "█───█" },
	N = { "█───█", "██──█", "█─█─█", "█──██", "█───█" },
	O = { " ███ ", "█───█", "█───█", "█───█", " ███ " },
	P = { "████ ", "█───█", "████ ", "█────", "█────" },
	Q = { " ███ ", "█───█", "█───█", "█──██", " ███ ▀" },
	R = { "████ ", "█───█", "████ ", "█──█ ", "█───█" },
	S = { " ████", "█────", " ███ ", "────█", "████ " },
	T = { "█████", "  █  ", "  █  ", "  █  ", "  █  " },
	U = { "█───█", "█───█", "█───█", "█───█", " ███ " },
	V = { "█───█", "█───█", "█───█", " █─█ ", "  █  " },
	W = { "█───█", "█───█", "█─█─█", "██─██", "█───█" },
	X = { "█───█", " █─█ ", "  █  ", " █─█ ", "█───█" },
	Y = { "█───█", " █─█ ", "  █  ", "  █  ", "  █  " },
	Z = { "█████", "   █ ", "  █  ", " █   ", "█████" },
	["0"] = { " ███ ", "█──██", "█─█─█", "██──█", " ███ " },
	["1"] = { "  ██ ", " █ █ ", "   █ ", "   █ ", " ████" },
	["2"] = { " ███ ", "█───█", "  ██ ", " █   ", "█████" },
	["3"] = { "████ ", "    █", " ███ ", "    █", "████ " },
	["4"] = { "█──█ ", "█──█ ", "█████", "   █ ", "   █ " },
	["5"] = { "█████", "█────", "████ ", "────█", "████ " },
	["6"] = { " ███ ", "█────", "████ ", "█───█", " ███ " },
	["7"] = { "█████", "   █ ", "  █  ", " █   ", " █   " },
	["8"] = { " ███ ", "█───█", " ███ ", "█───█", " ███ " },
	["9"] = { " ███ ", "█───█", " ████", "────█", " ███ " },
	[" "] = { "   ", "   ", "   ", "   ", "   " },
	["-"] = { "     ", "     ", " ███ ", "     ", "     " },
	["_"] = { "     ", "     ", "     ", "     ", "█████" },
	["!"] = { "  █  ", "  █  ", "  █  ", "     ", "  █  " },
	["?"] = { " ███ ", "█───█", "  ██ ", "     ", "  █  " },
	[":"] = { "     ", "  █  ", "     ", "  █  ", "     " },
	["."] = { "     ", "     ", "     ", "     ", "  █  " },
}

--- Generates a multi-line ASCII art title banner from a single text string parameter.
---
--- @param text string Text to convert into ASCII art banner.
--- @param opts table|nil Options table for formatting:
---   - `color` (string): ANSI color code (e.g. `cli.colors.cyan`).
---   - `subtitle` (string): Subtitle line placed below the banner.
---   - `border` (boolean): Surround title banner with border box (default false).
--- @return string ascii_banner Multi-line ASCII art banner.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local title = cli.ascii_title("NEOVIM", { color = cli.colors.cyan, subtitle = "Automation Suite" })
--- print(title)
function M.ascii_title(text, opts)
	opts = opts or {}
	text = tostring(text or "KRSNVIM"):upper()

	local rows = { "", "", "", "", "" }
	for i = 1, #text do
		local char = text:sub(i, i)
		local glyph = ASCII_FONT[char] or ASCII_FONT["?"]
		for r = 1, 5 do
			rows[r] = rows[r] .. glyph[r] .. " "
		end
	end

	local banner = table.concat(rows, "\n")
	if opts.color and opts.color ~= "" then
		banner = M.colorize(banner, opts.color)
	end

	if opts.subtitle and opts.subtitle ~= "" then
		local sub_text = "▸ " .. opts.subtitle
		banner = banner .. "\n  " .. (opts.color and M.colorize(sub_text, M.colors.yellow) or sub_text)
	end

	if opts.border then
		banner = M.box(banner, { title = "KRS BROWSER", style = "rounded" })
	end

	return banner
end

-- ============================================================================
-- FORMATTING HELPERS: BOX & TABLE
-- ============================================================================

--- Wraps text lines inside a stylized ASCII box container.
---
--- @param content string|string[] Single string or array of line strings.
--- @param opts table|nil Styling options (`title`, `style` = `"single"|"double"|"rounded"|"block"`).
--- @return string boxed Formatted container box text.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- print(cli.box({ "Status: Active", "Port: 8080" }, { title = "Server Info", style = "rounded" }))
function M.box(content, opts)
	opts = opts or {}
	local style = opts.style or "rounded"

	local border_styles = {
		single = { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" },
		double = { tl = "╔", tr = "╗", bl = "╚", br = "╝", h = "═", v = "║" },
		rounded = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
		block = { tl = "█", tr = "█", bl = "█", br = "█", h = "▀", v = "█" },
	}

	local b = border_styles[style] or border_styles.rounded
	local lines = {}
	if type(content) == "string" then
		for line in content:gmatch("([^\n]+)") do
			table.insert(lines, line)
		end
	else
		lines = content or {}
	end

	local max_len = 0
	for _, l in ipairs(lines) do
		local clean = l:gsub("\27%[[%d;]*m", "")
		if #clean > max_len then
			max_len = #clean
		end
	end

	if opts.title and #opts.title > max_len - 4 then
		max_len = #opts.title + 4
	end

	local top = b.tl .. b.h
	if opts.title then
		top = top .. " " .. opts.title .. " " .. b.h:rep(math.max(0, max_len - #opts.title - 2)) .. b.tr
	else
		top = top .. b.h:rep(max_len) .. b.tr
	end

	local out = { top }
	for _, l in ipairs(lines) do
		local clean = l:gsub("\27%[[%d;]*m", "")
		local pad = max_len - #clean
		table.insert(out, b.v .. " " .. l .. (" "):rep(math.max(0, pad)) .. " " .. b.v)
	end
	table.insert(out, b.bl .. b.h:rep(max_len + 2) .. b.br)

	return table.concat(out, "\n")
end

--- Formats tabular data into an aligned ASCII table with header row.
---
--- @param headers string[] Array of column header title strings.
--- @param rows table[] Array of row arrays matching columns.
--- @return string table_text Formatted table text.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local tbl = cli.table({ "ID", "Name", "Role" }, { { "1", "Alice", "Admin" }, { "2", "Bob", "User" } })
--- print(tbl)
function M.table(headers, rows)
	headers = headers or {}
	rows = rows or {}

	local col_widths = {}
	for i, h in ipairs(headers) do
		col_widths[i] = #tostring(h)
	end

	for _, row in ipairs(rows) do
		for i, val in ipairs(row) do
			local len = #tostring(val)
			if not col_widths[i] or len > col_widths[i] then
				col_widths[i] = len
			end
		end
	end

	local out = {}

	-- Header
	local header_parts = {}
	local separator_parts = {}
	for i, h in ipairs(headers) do
		local w = col_widths[i] or #h
		table.insert(header_parts, string.format("%-" .. w .. "s", h))
		table.insert(separator_parts, string.rep("─", w))
	end
	table.insert(out, "│ " .. table.concat(header_parts, " │ ") .. " │")
	table.insert(out, "├─" .. table.concat(separator_parts, "─┼─") .. "─┤")

	-- Rows
	for _, row in ipairs(rows) do
		local row_parts = {}
		for i, h in ipairs(headers) do
			local val = tostring(row[i] or "")
			local w = col_widths[i] or #val
			table.insert(row_parts, string.format("%-" .. w .. "s", val))
		end
		table.insert(out, "│ " .. table.concat(row_parts, " │ ") .. " │")
	end

	return table.concat(out, "\n")
end

-- ============================================================================
-- INTERACTIVE PROMPTS & SPINNER
-- ============================================================================

--- Displays a text input prompt with optional default value.
---
--- @param label string Prompt question label.
--- @param default_val string|nil Optional default value when input is empty.
--- @return string answer User input string or default value.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local name = cli.prompt("Enter your name", "Developer")
function M.prompt(label, default_val)
	local prompt_str = string.format("%s%s: ", label, default_val and (" [" .. default_val .. "]") or "")
	if vim and vim.fn and vim.fn.input then
		local input = vim.fn.input(prompt_str)
		if input == "" and default_val then
			return default_val
		end
		return input
	else
		io.write(prompt_str)
		local input = io.read()
		if (not input or input == "") and default_val then
			return default_val
		end
		return input or ""
	end
end

--- Displays an interactive Yes/No confirmation prompt.
---
--- @param label string Confirmation question.
--- @param default_bool boolean|nil Default choice (`true` for Y, `false` for N).
--- @return boolean confirmed `true` if user confirmed, `false` otherwise.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- if cli.confirm("Deploy to production?", false) then ... end
function M.confirm(label, default_bool)
	local hint = default_bool == true and "[Y/n]" or "[y/N]"
	local answer = M.prompt(label .. " " .. hint, default_bool == true and "y" or "n")
	return answer:lower():sub(1, 1) == "y"
end

--- Runs an animated loading spinner frame while executing a task.
---
--- @param message string Status message displayed next to the spinner.
--- @param work_fn function Function to execute during spinner run.
--- @return any result Return value of `work_fn`.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local res = cli.spinner("Building project assets...", function() return 42 end)
function M.spinner(message, work_fn)
	local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local idx = 1

	if vim and vim.notify then
		vim.notify("⏳ " .. message, vim.log.levels.INFO, { title = "CLI Task" })
	end

	local res = work_fn()

	if vim and vim.notify then
		vim.notify("✅ " .. message .. " (Done)", vim.log.levels.INFO, { title = "CLI Task" })
	end

	return res
end

-- ============================================================================
-- INTERACTIVE MENU SYSTEM (VIM KEYS + ARROWS + MOUSE SUPPORT)
-- ============================================================================

--- Displays an interactive selection menu with ASCII title header.
--- Supports Vim keys (`j`/`k`, `g`/`G`), Arrow keys (`Up`/`Down`), and Mouse clicks.
---
--- @param title string|table Header title text (or opts table with `title`, `subtitle`, `items`).
--- @param options string[]|table[] Array of string items or `{ label, value }` tables.
--- @param callback function|nil Callback function `callback(choice, index)` invoked on selection.
--- @return any choice Selected option item (or nil if cancelled).
--- @return number index Selected option index (1-N).
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- cli.menu("SELECT FRAMEWORK", { "React", "Vue", "Svelte", "Angular" }, function(choice, idx)
---     print("Picked:", choice, "at index:", idx)
--- end)
function M.menu(title, options, callback)
	local opts = {}
	if type(title) == "table" then
		opts = title
		options = opts.items or options or {}
		callback = callback or opts.callback
	else
		opts.title = title
	end

	opts.title = opts.title or "CLI MENU"
	opts.items = options or {}

	-- If running in interactive Neovim UI, launch floating modal with Vim, Arrow, and Mouse controls
	local has_ui = vim and vim.api and vim.api.nvim_list_uis and #vim.api.nvim_list_uis() > 0
	if has_ui and vim.api.nvim_open_win then
		local selected_idx = 1
		local items = opts.items

		local ascii_lines = {}
		local raw_banner = M.ascii_title(opts.title, { subtitle = opts.subtitle })
		for l in raw_banner:gmatch("([^\n]+)") do
			table.insert(ascii_lines, M.strip_ansi(l))
		end

		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].filetype = "krsmenu"
		vim.bo[buf].bufhidden = "wipe"

		local ns_id = vim.api.nvim_create_namespace("krs_cli_menu")

		local function render_menu()
			local content = {}
			for _, l in ipairs(ascii_lines) do
				table.insert(content, l)
			end
			table.insert(
				content,
				"────────────────────────────────────────────────────────"
			)
			table.insert(content, " Choose an option:")

			local selected_line_idx = #ascii_lines + 2
			for i, item in ipairs(items) do
				local label = type(item) == "table" and (item.label or item[1]) or tostring(item)
				if i == selected_idx then
					table.insert(content, string.format(" ▸ [%d] %s  ◄", i, label))
					selected_line_idx = #content - 1
				else
					table.insert(content, string.format("   [%d] %s", i, label))
				end
			end

			table.insert(
				content,
				"────────────────────────────────────────────────────────"
			)
			table.insert(
				content,
				" [j/k or ↑/↓]: Move  |  [Enter/Space]: Pick  |  [Mouse Click]: Pick  |  [q/Esc]: Cancel"
			)

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
			vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

			for l_idx = 0, #ascii_lines - 1 do
				pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "DiagnosticInfo", l_idx, 0, -1)
			end

			pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "Comment", #ascii_lines, 0, -1)
			pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "Title", #ascii_lines + 1, 0, -1)

			if selected_line_idx >= 0 and selected_line_idx < #content then
				pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "DiagnosticWarn", selected_line_idx, 0, -1)
			end

			pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "Comment", #content - 2, 0, -1)
			pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "Comment", #content - 1, 0, -1)
		end

		render_menu()

		local width = 64
		local height = #ascii_lines + #items + 5
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = math.min(width, vim.o.columns - 4),
			height = math.min(height, vim.o.lines - 4),
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			style = "minimal",
			border = "rounded",
			title = " 🦊 KRS Interactive Menu ",
			title_pos = "center",
		})

		local function confirm_choice()
			local idx = selected_idx
			local item = items[idx]
			pcall(vim.api.nvim_win_close, win, true)
			if callback then
				callback(item, idx)
			end
		end

		local function move_cursor(delta)
			selected_idx = selected_idx + delta
			if selected_idx < 1 then
				selected_idx = #items
			elseif selected_idx > #items then
				selected_idx = 1
			end
			render_menu()
		end

		local function mouse_click()
			local mouse_pos = vim.fn.getmousepos()
			if mouse_pos.winid == win then
				local line_num = mouse_pos.line
				local header_offset = #ascii_lines + 2
				local clicked_idx = line_num - header_offset
				if clicked_idx >= 1 and clicked_idx <= #items then
					selected_idx = clicked_idx
					render_menu()
					confirm_choice()
				end
			end
		end

		local map_opts = { buffer = buf, noremap = true, silent = true }

		-- Vim keybindings
		vim.keymap.set("n", "j", function()
			move_cursor(1)
		end, map_opts)
		vim.keymap.set("n", "k", function()
			move_cursor(-1)
		end, map_opts)
		vim.keymap.set("n", "g", function()
			selected_idx = 1
			render_menu()
		end, map_opts)
		vim.keymap.set("n", "G", function()
			selected_idx = #items
			render_menu()
		end, map_opts)

		-- Arrow keys
		vim.keymap.set("n", "<Down>", function()
			move_cursor(1)
		end, map_opts)
		vim.keymap.set("n", "<Up>", function()
			move_cursor(-1)
		end, map_opts)

		-- Selection
		vim.keymap.set("n", "<CR>", confirm_choice, map_opts)
		vim.keymap.set("n", "<Space>", confirm_choice, map_opts)

		-- Mouse support
		vim.keymap.set("n", "<LeftMouse>", mouse_click, map_opts)

		-- Cancel
		vim.keymap.set("n", "q", function()
			pcall(vim.api.nvim_win_close, win, true)
		end, map_opts)
		vim.keymap.set("n", "<Esc>", function()
			pcall(vim.api.nvim_win_close, win, true)
		end, map_opts)

		return
	else
		-- Standalone CLI fallback
		print("\n" .. M.ascii_title(opts.title, { subtitle = opts.subtitle, color = M.colors.cyan }))
		print(M.colorize("------------------------------------------", M.colors.cyan))
		for i, item in ipairs(opts.items) do
			local label = type(item) == "table" and (item.label or item[1]) or tostring(item)
			print(string.format("  " .. M.colorize("[%d]", M.colors.yellow) .. " %s", i, label))
		end
		print(M.colorize("------------------------------------------", M.colors.cyan))
		io.write(M.colorize("Select option (1-" .. #opts.items .. "): ", M.colors.cyan))
		local input = io.read()
		local num_str = input and input:match("%d+")
		local choice_num = num_str and tonumber(num_str)
		if choice_num and opts.items[choice_num] then
			local item = opts.items[choice_num]
			if callback then
				callback(item, choice_num)
			end
			return item, choice_num
		end
	end
end

--- Displays an interactive multi-selection checkbox list menu.
--- Supports Vim keys (`j`/`k`, `Space` toggle), Arrow keys (`Up`/`Down`), and Mouse clicks.
---
--- @param title string|table Header title text.
--- @param options string[] Array list of selectable text options.
--- @param callback function|nil Callback function `callback(selected_items)` invoked on submit.
--- @return string[] selected List of selected text options.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- cli.multi_select("SELECT PLUGINS", { "LSP", "DAP", "Linter", "Formatter" }, function(selected)
---     print("Selected count:", #selected)
--- end)
function M.multi_select(title, options, callback)
	local opts = {}
	if type(title) == "table" then
		opts = title
		options = opts.items or options or {}
		callback = callback or opts.callback
	else
		opts.title = title
	end

	opts.title = opts.title or "MULTI SELECT"
	opts.items = options or {}

	local has_ui = vim and vim.api and vim.api.nvim_list_uis and #vim.api.nvim_list_uis() > 0
	if has_ui and vim.api.nvim_open_win then
		local cursor_idx = 1
		local selected_state = {}
		local items = opts.items

		local ascii_lines = {}
		local raw_banner = M.ascii_title(opts.title, { subtitle = opts.subtitle })
		for l in raw_banner:gmatch("([^\n]+)") do
			table.insert(ascii_lines, M.strip_ansi(l))
		end

		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].filetype = "krsmultiselect"
		vim.bo[buf].bufhidden = "wipe"

		local function render_menu()
			local content = {}
			for _, l in ipairs(ascii_lines) do
				table.insert(content, l)
			end
			table.insert(
				content,
				"────────────────────────────────────────────────────────"
			)
			table.insert(content, " Toggle items with Space, press Enter to submit:")

			for i, item in ipairs(items) do
				local label = type(item) == "table" and (item.label or item[1]) or tostring(item)
				local chk = selected_state[i] and "[x]" or "[ ]"
				if i == cursor_idx then
					table.insert(content, string.format(" ▸ %s [%d] %s  ◄", chk, i, label))
				else
					table.insert(content, string.format("   %s [%d] %s", chk, i, label))
				end
			end

			table.insert(
				content,
				"────────────────────────────────────────────────────────"
			)
			table.insert(content, " [j/k or ↑/↓]: Move  |  [Space]: Toggle  |  [a]: Select All  |  [Enter]: Submit")

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
		end

		render_menu()

		local width = 64
		local height = #ascii_lines + #items + 5
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = math.min(width, vim.o.columns - 4),
			height = math.min(height, vim.o.lines - 4),
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			style = "minimal",
			border = "rounded",
			title = " 🦊 KRS Multi-Select ",
			title_pos = "center",
		})

		local function submit_selection()
			local selected = {}
			for i, item in ipairs(items) do
				if selected_state[i] then
					table.insert(selected, item)
				end
			end
			pcall(vim.api.nvim_win_close, win, true)
			if callback then
				callback(selected)
			end
		end

		local function move_cursor(delta)
			cursor_idx = cursor_idx + delta
			if cursor_idx < 1 then
				cursor_idx = #items
			elseif cursor_idx > #items then
				cursor_idx = 1
			end
			render_menu()
		end

		local function toggle_current()
			selected_state[cursor_idx] = not selected_state[cursor_idx]
			render_menu()
		end

		local function toggle_all()
			local all_on = true
			for i = 1, #items do
				if not selected_state[i] then
					all_on = false
					break
				end
			end
			for i = 1, #items do
				selected_state[i] = not all_on
			end
			render_menu()
		end

		local function mouse_click()
			local mouse_pos = vim.fn.getmousepos()
			if mouse_pos.winid == win then
				local line_num = mouse_pos.line
				local header_offset = #ascii_lines + 2
				local clicked_idx = line_num - header_offset
				if clicked_idx >= 1 and clicked_idx <= #items then
					cursor_idx = clicked_idx
					toggle_current()
				end
			end
		end

		local map_opts = { buffer = buf, noremap = true, silent = true }

		vim.keymap.set("n", "j", function()
			move_cursor(1)
		end, map_opts)
		vim.keymap.set("n", "k", function()
			move_cursor(-1)
		end, map_opts)
		vim.keymap.set("n", "<Down>", function()
			move_cursor(1)
		end, map_opts)
		vim.keymap.set("n", "<Up>", function()
			move_cursor(-1)
		end, map_opts)
		vim.keymap.set("n", "<Space>", toggle_current, map_opts)
		vim.keymap.set("n", "a", toggle_all, map_opts)
		vim.keymap.set("n", "<CR>", submit_selection, map_opts)
		vim.keymap.set("n", "<LeftMouse>", mouse_click, map_opts)
		vim.keymap.set("n", "q", function()
			pcall(vim.api.nvim_win_close, win, true)
		end, map_opts)
		vim.keymap.set("n", "<Esc>", function()
			pcall(vim.api.nvim_win_close, win, true)
		end, map_opts)

		return
	end
end

-- ============================================================================
-- ARGUMENT PARSER & HELP GENERATOR
-- ============================================================================

--- @class ParsedArgs
--- @field flags table<string, string|boolean> Map of `--flag` or `--key=value` parsed options.
--- @field positional string[] List of positional non-flag command line arguments.

--- Parses raw CLI arguments into flags (named options) and positional arguments.
--- Supports `--key=value`, `--flag` (`true`), `-f` (`true`), and raw positional strings.
---
--- @param raw_args string[]|nil Array of raw argument strings. Defaults to `arg` or `{}`.
--- @param schema table|nil Optional schema definition for flag validation.
--- @return ParsedArgs parsed Parsed flags and positional arguments structure.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local args = cli.parse_args({ "--env=production", "--verbose", "build" })
--- print(args.flags.env)     -- "production"
--- print(args.flags.verbose) -- true
--- print(args.positional[1]) -- "build"
function M.parse_args(raw_args, schema)
	raw_args = raw_args or arg or {}
	schema = schema or {}

	local parsed = {
		flags = {},
		positional = {},
	}

	for _, a in ipairs(raw_args) do
		if a:sub(1, 2) == "--" then
			local key, val = a:sub(3):match("^([^=]+)=(.*)$")
			if key then
				parsed.flags[key] = val
			else
				parsed.flags[a:sub(3)] = true
			end
		elseif a:sub(1, 1) == "-" and #a > 1 then
			parsed.flags[a:sub(2)] = true
		else
			table.insert(parsed.positional, a)
		end
	end

	return parsed
end

--- Generates a formatted `--help` text output string based on a CLI schema definition.
---
--- @param schema table Schema configuration specifying `name`, `description`, and `options`.
--- @return string help_text Formatted help document text.
---
--- @see [krsnvim-testing.lua](file:///c:/Users/Kristan/AppData/Local/nvim/docs/krsnvim-testing.lua)
---
--- @example
--- local help_doc = cli.help({
---     name = "build-script",
---     description = "Compiles project assets into dist/",
---     options = { env = "Target environment", minify = "Enable minification" }
--- })
--- print(help_doc)
function M.help(schema)
	schema = schema or {}
	local lines = {}
	table.insert(lines, M.ascii_title(schema.name or "KRSNVIM", { subtitle = schema.description }))
	table.insert(lines, "\nUsage: " .. (schema.name or "krsnvimscript") .. " [options] [arguments]")
	if schema.options then
		table.insert(lines, "\nOptions:")
		for opt, desc in pairs(schema.options) do
			table.insert(lines, string.format("  --%-15s %s", opt, desc))
		end
	end
	return table.concat(lines, "\n")
end

return M
