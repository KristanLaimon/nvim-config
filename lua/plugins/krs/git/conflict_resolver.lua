-- ============================================================================
-- KRS PLUGIN: Git Conflict Resolver (3-Way Merge Editor)
-- ============================================================================
-- WHAT IT DOES
--   A full-screen tiled 3-way merge conflict editor (like VSCode & DAP Debugger):
--     1. Sidebar (left): Conflicted files list with conflict counts & live status.
--     2. Top-Left: Current branch (HEAD / Ours) [Read-Only].
--     3. Top-Right: Incoming branch (Theirs) [Read-Only].
--     4. Bottom: Result (Final Merged) [THE ONLY EDITABLE WINDOW].
--
-- PANEL NAVIGATION SHORTCUTS
--   In Current/Incoming/Sidebar (Read-only panels):
--     c           Jump to Current panel (top-left)
--     i           Jump to Incoming panel (top-right)
--     r           Jump to Result panel (bottom)
--     s           Jump to Sidebar (left)
--     <Tab>       Cycle forward across panels
--     <S-Tab>     Cycle backward across panels
--   In Result editor (Bottom):
--     gc / <A-c>  Jump to Current panel (top-left)
--     gi / <A-i>  Jump to Incoming panel (top-right)
--     gs / <A-s>  Jump to Sidebar (left)
--     <Tab>       Cycle to next panel
--     <S-Tab>     Cycle to previous panel
--     <C-h>       Jump left to Sidebar
--     <C-k>       Jump up to Current
--     <C-l>       Jump up-right to Incoming
--
-- CONFLICT ACTIONS IN RESULT EDITOR
--   co / 1        Accept Current (Ours) for active conflict
--   ct / 2        Accept Incoming (Theirs) for active conflict
--   cb / 3        Accept Both (Current first)
--   cB / 4        Accept Both (Incoming first)
--   ]c / ]x       Jump to next conflict
--   [c / [x       Jump to previous conflict
--   s             Save & Stage file (git add)
--   ?             Show keymap reference popup
--   q / <Esc>     Close conflict resolver
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local conflicts = lazy_req("krs.git.conflicts")

local M = {}

M.ns_markers = vim.api.nvim_create_namespace("krs_conflict_markers")

M.settings = {
	sidebar_width = 30,
	notify_title = "Merge Conflict Resolver",
}

M.state = {
	is_open = false,
	cwd = nil,
	tab = nil,
	files = {},
	active_idx = 1,
	spans = {},
	sidebar_win = nil,
	sidebar_buf = nil,
	current_win = nil,
	current_buf = nil,
	incoming_win = nil,
	incoming_buf = nil,
	result_win = nil,
	result_buf = nil,
	prev_win = nil,
	prev_tab = nil,
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

-- ---------------------------------------------------------------------------
-- Highlights
-- ---------------------------------------------------------------------------

function M.setup_highlights()
	vim.api.nvim_set_hl(0, "KRSConflictOursHeader", { fg = "#a6e3a1", bg = "#1e3a29", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictTheirsHeader", { fg = "#89b4fa", bg = "#1e2d42", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictSeparator", { fg = "#f9e2af", bg = "#3b382c", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictOursChunk", { bg = "#172b1f", default = true })
	vim.api.nvim_set_hl(0, "KRSConflictTheirsChunk", { bg = "#172333", default = true })
	vim.api.nvim_set_hl(0, "KRSConflictBadge", { fg = "#11111b", bg = "#f9e2af", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictActiveFile", { fg = "#89dceb", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictResolved", { fg = "#a6e3a1", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictPending", { fg = "#f9e2af", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictResultChunk", { bg = "#262b3d", default = true })
end

-- ---------------------------------------------------------------------------
-- Status & State Queries
-- ---------------------------------------------------------------------------

--- Returns true if the Conflict Resolver UI is currently open.
--- @return boolean
function M.is_open()
	return M.state.is_open
		and M.state.result_win ~= nil
		and pcall(vim.api.nvim_win_is_valid, M.state.result_win)
		and vim.api.nvim_win_is_valid(M.state.result_win)
end

-- ---------------------------------------------------------------------------
-- Panel Navigation Functions
-- ---------------------------------------------------------------------------

function M.focus_current()
	if M.state.current_win and vim.api.nvim_win_is_valid(M.state.current_win) then
		vim.api.nvim_set_current_win(M.state.current_win)
	end
end

function M.focus_incoming()
	if M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) then
		vim.api.nvim_set_current_win(M.state.incoming_win)
	end
end

function M.focus_result()
	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		vim.api.nvim_set_current_win(M.state.result_win)
	end
end

function M.focus_sidebar()
	if M.state.sidebar_win and vim.api.nvim_win_is_valid(M.state.sidebar_win) then
		vim.api.nvim_set_current_win(M.state.sidebar_win)
	end
end

function M.cycle_next_panel()
	local cur_win = vim.api.nvim_get_current_win()
	if cur_win == M.state.sidebar_win then
		M.focus_current()
	elseif cur_win == M.state.current_win then
		M.focus_incoming()
	elseif cur_win == M.state.incoming_win then
		M.focus_result()
	else
		M.focus_sidebar()
	end
end

function M.cycle_prev_panel()
	local cur_win = vim.api.nvim_get_current_win()
	if cur_win == M.state.sidebar_win then
		M.focus_result()
	elseif cur_win == M.state.result_win then
		M.focus_incoming()
	elseif cur_win == M.state.incoming_win then
		M.focus_current()
	else
		M.focus_sidebar()
	end
end

-- ---------------------------------------------------------------------------
-- Highlighting Result Buffer Conflict Sections
-- ---------------------------------------------------------------------------

--- Clears and re-applies extmarks to the result buffer.
function M.update_result_highlights()
	if not M.state.result_buf or not vim.api.nvim_buf_is_valid(M.state.result_buf) then
		return
	end

	local buf = M.state.result_buf
	vim.api.nvim_buf_clear_namespace(buf, M.ns_markers, 0, -1)

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines == 0 then
		return
	end

	for _, span in ipairs(M.state.spans or {}) do
		local s_line = math.max(0, math.min(span.start_line - 1, #lines - 1))
		local e_line = math.max(s_line, math.min(span.end_line - 1, #lines - 1))

		local choice_badge
		local badge_hl
		if span.resolved then
			badge_hl = "KRSConflictResolved"
			if span.choice == "incoming" then
				choice_badge = " [RESOLVED: Theirs] "
			elseif span.choice == "both" then
				choice_badge = " [RESOLVED: Both] "
			else
				choice_badge = " [RESOLVED: Ours] "
			end
		else
			badge_hl = "KRSConflictPending"
			choice_badge = " [CONFLICT: 1:Ours 2:Theirs 3:Both] "
		end

		pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, s_line, 0, {
			virt_lines = {
				{
					{ string.format("⚔️ CONFLICT #%d%s", span.id, choice_badge), badge_hl },
				},
			},
			virt_lines_above = true,
		})

		for l = s_line, e_line do
			pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, l, 0, {
				line_hl_group = span.resolved and "Normal" or "KRSConflictResultChunk",
			})
		end
	end
end

-- ---------------------------------------------------------------------------
-- Winbar Headers
-- ---------------------------------------------------------------------------

function M.update_winbars()
	local active_item = M.state.files[M.state.active_idx]
	local remaining = active_item and active_item.conflict_count or 0
	local cwd = M.state.cwd or vim.fn.getcwd()
	local head_name, inc_name = conflicts.get_conflict_branch_names(cwd)

	if M.state.sidebar_win and vim.api.nvim_win_is_valid(M.state.sidebar_win) then
		pcall(function()
			vim.wo[M.state.sidebar_win].winbar = "%#KRSConflictActiveFile# ⚔️ CONFLICTED FILES %*"
		end)
	end

	if M.state.current_win and vim.api.nvim_win_is_valid(M.state.current_win) then
		pcall(function()
			vim.wo[M.state.current_win].winbar = string.format(
				"%%#KRSConflictOursHeader# 🌿 Current (%s) [READ-ONLY] %%* │ [i] Incoming  [r] Result  [s] Sidebar",
				head_name
			)
		end)
	end

	if M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) then
		pcall(function()
			vim.wo[M.state.incoming_win].winbar = string.format(
				"%%#KRSConflictTheirsHeader# 📥 Incoming (%s) [READ-ONLY] %%* │ [c] Current  [r] Result  [s] Sidebar",
				inc_name
			)
		end)
	end

	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		local status_str = remaining > 0 and string.format("%%#KRSConflictPending# ⚠️ %d remaining %%*", remaining)
			or "%#KRSConflictResolved# ✅ All resolved (0) │ Press [s] to Stage %*"
		pcall(function()
			vim.wo[M.state.result_win].winbar = string.format(
				"%%#Bold# ✏️ Result (Merged - EDITABLE) %%* │ %s │ [1/co] Ours  [2/ct] Theirs  [3/cb] Both  [s] Stage",
				status_str
			)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Sidebar Rendering
-- ---------------------------------------------------------------------------

function M.render_sidebar()
	if not M.state.sidebar_buf or not vim.api.nvim_buf_is_valid(M.state.sidebar_buf) then
		return
	end

	local buf = M.state.sidebar_buf
	vim.bo[buf].modifiable = true

	local lines = {}
	local highlights = {}

	table.insert(lines, " ⚔️ CONFLICTED FILES")
	table.insert(lines, "────────────────────────────")

	for idx, item in ipairs(M.state.files) do
		local is_active = (idx == M.state.active_idx)
		local prefix = is_active and "▶ " or "  "

		local count = item.conflict_count or 0
		local is_clean = item.is_staged or count == 0
		local status_icon = is_clean and "✓" or "!"

		-- Displays live count: (2) -> (1) -> (0)
		local row_text = string.format("%s%s %s (%d)", prefix, status_icon, item.file, count)

		table.insert(lines, row_text)
		local line_idx = #lines - 1

		if is_active then
			table.insert(highlights, { line = line_idx, col_start = 0, col_end = -1, hl = "KRSConflictActiveFile" })
		elseif is_clean then
			table.insert(highlights, { line = line_idx, col_start = 2, col_end = 3, hl = "KRSConflictResolved" })
		else
			table.insert(highlights, { line = line_idx, col_start = 2, col_end = 3, hl = "KRSConflictPending" })
		end
	end

	table.insert(lines, "")
	table.insert(lines, "────────────────────────────")
	table.insert(lines, " 🧭 PANEL JUMP:")
	table.insert(lines, " [c] Current (Top-Left)")
	table.insert(lines, " [i] Incoming (Top-Right)")
	table.insert(lines, " [r] Result (Bottom)")
	table.insert(lines, " [s] Sidebar (Left)")
	table.insert(lines, " [Tab] Cycle Panels")
	table.insert(lines, "")
	table.insert(lines, " ⚡ CONFLICT ACTIONS:")
	table.insert(lines, " [co / 1] Accept Current")
	table.insert(lines, " [ct / 2] Accept Incoming")
	table.insert(lines, " [cb / 3] Accept Both")
	table.insert(lines, " [s]      Stage & Save")
	table.insert(lines, " [?]      Show Help")
	table.insert(lines, " [q]      Close Resolver")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, M.ns_markers, 0, -1)
	for _, h in ipairs(highlights) do
		pcall(vim.api.nvim_buf_add_highlight, buf, M.ns_markers, h.hl, h.line, h.col_start, h.col_end)
	end
end

local function unmap_result_keymaps(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, k in ipairs({
		"co",
		"1",
		"ct",
		"2",
		"cb",
		"3",
		"cB",
		"4",
		"]c",
		"[c",
		"]x",
		"[x",
		"s",
		"gc",
		"<A-c>",
		"gi",
		"<A-i>",
		"gs",
		"<A-s>",
		"<Tab>",
		"<S-Tab>",
		"?",
		"q",
		"<Esc>",
		"<C-h>",
		"<C-k>",
		"<C-l>",
	}) do
		pcall(vim.keymap.del, "n", k, { buffer = buf })
	end
end

function M.load_file(idx)
	if not M.state.files or #M.state.files == 0 then
		return
	end
	if idx < 1 or idx > #M.state.files then
		return
	end

	-- Clean up previous result buffer if switching
	if M.state.result_buf and vim.api.nvim_buf_is_valid(M.state.result_buf) then
		unmap_result_keymaps(M.state.result_buf)
		pcall(vim.api.nvim_buf_clear_namespace, M.state.result_buf, M.ns_markers, 0, -1)
	end

	M.state.active_idx = idx
	local item = M.state.files[idx]
	local rel_path = item.file
	local full_path = item.full_path
	local cwd = M.state.cwd or vim.fn.getcwd()

	-- Working tree lines from disk
	local working_lines = conflicts.read_file_lines(full_path)
	local marker_list = conflicts.parse_markers(working_lines)

	-- 1. Current branch content (Ours / HEAD / Stage 2)
	local current_lines = conflicts.get_stage_content(rel_path, 2, cwd)
	if not current_lines or #current_lines == 0 then
		current_lines, _, _ = conflicts.extract_clean_versions(working_lines)
	end

	-- 2. Incoming branch content (Theirs / MERGE_HEAD / Stage 3)
	local incoming_lines = conflicts.get_stage_content(rel_path, 3, cwd)
	if not incoming_lines or #incoming_lines == 0 then
		_, incoming_lines, _ = conflicts.extract_clean_versions(working_lines)
	end

	-- Determine filetype for syntax highlighting
	local ft = vim.filetype.match({ filename = full_path })
	if not ft or ft == "" then
		local ext = full_path:match("%.([%w_]+)$")
		ft = ext or ""
	end

	-- Populate Top-Left: Current (Ours) [Read-Only]
	if M.state.current_buf and vim.api.nvim_buf_is_valid(M.state.current_buf) then
		vim.bo[M.state.current_buf].modifiable = true
		vim.bo[M.state.current_buf].readonly = false
		vim.api.nvim_buf_set_lines(M.state.current_buf, 0, -1, false, current_lines)
		vim.bo[M.state.current_buf].modifiable = false
		vim.bo[M.state.current_buf].readonly = true
		if ft ~= "" then
			pcall(function()
				vim.bo[M.state.current_buf].filetype = ft
			end)
		end
	end

	-- Populate Top-Right: Incoming (Theirs) [Read-Only]
	if M.state.incoming_buf and vim.api.nvim_buf_is_valid(M.state.incoming_buf) then
		vim.bo[M.state.incoming_buf].modifiable = true
		vim.bo[M.state.incoming_buf].readonly = false
		vim.api.nvim_buf_set_lines(M.state.incoming_buf, 0, -1, false, incoming_lines)
		vim.bo[M.state.incoming_buf].modifiable = false
		vim.bo[M.state.incoming_buf].readonly = true
		if ft ~= "" then
			pcall(function()
				vim.bo[M.state.incoming_buf].filetype = ft
			end)
		end
	end

	-- Populate Bottom Result Window [THE ONLY EDITABLE WINDOW]
	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		local res_buf = vim.fn.bufadd(full_path)
		vim.fn.bufload(res_buf)
		vim.bo[res_buf].buflisted = true
		vim.bo[res_buf].swapfile = false
		vim.api.nvim_win_set_buf(M.state.result_win, res_buf)
		M.state.result_buf = res_buf

		vim.bo[res_buf].modifiable = true
		vim.bo[res_buf].readonly = false
		if ft ~= "" then
			pcall(function()
				vim.bo[res_buf].filetype = ft
			end)
		end

		-- Check if file contains conflict markers to generate the clean resulting code
		local buf_lines = vim.api.nvim_buf_get_lines(res_buf, 0, -1, false)
		if #buf_lines <= 1 and (buf_lines[1] == "" or buf_lines[1] == nil) then
			buf_lines = working_lines
		end

		local parsed = conflicts.parse_markers(buf_lines)
		if #parsed == 0 and #marker_list > 0 then
			buf_lines = working_lines
			parsed = marker_list
		end

		if #parsed > 0 then
			-- Generate clean resulting code with Current as initial candidate
			local clean_lines, spans = conflicts.build_resolved_lines(buf_lines, parsed, "current")
			for _, s in ipairs(spans) do
				s.resolved = false
			end
			M.state.spans = spans
			item.conflict_count = #spans
			vim.api.nvim_buf_set_lines(res_buf, 0, -1, false, clean_lines)
		else
			M.state.spans = {}
			item.conflict_count = 0
			if #buf_lines > 0 then
				vim.api.nvim_buf_set_lines(res_buf, 0, -1, false, buf_lines)
			end
		end

		M.attach_result_keymaps(res_buf)
		M.update_result_highlights()

		if M.state.spans and #M.state.spans > 0 then
			pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { M.state.spans[1].start_line, 0 })
			pcall(vim.cmd, "normal! zz")
		end
	end

	M.update_winbars()
	M.render_sidebar()
end

-- ---------------------------------------------------------------------------
-- Conflict Actions inside Result Window
-- ---------------------------------------------------------------------------

--- Finds the conflict span at or closest to the cursor line in Result window.
--- @return table|nil span
local function get_target_span()
	if not M.state.spans or #M.state.spans == 0 then
		return nil
	end
	local cursor_line = vim.api.nvim_win_get_cursor(M.state.result_win)[1]

	for _, s in ipairs(M.state.spans) do
		if cursor_line >= s.start_line and cursor_line <= s.end_line then
			return s
		end
	end

	for _, s in ipairs(M.state.spans) do
		if s.start_line >= cursor_line then
			return s
		end
	end

	return M.state.spans[#M.state.spans]
end

--- Applies a resolution choice to the active conflict span.
--- @param choice string "current" | "incoming" | "both_current_first" | "both_incoming_first"
local function apply_span_choice(choice)
	local span = get_target_span()
	if not span then
		notify("No conflict span at cursor", vim.log.levels.WARN)
		return
	end

	local new_chunk = {}
	if choice == "current" or choice == "ours" then
		new_chunk = span.current_lines
		span.choice = "current"
	elseif choice == "incoming" or choice == "theirs" then
		new_chunk = span.incoming_lines
		span.choice = "incoming"
	elseif choice == "both_incoming_first" then
		for _, l in ipairs(span.incoming_lines) do
			table.insert(new_chunk, l)
		end
		for _, l in ipairs(span.current_lines) do
			table.insert(new_chunk, l)
		end
		span.choice = "both"
	else
		for _, l in ipairs(span.current_lines) do
			table.insert(new_chunk, l)
		end
		for _, l in ipairs(span.incoming_lines) do
			table.insert(new_chunk, l)
		end
		span.choice = "both"
	end

	local buf = M.state.result_buf
	local old_count = (span.end_line - span.start_line + 1)
	local new_count = #new_chunk
	local delta = new_count - old_count

	vim.api.nvim_buf_set_lines(buf, span.start_line - 1, span.end_line, false, new_chunk)
	span.end_line = span.start_line + math.max(1, new_count) - 1
	span.resolved = true

	-- Shift subsequent spans
	for i = span.id + 1, #M.state.spans do
		local next_s = M.state.spans[i]
		next_s.start_line = next_s.start_line + delta
		next_s.end_line = next_s.end_line + delta
	end

	-- Recalculate remaining unresolved conflicts for active file
	local item = M.state.files[M.state.active_idx]
	if item then
		local remaining = 0
		for _, s in ipairs(M.state.spans) do
			if not s.resolved then
				remaining = remaining + 1
			end
		end
		item.conflict_count = remaining
	end

	M.update_result_highlights()
	M.render_sidebar()
	M.update_winbars()
	pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { math.max(1, span.start_line), 0 })

	local label = (choice == "incoming" or choice == "theirs") and "📥 Incoming (Theirs)"
		or ((choice:find("both")) and "🔀 Both Changes" or "🌿 Current (Ours)")
	notify(string.format("Applied %s for Conflict #%d", label, span.id))
end

function M.accept_current()
	apply_span_choice("current")
end

function M.accept_incoming()
	apply_span_choice("incoming")
end

function M.accept_both(order)
	apply_span_choice(order == "incoming_first" and "both_incoming_first" or "both_current_first")
end

function M.next_conflict()
	if not M.state.spans or #M.state.spans == 0 then
		notify("No conflicts in this file")
		return
	end
	local cursor_line = vim.api.nvim_win_get_cursor(M.state.result_win)[1]

	for _, s in ipairs(M.state.spans) do
		if s.start_line > cursor_line then
			pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { s.start_line, 0 })
			pcall(vim.cmd, "normal! zz")
			return
		end
	end

	pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { M.state.spans[1].start_line, 0 })
	pcall(vim.cmd, "normal! zz")
	notify("Wrapped to first conflict")
end

function M.prev_conflict()
	if not M.state.spans or #M.state.spans == 0 then
		notify("No conflicts in this file")
		return
	end
	local cursor_line = vim.api.nvim_win_get_cursor(M.state.result_win)[1]

	for i = #M.state.spans, 1, -1 do
		local s = M.state.spans[i]
		if s.start_line < cursor_line then
			pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { s.start_line, 0 })
			pcall(vim.cmd, "normal! zz")
			return
		end
	end

	pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { M.state.spans[#M.state.spans].start_line, 0 })
	pcall(vim.cmd, "normal! zz")
	notify("Wrapped to last conflict")
end

--- Saves the current result file to disk and stages it via `git add`.
function M.stage_current_file()
	if not M.state.files or #M.state.files == 0 then
		return
	end
	local item = M.state.files[M.state.active_idx]
	if not item then
		return
	end

	-- Save result buffer to disk
	if M.state.result_buf and vim.api.nvim_buf_is_valid(M.state.result_buf) then
		vim.api.nvim_win_call(M.state.result_win, function()
			pcall(vim.cmd, "silent write!")
		end)
	end

	local ok, err = conflicts.stage_file(item.file, M.state.cwd)
	if ok then
		item.is_staged = true
		item.conflict_count = 0
		notify(string.format("✅ Staged %s (marked resolved)", item.file))
		M.render_sidebar()
		M.update_winbars()

		-- Check if all files in repo are staged/resolved
		local all_done = true
		for _, f in ipairs(M.state.files) do
			if not f.is_staged and (f.conflict_count or 0) > 0 then
				all_done = false
				break
			end
		end

		if all_done then
			notify("🎉 All conflicted files staged! You can now commit with <C-S-g> or git commit.")
		else
			-- Advance to next conflicted file
			for next_idx, f in ipairs(M.state.files) do
				if not f.is_staged and (f.conflict_count or 0) > 0 then
					M.load_file(next_idx)
					break
				end
			end
		end
	else
		notify("Failed to stage: " .. tostring(err), vim.log.levels.ERROR)
	end
end

-- ---------------------------------------------------------------------------
-- Keymap Attachments
-- ---------------------------------------------------------------------------

function M.attach_result_keymaps(buf)
	local opts = { buffer = buf, silent = true, nowait = true }

	-- Conflict resolution actions
	vim.keymap.set("n", "co", M.accept_current, opts)
	vim.keymap.set("n", "1", M.accept_current, opts)
	vim.keymap.set("n", "ct", M.accept_incoming, opts)
	vim.keymap.set("n", "2", M.accept_incoming, opts)
	vim.keymap.set("n", "cb", function()
		M.accept_both("current_first")
	end, opts)
	vim.keymap.set("n", "3", function()
		M.accept_both("current_first")
	end, opts)
	vim.keymap.set("n", "cB", function()
		M.accept_both("incoming_first")
	end, opts)
	vim.keymap.set("n", "4", function()
		M.accept_both("incoming_first")
	end, opts)

	-- Conflict jumps
	vim.keymap.set("n", "]c", M.next_conflict, opts)
	vim.keymap.set("n", "[c", M.prev_conflict, opts)
	vim.keymap.set("n", "]x", M.next_conflict, opts)
	vim.keymap.set("n", "[x", M.prev_conflict, opts)

	-- Save & Stage
	vim.keymap.set("n", "s", M.stage_current_file, opts)

	-- Panel navigation
	vim.keymap.set("n", "gc", M.focus_current, opts)
	vim.keymap.set("n", "<A-c>", M.focus_current, opts)
	vim.keymap.set("n", "gi", M.focus_incoming, opts)
	vim.keymap.set("n", "<A-i>", M.focus_incoming, opts)
	vim.keymap.set("n", "gs", M.focus_sidebar, opts)
	vim.keymap.set("n", "<A-s>", M.focus_sidebar, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)

	-- Help & Close
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "q", M.close, opts)
end

function M.attach_sidebar_keymaps()
	local buf = M.state.sidebar_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local opts = { buffer = buf, silent = true, nowait = true }

	local function on_select()
		local line = vim.api.nvim_win_get_cursor(M.state.sidebar_win)[1]
		local target_idx = line - 2
		if target_idx >= 1 and target_idx <= #M.state.files then
			M.load_file(target_idx)
			M.focus_result()
		end
	end

	vim.keymap.set("n", "<CR>", on_select, opts)
	vim.keymap.set("n", "<2-LeftMouse>", on_select, opts)
	vim.keymap.set("n", "c", M.focus_current, opts)
	vim.keymap.set("n", "i", M.focus_incoming, opts)
	vim.keymap.set("n", "r", M.focus_result, opts)
	vim.keymap.set("n", "s", M.stage_current_file, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
end

function M.attach_current_keymaps()
	local buf = M.state.current_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local opts = { buffer = buf, silent = true, nowait = true }

	vim.keymap.set("n", "c", M.focus_current, opts)
	vim.keymap.set("n", "i", M.focus_incoming, opts)
	vim.keymap.set("n", "r", M.focus_result, opts)
	vim.keymap.set("n", "s", M.focus_sidebar, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)
	vim.keymap.set("n", "co", function()
		M.accept_current()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "1", function()
		M.accept_current()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "]c", function()
		M.next_conflict()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "[c", function()
		M.prev_conflict()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
end

function M.attach_incoming_keymaps()
	local buf = M.state.incoming_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local opts = { buffer = buf, silent = true, nowait = true }

	vim.keymap.set("n", "c", M.focus_current, opts)
	vim.keymap.set("n", "i", M.focus_incoming, opts)
	vim.keymap.set("n", "r", M.focus_result, opts)
	vim.keymap.set("n", "s", M.focus_sidebar, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)
	vim.keymap.set("n", "ct", function()
		M.accept_incoming()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "2", function()
		M.accept_incoming()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "]c", function()
		M.next_conflict()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "[c", function()
		M.prev_conflict()
		M.focus_result()
	end, opts)
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
end

-- ---------------------------------------------------------------------------
-- Help Popup
-- ---------------------------------------------------------------------------

function M.show_help_popup()
	local help_lines = {
		" ⚔️ 3-WAY MERGE CONFLICT RESOLVER CHEAT-SHEET ",
		"─────────────────────────────────────────────────",
		" 🧭 PANEL NAVIGATION (Letters):",
		"   c            Jump to Current panel (top-left)",
		"   i            Jump to Incoming panel (top-right)",
		"   r            Jump to Result panel (bottom)",
		"   s            Jump to Sidebar (left)",
		"   gc / <A-c>   Jump to Current (from Result)",
		"   gi / <A-i>   Jump to Incoming (from Result)",
		"   gs / <A-s>   Jump to Sidebar (from Result)",
		"   <Tab>        Cycle next panel",
		"   <S-Tab>      Cycle previous panel",
		"   <C-h/k/l>    Direct jump (Sidebar/Current/Incoming)",
		"",
		" ⚡ CONFLICT RESOLUTION (In Result Window):",
		"   1  or  co    Accept Current (Ours / HEAD)",
		"   2  or  ct    Accept Incoming (Theirs / Remote)",
		"   3  or  cb    Accept Both (Current first)",
		"   4  or  cB    Accept Both (Incoming first)",
		"   ]c or  ]x    Jump to Next conflict",
		"   [c or  [x    Jump to Previous conflict",
		"",
		" 💾 FILE ACTIONS:",
		"   s            Save file and stage with git add",
		"   <CR>         In sidebar: switch to file under cursor",
		"   q / <Esc>    Close Conflict Resolver",
		"─────────────────────────────────────────────────",
		" Press q, <Esc>, or <CR> to close this help window",
	}

	local w = 54
	local h = #help_lines
	local r = math.max(2, math.floor((vim.o.lines - h) / 2))
	local c = math.max(2, math.floor((vim.o.columns - w) / 2))

	local hbuf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, help_lines)
	vim.bo[hbuf].modifiable = false
	vim.bo[hbuf].bufhidden = "wipe"

	local hwin = vim.api.nvim_open_win(hbuf, true, {
		relative = "editor",
		row = r,
		col = c,
		width = w,
		height = h,
		style = "minimal",
		border = "rounded",
		title = " Keyboard Shortcuts ",
		title_pos = "center",
		zindex = 320,
	})

	local function close_help()
		if hwin and vim.api.nvim_win_is_valid(hwin) then
			pcall(vim.api.nvim_win_close, hwin, true)
		end
	end

	for _, k in ipairs({ "q", "<Esc>", "<CR>", "?" }) do
		vim.keymap.set("n", k, close_help, { buffer = hbuf, silent = true, nowait = true })
	end
end

-- ---------------------------------------------------------------------------
-- Open & Close Lifecycle
-- ---------------------------------------------------------------------------

--- Opens the 3-way Merge Conflict Editor in a full-screen tiled workspace.
--- @param files_or_cwd table|string|nil
--- @param cwd_arg string|nil
--- @return boolean success
function M.open(files_or_cwd, cwd_arg)
	local cwd = cwd_arg
	if type(files_or_cwd) == "string" and not cwd then
		cwd = files_or_cwd
	end
	cwd = cwd or vim.fn.getcwd()
	M.state.cwd = cwd

	M.setup_highlights()

	-- If already open, focus result window
	if M.is_open() then
		M.focus_result()
		return true
	end

	-- Check if repo has conflicts
	local file_list
	if type(files_or_cwd) == "table" and #files_or_cwd > 0 then
		file_list = files_or_cwd
	else
		file_list = conflicts.get_conflicted_files(cwd)
	end

	if #file_list == 0 then
		vim.notify("✅ No git merge conflicts detected in this repository.", vim.log.levels.INFO, {
			title = M.settings.notify_title,
		})
		return false
	end

	-- Initialize files list with conflict counts from disk
	M.state.files = {}
	for _, f in ipairs(file_list) do
		local rel_name
		local full_p
		local count

		if type(f) == "table" then
			rel_name = f.file or f.path or f[1] or ""
			full_p = f.full_path or (rel_name ~= "" and vim.fs.normalize(cwd .. "/" .. rel_name))
			count = f.conflict_count
		else
			rel_name = tostring(f)
			if rel_name:sub(1, 1) == "/" or rel_name:match("^%a:[/\\]") then
				full_p = vim.fs.normalize(rel_name)
			else
				full_p = vim.fs.normalize(cwd .. "/" .. rel_name)
			end
		end

		if not count and full_p then
			local lines = conflicts.read_file_lines(full_p)
			local markers = conflicts.parse_markers(lines)
			count = #markers
		end

		table.insert(M.state.files, {
			file = rel_name,
			full_path = full_p,
			conflict_count = count or 0,
			is_staged = false,
		})
	end
	M.state.active_idx = 1

	M.state.prev_win = vim.api.nvim_get_current_win()
	M.state.prev_tab = vim.api.nvim_get_current_tabpage()

	-- Open dedicated tabpage (full-screen tiled workspace, like DAP UI)
	vim.cmd("tabnew")
	M.state.tab = vim.api.nvim_get_current_tabpage()
	local base_win = vim.api.nvim_get_current_win()

	-- 1. Create Sidebar window on the far left (fixed width)
	local sb_width = M.settings.sidebar_width or 30
	local sidebar_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[sidebar_buf].buftype = "nofile"
	vim.bo[sidebar_buf].bufhidden = "wipe"
	vim.bo[sidebar_buf].swapfile = false
	vim.bo[sidebar_buf].buflisted = false
	local sidebar_win = vim.api.nvim_open_win(sidebar_buf, false, {
		win = base_win,
		split = "left",
		width = sb_width,
	})
	M.state.sidebar_win = sidebar_win
	M.state.sidebar_buf = sidebar_buf

	-- 2. Split base_win (right column) horizontally: Result on the bottom
	local res_height = math.max(8, math.floor(vim.o.lines * 0.48))
	local result_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[result_buf].buftype = "nofile"
	vim.bo[result_buf].bufhidden = "wipe"
	local result_win = vim.api.nvim_open_win(result_buf, true, {
		win = base_win,
		split = "below",
		height = res_height,
	})
	M.state.result_win = result_win
	M.state.result_buf = result_buf

	-- 3. base_win is now the top-left (Current / Ours)
	local current_win = base_win
	local current_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[current_buf].buftype = "nofile"
	vim.bo[current_buf].bufhidden = "wipe"
	vim.api.nvim_win_set_buf(current_win, current_buf)
	M.state.current_win = current_win
	M.state.current_buf = current_buf

	-- 4. Split current_win vertically: Incoming (Theirs) on top-right
	local incoming_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[incoming_buf].buftype = "nofile"
	vim.bo[incoming_buf].bufhidden = "wipe"
	local incoming_win = vim.api.nvim_open_win(incoming_buf, false, {
		win = current_win,
		split = "right",
	})
	M.state.incoming_win = incoming_win
	M.state.incoming_buf = incoming_buf

	-- Apply window display options
	for _, w in ipairs({ current_win, incoming_win, result_win }) do
		if vim.api.nvim_win_is_valid(w) then
			vim.wo[w].number = true
			vim.wo[w].relativenumber = false
			vim.wo[w].signcolumn = "yes"
			vim.wo[w].wrap = false
			vim.wo[w].cursorline = true
		end
	end
	if vim.api.nvim_win_is_valid(sidebar_win) then
		vim.wo[sidebar_win].number = false
		vim.wo[sidebar_win].relativenumber = false
		vim.wo[sidebar_win].signcolumn = "no"
		vim.wo[sidebar_win].wrap = false
		vim.wo[sidebar_win].cursorline = true
	end

	M.state.is_open = true

	-- Attach keymaps
	M.attach_sidebar_keymaps()
	M.attach_current_keymaps()
	M.attach_incoming_keymaps()

	-- Load first conflicted file
	M.load_file(1)

	-- Focus on result window
	M.focus_result()

	-- Tab closed autocmd to reset state if user closes tab manually
	local augroup = vim.api.nvim_create_augroup("KrsConflictResolverTab", { clear = true })
	vim.api.nvim_create_autocmd("TabClosed", {
		group = augroup,
		callback = function()
			if M.state.tab and not pcall(vim.api.nvim_tabpage_is_valid, M.state.tab) then
				M.state.is_open = false
				M.state.tab = nil
				M.state.sidebar_win = nil
				M.state.current_win = nil
				M.state.incoming_win = nil
				M.state.result_win = nil
			end
		end,
	})

	return true
end

--- Closes the Conflict Resolver UI and restores the previous workspace.
function M.close()
	if not M.state.is_open and not M.state.tab then
		return
	end

	M.state.is_open = false

	if M.state.result_buf and vim.api.nvim_buf_is_valid(M.state.result_buf) then
		unmap_result_keymaps(M.state.result_buf)
		pcall(vim.api.nvim_buf_clear_namespace, M.state.result_buf, M.ns_markers, 0, -1)
	end

	if M.state.tab and pcall(vim.api.nvim_tabpage_is_valid, M.state.tab) then
		local total_tabs = #vim.api.nvim_list_tabpages()
		if total_tabs > 1 then
			pcall(vim.api.nvim_set_current_tabpage, M.state.tab)
			pcall(vim.cmd, "tabclose")
		else
			for _, w in ipairs({ M.state.sidebar_win, M.state.current_win, M.state.incoming_win, M.state.result_win }) do
				if w and pcall(vim.api.nvim_win_is_valid, w) and vim.api.nvim_win_is_valid(w) then
					pcall(vim.api.nvim_win_close, w, true)
				end
			end
		end
	end

	M.state.tab = nil
	M.state.sidebar_win = nil
	M.state.sidebar_buf = nil
	M.state.current_win = nil
	M.state.current_buf = nil
	M.state.incoming_win = nil
	M.state.incoming_buf = nil
	M.state.result_win = nil
	M.state.result_buf = nil

	if
		M.state.prev_win
		and pcall(vim.api.nvim_win_is_valid, M.state.prev_win)
		and vim.api.nvim_win_is_valid(M.state.prev_win)
	then
		pcall(vim.api.nvim_set_current_win, M.state.prev_win)
	end
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function M.setup()
	M.setup_highlights()

	vim.api.nvim_create_user_command("GitConflictResolve", function(opts)
		local arg = opts.args ~= "" and opts.args or nil
		M.open(arg)
	end, {
		desc = "Open full-screen 3-way Merge Conflict Resolver",
		nargs = "?",
		complete = "file",
	})

	vim.api.nvim_create_user_command("GitConflictClose", function()
		M.close()
	end, {
		desc = "Close 3-way Merge Conflict Resolver",
	})

	vim.api.nvim_create_user_command("GitConflictNext", function()
		M.next_conflict()
	end, {
		desc = "Jump to next merge conflict in Result editor",
	})

	vim.api.nvim_create_user_command("GitConflictPrev", function()
		M.prev_conflict()
	end, {
		desc = "Jump to previous merge conflict in Result editor",
	})

	vim.api.nvim_create_user_command("GitConflictAcceptCurrent", function()
		M.accept_current()
	end, {
		desc = "Accept Current (Ours) for active conflict",
	})

	vim.api.nvim_create_user_command("GitConflictAcceptIncoming", function()
		M.accept_incoming()
	end, {
		desc = "Accept Incoming (Theirs) for active conflict",
	})

	vim.api.nvim_create_user_command("GitConflictAcceptBoth", function()
		M.accept_both("current_first")
	end, {
		desc = "Accept Both changes for active conflict",
	})

	vim.api.nvim_create_user_command("GitConflictStage", function()
		M.stage_current_file()
	end, {
		desc = "Save and stage current conflicted file",
	})
end

return setmetatable({
	name = "krs_conflict_resolver",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = {
		"GitConflictResolve",
		"GitConflictClose",
		"GitConflictNext",
		"GitConflictPrev",
		"GitConflictAcceptCurrent",
		"GitConflictAcceptIncoming",
		"GitConflictAcceptBoth",
		"GitConflictStage",
	},
	config = function()
		M.setup()
	end,
}, { __index = M })
