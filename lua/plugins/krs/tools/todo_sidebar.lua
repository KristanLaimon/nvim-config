-- ============================================================================
-- KRS PLUGIN: Todo & Comment Tags Right Sidebar (`plugins.krs.tools.todo_sidebar`)
-- ============================================================================
-- WHAT IT DOES
--   A docked right vertical sidebar (split = "right") that automatically discovers,
--   categorizes, and displays all TODOs and special comment tags across your project
--   or active buffer.
--
-- SUPPORTED COMMENT SYNTAXES (ANY LANGUAGE)
--   - Single-line: // (C/C++/JS/TS/Go/Rust/C#/Java/PHP), # (Python/Bash/Ruby/YAML),
--                  -- (Lua/SQL/Haskell), ; (Lisp/ASM/INI), % (LaTeX/Erlang)
--   - Multi-line:  /* ... */ (C/JS/TS/CSS/Rust/Go/Java), <!-- ... --> (HTML/Markdown/Vue),
--                  {- ... -} (Haskell), (* ... *) (OCaml/Pascal), """ / ''' (Python),
--                  --[[ ... ]] (Lua), and continuation lines (* TODO: ...).
--
-- SUPPORTED COMMENT TAGS & CATEGORIES
--   - TODO:       Tasks, reminders, future improvements
--   - FIXME/BUG:  Defects, broken behavior, bugs, issues to fix
--   - HACK:       Workarounds, temporary solutions, technical debt
--   - WARN:       Warnings, tricky logic, hazards, cautions
--   - NOTE/INFO:  Notes, architectural context, ideas, documentation
--   - PERF/OPTIM: Performance bottlenecks, optimization suggestions
--   - TEST:       Pending tests, assertions, mocks, test fixtures
--   - SAFETY/SEC: Memory safety, security alerts, authorization checks
--   - REVIEW:     Peer review notes, questions, code review comments
--   - DEPRECATED: Deprecated APIs slated for removal
--   - XXX:        Critical attention flags
--
-- EX COMMANDS
--   :TodoSidebar     -- Toggle the right TODO sidebar
--   :TodoToggle      -- Alias to toggle sidebar
--   :TodoRefresh     -- Force rescan workspace
--   :TodoSearch      -- Fuzzy search comments via Telescope
--   :TodoFilter      -- Open sidebar filtered to a specific tag
--
-- KEYMAPS (INSIDE SIDEBAR)
--   <CR>             -- Jump to file and line (focuses editor)
--   <Space>          -- Preview file and line (keeps focus in sidebar)
--   o                -- Jump to file and line, and close sidebar
--   c / <Tab>        -- Collapse / expand current file section
--   C                -- Collapse all / expand all files
--   f                -- Filter by comment tag (TODO, FIXME, WARN, etc.)
--   F                -- Clear active tag filter (show ALL)
--   b                -- Toggle scope between Project and Active Buffer
--   r                -- Refresh / rescan comments
--   q / <Esc>        -- Close sidebar
--   ?                -- Toggle keyboard shortcuts help
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local project = lazy_req("krs.core.project")

local M = {}

M.settings = {
	width = 44,
	auto_refresh_on_save = true,
	notify_title = "KRS Todo Sidebar",
	default_scope = "project", -- "project" or "buffer"
}

--- Tag definitions, metadata, icons, and visual styles
M.TAGS = {
	TODO = { name = "TODO", icon = "", hl = "KrsTodoTag_TODO", category = "Task" },
	FIXME = { name = "FIXME", icon = "", hl = "KrsTodoTag_FIXME", category = "Defect" },
	BUG = { name = "BUG", icon = "", hl = "KrsTodoTag_BUG", category = "Defect" },
	FIX = { name = "FIX", icon = "", hl = "KrsTodoTag_FIXME", category = "Defect" },
	ISSUE = { name = "ISSUE", icon = "", hl = "KrsTodoTag_BUG", category = "Defect" },
	HACK = { name = "HACK", icon = "", hl = "KrsTodoTag_HACK", category = "Workaround" },
	WARN = { name = "WARN", icon = "", hl = "KrsTodoTag_WARN", category = "Warning" },
	WARNING = { name = "WARNING", icon = "", hl = "KrsTodoTag_WARN", category = "Warning" },
	CAUTION = { name = "CAUTION", icon = "", hl = "KrsTodoTag_WARN", category = "Warning" },
	NOTE = { name = "NOTE", icon = "", hl = "KrsTodoTag_NOTE", category = "Note" },
	INFO = { name = "INFO", icon = "", hl = "KrsTodoTag_INFO", category = "Note" },
	IDEA = { name = "IDEA", icon = "💡", hl = "KrsTodoTag_NOTE", category = "Note" },
	DOC = { name = "DOC", icon = "󰈙", hl = "KrsTodoTag_INFO", category = "Note" },
	PERF = { name = "PERF", icon = "⚡", hl = "KrsTodoTag_PERF", category = "Performance" },
	OPTIM = { name = "OPTIM", icon = "⚡", hl = "KrsTodoTag_PERF", category = "Performance" },
	OPTIMIZE = { name = "OPTIMIZE", icon = "⚡", hl = "KrsTodoTag_PERF", category = "Performance" },
	TEST = { name = "TEST", icon = "󰙨", hl = "KrsTodoTag_TEST", category = "Testing" },
	TESTING = { name = "TESTING", icon = "󰙨", hl = "KrsTodoTag_TEST", category = "Testing" },
	REVIEW = { name = "REVIEW", icon = "󰒡", hl = "KrsTodoTag_REVIEW", category = "Review" },
	DEPRECATED = { name = "DEPRECATED", icon = "󰮆", hl = "KrsTodoTag_DEPRECATED", category = "Deprecated" },
	SAFETY = { name = "SAFETY", icon = "🛡️", hl = "KrsTodoTag_SAFETY", category = "Safety" },
	SECURITY = { name = "SECURITY", icon = "🛡️", hl = "KrsTodoTag_SAFETY", category = "Safety" },
	AUDIT = { name = "AUDIT", icon = "🛡️", hl = "KrsTodoTag_SAFETY", category = "Safety" },
	XXX = { name = "XXX", icon = "⚠️", hl = "KrsTodoTag_FIXME", category = "Warning" },
}

M.TAG_ORDER = {
	"TODO",
	"FIXME",
	"BUG",
	"HACK",
	"WARN",
	"NOTE",
	"PERF",
	"TEST",
	"SAFETY",
	"REVIEW",
	"DEPRECATED",
	"XXX",
}

--- Internal state
M.state = {
	win = nil,
	buf = nil,
	last_code_win = nil,
	items = {},
	collapsed_files = {},
	filter_tag = nil,
	scope = "project",
	is_scanning = false,
	show_help = false,
	row_map = {},
}

local NS = vim.api.nvim_create_namespace("krs_todo_sidebar")

-- ============================================================================
-- HIGHLIGHT SETUP
-- ============================================================================

local function setup_highlights()
	local hl_definitions = {
		KrsTodoHeader = { fg = "#89b4fa", bold = true },
		KrsTodoDivider = { fg = "#45475a" },
		KrsTodoFile = { fg = "#89dceb", bold = true },
		KrsTodoFileCount = { fg = "#6c7086" },
		KrsTodoLineNr = { fg = "#7f849c" },
		KrsTodoText = { fg = "#cdd6f4" },
		KrsTodoHelp = { fg = "#a6adc8" },
		KrsTodoScopeBadge = { fg = "#f9e2af", bold = true },
		KrsTodoFilterBadge = { fg = "#fab387", bold = true },

		-- Tag specific colors
		KrsTodoTag_TODO = { fg = "#89b4fa", bold = true },
		KrsTodoTag_FIXME = { fg = "#f38ba8", bold = true },
		KrsTodoTag_BUG = { fg = "#f38ba8", bold = true },
		KrsTodoTag_HACK = { fg = "#fab387", bold = true },
		KrsTodoTag_WARN = { fg = "#f9e2af", bold = true },
		KrsTodoTag_NOTE = { fg = "#a6e3a1", bold = true },
		KrsTodoTag_INFO = { fg = "#94e2d5", bold = true },
		KrsTodoTag_PERF = { fg = "#cba6f7", bold = true },
		KrsTodoTag_TEST = { fg = "#b4befe", bold = true },
		KrsTodoTag_SAFETY = { fg = "#eba0ac", bold = true },
		KrsTodoTag_REVIEW = { fg = "#74c7ec", bold = true },
		KrsTodoTag_DEPRECATED = { fg = "#6c7086", italic = true },
	}

	for group, spec in pairs(hl_definitions) do
		spec.default = true
		vim.api.nvim_set_hl(0, group, spec)
	end
end

-- ============================================================================
-- PARSING ENGINE
-- ============================================================================

--- Parses a raw line string from ripgrep or buffer into a structured comment item.
--- @param line_str string In format "file:line:col:content" or raw line content with line/file provided
--- @param default_file? string
--- @param default_line? integer
--- @return table|nil item
function M.parse_comment_line(line_str, default_file, default_line)
	local file, line_nr, col, content
	if default_file and default_line then
		file = default_file
		line_nr = default_line
		col = 1
		content = line_str
	else
		file, line_nr, col, content = line_str:match("^([^:]+):(%d+):(%d+):(.*)$")
		if not file then
			return nil
		end
		line_nr = tonumber(line_nr)
		col = tonumber(col)
	end

	-- Identify comment prefix
	local prefixes = { "//", "#", "--", "/*", "*", "<!--", "{-", "(*", ";", "%", '"""', "'''" }
	local prefix_end = 0
	local found_p = nil
	for _, p in ipairs(prefixes) do
		local s, e = content:find(p, 1, true)
		if s and (prefix_end == 0 or s < prefix_end) then
			-- Avoid Lua table length operator `#` false positive (e.g. `local len = #items`)
			if p == "#" and file:match("%.lua$") and s > 1 then
				local char_before = content:sub(s - 1, s - 1)
				if char_before:match("[%w_%)%]]") then
					s = nil
				end
			end
			if s then
				prefix_end = e
				found_p = p
			end
		end
	end

	if prefix_end == 0 and not found_p then
		return nil
	end

	local comment_body = content:sub(prefix_end + 1)
	local comment_upper = comment_body:upper()

	for _, tag in ipairs(M.TAG_ORDER) do
		local s, e = comment_upper:find("%f[%a]" .. tag .. "%f[^%a]")
		if s then
			local pre = comment_body:sub(1, s - 1)
			-- Preceding characters between comment marker and tag must only be spaces, dashes, *, or @
			if pre:match("^[%s%-%*@]*$") then
				local after = comment_body:sub(e + 1)
				local extra = after:match("^%s*(%b())")
				if extra then
					after = after:sub(#extra + 1)
				end
				local text = after
					:gsub("^%s*[:%-%s]%s*", "")
					:gsub("%s*%*/%s*$", "")
					:gsub("%s*%-%->%s*$", "")
					:gsub("%s*%-%-%]%s*$", "")
					:gsub('%s*"""%s*$', "")
					:gsub([=[%s*'''%s*$]=], "")
					:gsub("%s+$", "")

				local tag_def = M.TAGS[tag] or { name = tag, icon = "", hl = "KrsTodoTag_TODO" }

				return {
					file = file,
					line = line_nr,
					col = col or 1,
					tag = tag,
					tag_name = tag_def.name,
					icon = tag_def.icon,
					hl = tag_def.hl,
					extra = extra,
					text = (text and text ~= "") and text or "(no description)",
					raw = content,
				}
			end
		end
	end

	return nil
end

-- ============================================================================
-- SCANNING ENGINE (ASYNCHRONOUS RIPGREP + BUFFER SCAN)
-- ============================================================================

--- Runs an asynchronous scan for TODO comments across workspace or active buffer.
--- @param opts? { scope?: "project"|"buffer", on_done?: fun(items: table[]) }
function M.scan(opts, on_done)
	opts = opts or {}
	local scope = opts.scope or M.state.scope or "project"
	M.state.scope = scope
	M.state.is_scanning = true

	if scope == "buffer" then
		local cur_buf = vim.api.nvim_get_current_buf()
		local file = vim.api.nvim_buf_get_name(cur_buf)
		if file == "" or vim.bo[cur_buf].buftype ~= "" then
			M.state.items = {}
			M.state.is_scanning = false
			if on_done then
				on_done(M.state.items)
			end
			M.render()
			return
		end

		local lines = vim.api.nvim_buf_get_lines(cur_buf, 0, -1, false)
		local rel_file = vim.fn.fnamemodify(file, ":.")
		local items = {}
		for i, line in ipairs(lines) do
			local item = M.parse_comment_line(line, rel_file, i)
			if item then
				table.insert(items, item)
			end
		end

		M.state.items = items
		M.state.is_scanning = false
		if on_done then
			on_done(items)
		end
		M.render()
		return
	end

	-- Scope: "project" via ripgrep
	local root_dir = project.root() or vim.fn.getcwd()
	local tag_pattern = table.concat(M.TAG_ORDER, "|")
	local rg_pattern = [=[(//|#|--|/\*|[*]|<!--|[{]-|\(\*|"""|'''|;|%)\s*[@]?\b(]=] .. tag_pattern .. [=[)\b]=]

	local cmd = {
		"rg",
		"--column",
		"--line-number",
		"--no-heading",
		"--color=never",
		"--hidden",
		"--glob=!.git/*",
		"--glob=!node_modules/*",
		"--glob=!vendor/*",
		"--glob=!.krsnvim/*",
		"--glob=!dist/*",
		"--glob=!build/*",
		"--glob=!target/*",
		"--glob=!.next/*",
		"--glob=!.nuxt/*",
		"--glob=!.cache/*",
		"--glob=!.local/*",
		"--glob=!lazy/*",
		"--glob=!*.min.js",
		"--glob=!*.min.css",
		"-i",
		rg_pattern,
		root_dir,
	}

	vim.system(cmd, { text = true }, function(obj)
		vim.schedule(function()
			M.state.is_scanning = false
			if obj.code ~= 0 and obj.code ~= 1 then
				-- Ripgrep failed or missing; fallback to active buffer
				vim.notify("Ripgrep scan failed, falling back to open buffers", vim.log.levels.WARN, {
					title = M.settings.notify_title,
				})
				M.state.items = {}
				M.render()
				return
			end

			local stdout = obj.stdout or ""
			local raw_lines = vim.split(stdout, "\n", { trimempty = true })
			local items = {}

			for _, l in ipairs(raw_lines) do
				local item = M.parse_comment_line(l)
				if item then
					-- Make file path relative to project root
					local rel = item.file
					if rel:sub(1, #root_dir) == root_dir then
						rel = rel:sub(#root_dir + 2)
					end
					item.file = rel
					table.insert(items, item)
				end
			end

			M.state.items = items
			if on_done then
				on_done(items)
			end
			M.render()
		end)
	end)
end

-- ============================================================================
-- SIDEBAR WINDOW & RENDERING
-- ============================================================================

--- Resolves or creates the right sidebar buffer and window.
--- @return integer win, integer buf
function M.open_window()
	if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
		return M.state.win, M.state.buf
	end

	-- Save reference to the active code window before opening sidebar
	local cur_win = vim.api.nvim_get_current_win()
	local cur_buf = vim.api.nvim_win_get_buf(cur_win)
	if vim.bo[cur_buf].buftype == "" and vim.bo[cur_buf].filetype ~= "krs_todo_sidebar" then
		M.state.last_code_win = cur_win
	end

	local buf = vim.api.nvim_create_buf(false, true)
	M.state.buf = buf
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "krs_todo_sidebar"
	vim.bo[buf].modifiable = false

	local total_cols = vim.o.columns
	local width = math.min(52, math.max(36, math.floor(total_cols * 0.28)))

	local win = vim.api.nvim_open_win(buf, true, {
		win = -1,
		split = "right",
		width = width,
	})
	M.state.win = win

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].winfixwidth = true

	M.bind_keymaps(buf)

	-- Handle window close cleanly
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			M.state.win = nil
			M.state.buf = nil
		end,
	})

	return win, buf
end

--- Renders the sidebar contents with grouped files, highlights, and status.
function M.render()
	if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
		return
	end

	local buf = M.state.buf
	local win = M.state.win
	local lines = {}
	local highlights = {} -- Array of { line, col_start, col_end, hl_group }
	M.state.row_map = {}

	local function add_line(text, hl_list, row_meta)
		table.insert(lines, text)
		local line_idx = #lines - 1 -- 0-based for nvim_buf_set_extmark
		if hl_list then
			for _, h in ipairs(hl_list) do
				table.insert(highlights, {
					line = line_idx,
					col_start = h[1],
					col_end = h[2],
					hl = h[3],
				})
			end
		end
		if row_meta then
			M.state.row_map[#lines] = row_meta
		end
	end

	-- 1. Header
	local total_count = #M.state.items
	local scope_label = M.state.scope == "buffer" and "Buffer Scope" or "Project Scope"
	local header_title = string.format(" 📝 Comments & TODOs (%d)", total_count)
	add_line(header_title, { { 0, #header_title, "KrsTodoHeader" } })

	local divider = " "
		.. string.rep(
			"─",
			math.max(34, vim.api.nvim_win_is_valid(win or 0) and (vim.api.nvim_win_get_width(win) - 2) or 40)
		)
	add_line(divider, { { 0, #divider, "KrsTodoDivider" } })

	-- 2. Scope & Filter Pill
	local scope_pill = string.format(" 󰈔 [%s]", scope_label)
	local filter_pill = M.state.filter_tag and string.format("  🔍 Filter: [%s]", M.state.filter_tag) or ""
	add_line(scope_pill .. filter_pill, {
		{ 0, #scope_pill, "KrsTodoScopeBadge" },
		{ #scope_pill, #(scope_pill .. filter_pill), "KrsTodoFilterBadge" },
	})

	-- 3. Category Counts
	local counts = {}
	for _, item in ipairs(M.state.items) do
		counts[item.tag] = (counts[item.tag] or 0) + 1
	end

	local pill_line = " "
	local pill_hls = {}
	for _, tag in ipairs({ "TODO", "FIXME", "BUG", "WARN", "NOTE", "PERF", "TEST", "HACK" }) do
		if counts[tag] and counts[tag] > 0 then
			local tag_def = M.TAGS[tag] or { icon = "", hl = "KrsTodoTag_TODO" }
			local pill = string.format("%s %s:%d  ", tag_def.icon, tag, counts[tag])
			local s = #pill_line
			pill_line = pill_line .. pill
			table.insert(pill_hls, { s, #pill_line - 2, tag_def.hl })
		end
	end
	if #pill_line > 2 then
		add_line(pill_line, pill_hls)
	end

	add_line(divider, { { 0, #divider, "KrsTodoDivider" } })

	-- 4. Loading indicator or Empty State
	if M.state.is_scanning then
		add_line(" 󰑮 Scanning for comments in background...", { { 0, 42, "KrsTodoHelp" } })
	elseif total_count == 0 then
		add_line(" 󰋽 No comment tags found in " .. scope_label:lower() .. ".", { { 0, 46, "KrsTodoHelp" } })
		add_line("   (Try adding // TODO: or -- NOTE: in your code)", { { 0, 50, "KrsTodoLineNr" } })
	else
		-- 5. Group by File
		local files_map = {}
		local files_list = {}
		for _, item in ipairs(M.state.items) do
			-- Apply tag filter if set
			if not M.state.filter_tag or item.tag == M.state.filter_tag then
				if not files_map[item.file] then
					files_map[item.file] = {}
					table.insert(files_list, item.file)
				end
				table.insert(files_map[item.file], item)
			end
		end

		table.sort(files_list)

		for _, file in ipairs(files_list) do
			local file_items = files_map[file]
			local is_collapsed = M.state.collapsed_files[file] == true
			local arrow = is_collapsed and "▶" or "▼"
			local file_hdr = string.format(" %s  %s (%d)", arrow, file, #file_items)

			add_line(file_hdr, {
				{ 1, 4, "KrsTodoTag_TODO" },
				{ 4, #file_hdr - (#tostring(#file_items) + 3), "KrsTodoFile" },
				{ #file_hdr - (#tostring(#file_items) + 3), #file_hdr, "KrsTodoFileCount" },
			}, { type = "file", file = file })

			if not is_collapsed then
				for _, item in ipairs(file_items) do
					local line_nr_str = string.format("%4d", item.line)
					local tag_display = string.format("[%s]", item.tag)
					local extra_str = item.extra and (item.extra .. " ") or ""
					local text_preview = extra_str .. item.text
					-- Limit text width
					if #text_preview > 40 then
						text_preview = text_preview:sub(1, 37) .. "..."
					end

					local row_text = string.format("   %s  %s %s %s", line_nr_str, item.icon, tag_display, text_preview)

					local s_nr = 3
					local e_nr = s_nr + #line_nr_str
					local s_icon = e_nr + 2
					local s_tag = s_icon + #item.icon + 1
					local e_tag = s_tag + #tag_display
					local s_text = e_tag + 1
					local e_text = #row_text

					add_line(row_text, {
						{ s_nr, e_nr, "KrsTodoLineNr" },
						{ s_icon, e_tag, item.hl },
						{ s_text, e_text, "KrsTodoText" },
					}, {
						type = "item",
						file = item.file,
						line = item.line,
						col = item.col,
						tag = item.tag,
					})
				end
				-- Empty row between files
				add_line("", nil)
			end
		end
	end

	-- 6. Footer / Keymap Help
	add_line(divider, { { 0, #divider, "KrsTodoDivider" } })
	if M.state.show_help then
		add_line(" ⌨️  KEYMAP HELP:", { { 0, 16, "KrsTodoHeader" } })
		add_line("   <CR>     Jump to line in code editor", { { 3, 7, "KrsTodoTag_TODO" } })
		add_line("   <Space>  Preview line (keep focus in sidebar)", { { 3, 10, "KrsTodoTag_TODO" } })
		add_line("   o        Jump to line and close sidebar", { { 3, 4, "KrsTodoTag_TODO" } })
		add_line("   c / Tab  Fold / unfold file section", { { 3, 10, "KrsTodoTag_TODO" } })
		add_line("   C        Fold all / unfold all files", { { 3, 4, "KrsTodoTag_TODO" } })
		add_line("   f        Filter by comment tag (TODO/FIXME/...)", { { 3, 4, "KrsTodoTag_TODO" } })
		add_line("   F        Clear filter (show all)", { { 3, 4, "KrsTodoTag_TODO" } })
		add_line("   b        Toggle scope (Project <-> Buffer)", { { 3, 4, "KrsTodoTag_TODO" } })
		add_line("   r        Refresh & rescan workspace", { { 3, 4, "KrsTodoTag_TODO" } })
		add_line("   q / Esc  Close sidebar", { { 3, 10, "KrsTodoTag_TODO" } })
	else
		local quick_help = " [CR] Jump  [c] Fold  [f] Filter  [b] Scope  [r] Scan  [?] Help"
		add_line(quick_help, { { 0, #quick_help, "KrsTodoHelp" } })
	end

	-- Write buffer lines
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	-- Apply highlights via extmarks
	vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	for _, h in ipairs(highlights) do
		pcall(vim.api.nvim_buf_set_extmark, buf, NS, h.line, math.max(0, h.col_start), {
			end_col = math.min(#lines[h.line + 1] or 0, h.col_end),
			hl_group = h.hl,
		})
	end
end

-- ============================================================================
-- NAVIGATION & INTERACTION
-- ============================================================================

--- Finds a target code window to open files in.
--- @return integer win
local function get_target_code_window()
	if M.state.last_code_win and vim.api.nvim_win_is_valid(M.state.last_code_win) then
		return M.state.last_code_win
	end

	-- Find first non-sidebar, non-dock, non-float window in current tab
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if w ~= M.state.win then
			local b = vim.api.nvim_win_get_buf(w)
			local bt = vim.bo[b].buftype
			local ft = vim.bo[b].filetype
			local cfg = vim.api.nvim_win_get_config(w)
			if (not cfg.relative or cfg.relative == "") and bt == "" and ft ~= "neo-tree" and ft ~= "krs_todo_sidebar" then
				M.state.last_code_win = w
				return w
			end
		end
	end

	-- If none found, create a split to the left of the sidebar
	vim.cmd("wincmd h")
	local new_win = vim.api.nvim_get_current_win()
	M.state.last_code_win = new_win
	return new_win
end

--- Jumps to the item under the cursor in the code editor.
--- @param close_sidebar boolean Whether to close the sidebar after jumping
--- @param keep_focus boolean Whether to restore focus back to the sidebar (for preview)
function M.jump_to_current(close_sidebar, keep_focus)
	if not M.state.win or not vim.api.nvim_win_is_valid(M.state.win) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(M.state.win)
	local row = cursor[1]
	local meta = M.state.row_map[row]

	if not meta then
		return
	end

	if meta.type == "file" then
		-- Toggle collapse if cursor is on file header
		M.state.collapsed_files[meta.file] = not M.state.collapsed_files[meta.file]
		M.render()
		return
	end

	if meta.type ~= "item" then
		return
	end

	local target_win = get_target_code_window()
	local root_dir = project.root() or vim.fn.getcwd()
	local full_path = meta.file:sub(1, 1) == "/" and meta.file or (root_dir .. "/" .. meta.file)

	if vim.fn.filereadable(full_path) == 0 then
		vim.notify("File not readable: " .. meta.file, vim.log.levels.WARN, { title = M.settings.notify_title })
		return
	end

	if close_sidebar then
		M.close()
	end

	vim.api.nvim_set_current_win(target_win)
	vim.cmd("edit " .. vim.fn.fnameescape(full_path))
	pcall(vim.api.nvim_win_set_cursor, target_win, { meta.line, math.max(0, (meta.col or 1) - 1) })
	vim.cmd("normal! zz")

	if keep_focus and not close_sidebar and M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
		vim.api.nvim_set_current_win(M.state.win)
	end
end

--- Binds interactive keymaps to the sidebar buffer.
--- @param buf integer
function M.bind_keymaps(buf)
	local function map(keys, fn, desc)
		local list = type(keys) == "table" and keys or { keys }
		for _, key in ipairs(list) do
			vim.keymap.set("n", key, fn, { buffer = buf, noremap = true, silent = true, desc = desc })
		end
	end

	-- Jump actions
	map("<CR>", function()
		M.jump_to_current(false, false)
	end, "Jump to comment in code window")

	map("<Space>", function()
		M.jump_to_current(false, true)
	end, "Preview comment in code window (keep sidebar focus)")

	map("o", function()
		M.jump_to_current(true, false)
	end, "Jump to comment and close sidebar")

	-- Folding
	map({ "c", "<Tab>" }, function()
		local cursor = vim.api.nvim_win_get_cursor(M.state.win)
		local meta = M.state.row_map[cursor[1]]
		if meta and meta.file then
			M.state.collapsed_files[meta.file] = not M.state.collapsed_files[meta.file]
			M.render()
		end
	end, "Toggle collapse of current file")

	map("C", function()
		local all_collapsed = true
		for _, item in ipairs(M.state.items) do
			if not M.state.collapsed_files[item.file] then
				all_collapsed = false
				break
			end
		end

		local new_state = not all_collapsed
		for _, item in ipairs(M.state.items) do
			M.state.collapsed_files[item.file] = new_state
		end
		M.render()
	end, "Toggle collapse all files")

	-- Filter by tag
	map("f", function()
		M.filter_prompt()
	end, "Filter by comment tag")

	map("F", function()
		M.state.filter_tag = nil
		M.render()
		vim.notify("Filter cleared (showing all tags)", vim.log.levels.INFO, { title = M.settings.notify_title })
	end, "Clear tag filter")

	-- Scope toggle
	map("b", function()
		M.state.scope = (M.state.scope == "project") and "buffer" or "project"
		M.scan({ scope = M.state.scope })
	end, "Toggle scope (Project vs Buffer)")

	-- Refresh
	map("r", function()
		M.scan()
	end, "Rescan comments")

	-- Help
	map("?", function()
		M.state.show_help = not M.state.show_help
		M.render()
	end, "Toggle help footer")

	-- Close
	map({ "q", "<Esc>" }, function()
		M.close()
	end, "Close Todo Sidebar")
end

--- Opens a prompt / picker to filter items by tag.
function M.filter_prompt()
	local options = { "ALL (Clear Filter)" }
	for _, tag in ipairs(M.TAG_ORDER) do
		local tag_def = M.TAGS[tag]
		table.insert(options, string.format("%s %s", tag_def.icon, tag))
	end

	vim.ui.select(options, { prompt = "Filter comments by tag:" }, function(choice)
		if not choice then
			return
		end
		if choice:match("^ALL") then
			M.state.filter_tag = nil
		else
			local selected_tag = choice:match("%s([%a_]+)$")
			M.state.filter_tag = selected_tag
		end
		M.render()
	end)
end

-- ============================================================================
-- TELESCOPE INTEGRATION
-- ============================================================================

--- Opens a Telescope fuzzy finder over all discovered comments.
function M.search_telescope()
	local has_telescope, pickers = pcall(require, "telescope.pickers")
	if not has_telescope then
		vim.notify("Telescope is not installed", vim.log.levels.WARN, { title = M.settings.notify_title })
		return
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local function open_picker_with_items(items)
		pickers
			.new({}, {
				prompt_title = " 📝 Search Todo & Comments ",
				finder = finders.new_table({
					results = items,
					entry_maker = function(entry)
						local display =
							string.format("%s [%s] %s:%d — %s", entry.icon, entry.tag, entry.file, entry.line, entry.text)
						return {
							value = entry,
							display = display,
							ordinal = string.format("%s %s %s %s", entry.tag, entry.file, entry.text, entry.extra or ""),
							filename = entry.file,
							lnum = entry.line,
							col = entry.col,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				previewer = conf.qflist_previewer({}),
				attach_mappings = function(prompt_bufnr, _)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection and selection.value then
							local root_dir = project.root() or vim.fn.getcwd()
							local full_path = selection.value.file:sub(1, 1) == "/" and selection.value.file
								or (root_dir .. "/" .. selection.value.file)
							vim.cmd("edit " .. vim.fn.fnameescape(full_path))
							pcall(vim.api.nvim_win_set_cursor, 0, { selection.value.line, math.max(0, selection.value.col - 1) })
							vim.cmd("normal! zz")
						end
					end)
					return true
				end,
			})
			:find()
	end

	if #M.state.items > 0 then
		open_picker_with_items(M.state.items)
	else
		M.scan({
			on_done = function(items)
				open_picker_with_items(items)
			end,
		})
	end
end

-- ============================================================================
-- PUBLIC API & LIFECYCLE
-- ============================================================================

--- Checks if the sidebar window is currently open.
--- @return boolean
function M.is_open()
	return M.state.win ~= nil and vim.api.nvim_win_is_valid(M.state.win)
end

--- Opens the right sidebar and triggers an initial scan.
function M.open()
	M.open_window()
	M.render()
	M.scan()
end

--- Closes the right sidebar cleanly.
function M.close()
	if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
		pcall(vim.api.nvim_win_close, M.state.win, true)
	end
	M.state.win = nil
	M.state.buf = nil

	-- Restore focus to last active code window if valid
	if M.state.last_code_win and vim.api.nvim_win_is_valid(M.state.last_code_win) then
		pcall(vim.api.nvim_set_current_win, M.state.last_code_win)
	end
end

--- Toggles the right sidebar on/off.
function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

--- Refreshes the comments and renders the sidebar.
function M.refresh()
	M.scan()
end

--- Filters the sidebar by a specific tag.
--- @param tag string
function M.filter(tag)
	if tag and tag ~= "" then
		M.state.filter_tag = tag:upper()
	else
		M.state.filter_tag = nil
	end
	if not M.is_open() then
		M.open()
	else
		M.render()
	end
end

--- Setup and registration of user commands and autocmds.
function M.setup()
	setup_highlights()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("krs_todo_sidebar_hl", { clear = true }),
		callback = setup_highlights,
	})

	-- Register Ex commands
	vim.api.nvim_create_user_command("TodoSidebar", function()
		M.toggle()
	end, { desc = "Toggle Todo & Comment Tags right sidebar" })

	vim.api.nvim_create_user_command("TodoToggle", function()
		M.toggle()
	end, { desc = "Toggle Todo & Comment Tags right sidebar" })

	vim.api.nvim_create_user_command("TodoRefresh", function()
		M.refresh()
	end, { desc = "Rescan and refresh Todo & Comment Tags" })

	vim.api.nvim_create_user_command("TodoSearch", function()
		M.search_telescope()
	end, { desc = "Fuzzy search Todo comments via Telescope" })

	vim.api.nvim_create_user_command("TodoFilter", function(opts)
		M.filter(opts.args)
	end, {
		nargs = "?",
		complete = function()
			return M.TAG_ORDER
		end,
		desc = "Open Todo sidebar filtered to a tag (e.g. :TodoFilter FIXME)",
	})

	-- Bind default non-occupied keymaps: <leader>td and <C-S-o>
	vim.keymap.set("n", "<leader>td", function()
		M.toggle()
	end, { noremap = true, silent = true, desc = "Toggle Todo Sidebar (Right)" })

	vim.keymap.set("n", "<C-S-o>", function()
		M.toggle()
	end, { noremap = true, silent = true, desc = "Toggle Todo Sidebar (Right)" })

	-- Debounced auto-refresh on save when sidebar is open
	if M.settings.auto_refresh_on_save then
		local timer = nil
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = vim.api.nvim_create_augroup("krs_todo_sidebar_autorefresh", { clear = true }),
			callback = function()
				if M.is_open() then
					if timer then
						timer:stop()
						timer:close()
						timer = nil
					end
					timer = (vim.uv or vim.loop).new_timer()
					if timer then
						timer:start(
							400,
							0,
							vim.schedule_wrap(function()
								if timer then
									timer:stop()
									timer:close()
									timer = nil
								end
								if M.is_open() then
									M.scan()
								end
							end)
						)
					end
				end
			end,
		})
	end
end

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

local plugin_spec = {
	name = "krs_todo_sidebar",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = false,
	cmd = { "TodoSidebar", "TodoToggle", "TodoRefresh", "TodoSearch", "TodoFilter" },
	keys = {
		{ "<leader>td", desc = "Toggle Todo Sidebar (Right)" },
		{ "<C-S-o>", desc = "Toggle Todo Sidebar (Right)" },
	},
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
