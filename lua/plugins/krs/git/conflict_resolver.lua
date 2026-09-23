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
--
-- PANEL NAVIGATION SHORTCUTS
--   In All Panels (Result, Current, Incoming, Sidebar):
--     <C-h>       Jump to Sidebar (left)
--     <C-k>       Jump to Current / Ours (top-left)
--     <C-l>       Jump to Incoming / Theirs (top-right)
--     <C-j>       Jump to Result (bottom)
--     <Tab>       Cycle forward across panels
--     <S-Tab>     Cycle backward across panels
--     c / i / r / s Panel jump aliases in read-only panels
--
-- CONFLICT ACTIONS (Scoped only to Git Merge Conflict Screen):
--   <C-1> / <C-o> Accept Current (Ours / HEAD) [Green highlight]
--   <C-2> / <C-t> Accept Incoming (Theirs / Remote) [Blue highlight]
--   <C-3> / <C-b> Accept Both (Current first)
--   <C-4>         Accept Both (Incoming first)
--   <C-z> / u     Undo Resolution (repeat to reach initial merge state)
--   <C-n> / ]c    Jump to next conflict
--   <C-p> / [c    Jump to previous conflict
--   <C-s> / s     Save & Stage file (git add)
--   <C-/> / ?     Show keymap reference popup
--   <C-q> / q     Close conflict resolver
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local conflicts = lazy_req("krs.git.conflicts")
local project = lazy_req("krs.core.project")
local store = lazy_req("krs.core.store")

local M = {}

M.ns_markers = vim.api.nvim_create_namespace("krs_conflict_markers")
M.ns_spans = vim.api.nvim_create_namespace("krs_conflict_spans")

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
	current_spans = {},
	incoming_spans = {},
	history = {},
	sidebar_win = nil,
	sidebar_buf = nil,
	current_win = nil,
	current_buf = nil,
	incoming_win = nil,
	incoming_buf = nil,
	result_win = nil,
	result_buf = nil,
	last_top_win = nil,
	prev_win = nil,
	prev_tab = nil,
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

--- Resolves the per-project `.krsnvim/conflict_session.json` config path.
--- @param cwd string|nil
--- @return string
function M.get_session_path(cwd)
	cwd = cwd or M.state.cwd or vim.fn.getcwd()
	local root = project.root() or cwd
	if project.config_path then
		return project.config_path("conflict_session.json", root)
	end
	return root .. "/.krsnvim/conflict_session.json"
end

--- Loads in-progress conflict resolution session data from `.krsnvim/conflict_session.json`.
--- @param cwd string|nil
--- @return table|nil
function M.load_session(cwd)
	local path = M.get_session_path(cwd)
	local data = store.load(path, nil)
	if data and type(data) == "table" and data.files then
		return data
	end
	return nil
end

--- Saves in-progress conflict resolution state to `.krsnvim/conflict_session.json`.
function M.save_session()
	if not M.state.is_open or not M.state.files or #M.state.files == 0 then
		return
	end
	local path = M.get_session_path(M.state.cwd)

	-- Update active file lines and spans
	local active_item = M.state.files[M.state.active_idx]
	if active_item and M.state.result_buf and vim.api.nvim_buf_is_valid(M.state.result_buf) then
		active_item.saved_lines = vim.api.nvim_buf_get_lines(M.state.result_buf, 0, -1, false)
		active_item.saved_spans = vim.deepcopy(M.state.spans)
	end

	local files_map = {}
	for _, f in ipairs(M.state.files) do
		files_map[f.file] = {
			conflict_count = f.conflict_count,
			is_staged = f.is_staged,
			lines = f.saved_lines,
			spans = f.saved_spans,
		}
	end

	local data = {
		cwd = M.state.cwd,
		active_idx = M.state.active_idx,
		files = files_map,
		timestamp = os.time(),
	}
	store.save(path, data)
end

local save_timer = nil
--- Debounced version of save_session for rapid keystrokes/modifications in Result window.
function M.debounced_save_session()
	if save_timer then
		save_timer:stop()
		save_timer:close()
		save_timer = nil
	end
	local uv = vim.uv or vim.loop
	save_timer = uv.new_timer()
	if save_timer then
		save_timer:start(350, 0, vim.schedule_wrap(function()
			if save_timer then
				save_timer:stop()
				save_timer:close()
				save_timer = nil
			end
			M.save_session()
		end))
	else
		M.save_session()
	end
end

--- Deletes the `.krsnvim/conflict_session.json` persistence file.
--- @param cwd string|nil
function M.clear_session(cwd)
	if save_timer then
		save_timer:stop()
		save_timer:close()
		save_timer = nil
	end
	local path = M.get_session_path(cwd)
	if vim.fn.filereadable(path) == 1 then
		pcall(vim.fn.delete, path)
	end
end

--- Returns the current 1-indexed (start_line, end_line) of a span based on its extmark in the result buffer.
--- Dynamically updates even after free-form manual editing, insertions, and deletions.
--- Safely clamps to current buffer line count.
local function get_span_bounds(span)
	if not span then
		return 1, 1
	end
	local buf = M.state.result_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return span.start_line or 1, span.end_line or 1
	end
	local line_count = vim.api.nvim_buf_line_count(buf)
	if line_count == 0 then
		span.start_line = 1
		span.end_line = 1
		return 1, 1
	end

	if span.extmark_id then
		local pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_spans, span.extmark_id, { details = true })
		if pos and #pos >= 2 then
			local sr = math.max(0, math.min(pos[1], line_count - 1))
			local er = sr
			if pos[3] and pos[3].end_row then
				er = math.max(sr, math.min(pos[3].end_row, line_count - 1))
			end
			span.start_line = sr + 1
			span.end_line = er + 1
			return span.start_line, span.end_line
		end
	end

	local s = math.max(1, math.min(span.start_line or 1, line_count))
	local e = math.max(s, math.min(span.end_line or s, line_count))
	span.start_line = s
	span.end_line = e
	return s, e
end

--- Retrieves the actual Neo-tree width (from disk or open window) to keep sidebar aligned.
--- @return integer
function M.get_sidebar_width()
	local ok, store = pcall(require, "krs.core.store")
	if ok and store and store.read_file then
		local raw = store.read_file(vim.fn.stdpath("state") .. "/neotree_width")
		local w = tonumber(raw or "")
		if w and w >= 18 and w <= 60 then
			return w
		end
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
		if ok_buf and buf and vim.bo[buf].filetype == "neo-tree" then
			local w = vim.api.nvim_win_get_width(win)
			if w and w >= 18 and w <= 60 then
				return w
			end
		end
	end
	return M.settings.sidebar_width or 30
end

--- Pins the sidebar window width so it never expands when adjacent splits change.
function M.enforce_sidebar_width()
	if
		M.state.sidebar_win
		and pcall(vim.api.nvim_win_is_valid, M.state.sidebar_win)
		and vim.api.nvim_win_is_valid(M.state.sidebar_win)
	then
		local target_w = M.get_sidebar_width()
		vim.wo[M.state.sidebar_win].winfixwidth = true
		if vim.api.nvim_win_get_width(M.state.sidebar_win) ~= target_w then
			pcall(vim.api.nvim_win_set_width, M.state.sidebar_win, target_w)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Highlights (Distinct colors for Ours = Green vs Theirs = Blue)
-- ---------------------------------------------------------------------------

function M.setup_highlights()
	-- Ours (Current branch / HEAD): Distinct Green
	vim.api.nvim_set_hl(0, "KRSConflictOursHeader", { fg = "#a6e3a1", bg = "#1e3a29", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictOursChunk", { bg = "#1a3826", default = true })
	vim.api.nvim_set_hl(0, "KRSConflictOursBadge", { fg = "#a6e3a1", bg = "#1e3a29", bold = true, default = true })

	-- Theirs (Incoming branch): Distinct Blue
	vim.api.nvim_set_hl(0, "KRSConflictTheirsHeader", { fg = "#89b4fa", bg = "#1e2d42", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictTheirsChunk", { bg = "#182c47", default = true })
	vim.api.nvim_set_hl(0, "KRSConflictTheirsBadge", { fg = "#89b4fa", bg = "#1e2d42", bold = true, default = true })

	-- Both & Separator: Purple & Gold
	vim.api.nvim_set_hl(0, "KRSConflictSeparator", { fg = "#f9e2af", bg = "#3b382c", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictBothChunk", { bg = "#2d2345", default = true })
	vim.api.nvim_set_hl(0, "KRSConflictBadge", { fg = "#11111b", bg = "#f9e2af", bold = true, default = true })

	-- Sidebar & Result status
	vim.api.nvim_set_hl(0, "KRSConflictActiveFile", { fg = "#89dceb", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictResolved", { fg = "#a6e3a1", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictPending", { fg = "#f9e2af", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSConflictResultChunk", { bg = "#332a1e", default = true })
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
		M.state.last_top_win = M.state.current_win
		vim.api.nvim_set_current_win(M.state.current_win)
	end
end

function M.focus_incoming()
	if M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) then
		M.state.last_top_win = M.state.incoming_win
		vim.api.nvim_set_current_win(M.state.incoming_win)
	end
end

--- Navigates UP from the result window, returning to whichever top panel
--- (Current/Ours or Incoming/Theirs) was most recently active.
function M.focus_up()
	local target = M.state.last_top_win
	if target and vim.api.nvim_win_is_valid(target) then
		vim.api.nvim_set_current_win(target)
		return
	end
	M.focus_current()
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
-- Highlighting Buffer Conflict Sections (Ours = Green, Theirs = Blue)
-- ---------------------------------------------------------------------------

--- Clears and re-applies extmarks to the Top-Left Current (Ours) buffer.
function M.update_current_highlights()
	if not M.state.current_buf or not vim.api.nvim_buf_is_valid(M.state.current_buf) then
		return
	end

	local buf = M.state.current_buf
	vim.api.nvim_buf_clear_namespace(buf, M.ns_markers, 0, -1)

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines == 0 then
		return
	end

	local cwd = M.state.cwd or vim.fn.getcwd()
	local head_name = conflicts.get_conflict_branch_names(cwd)

	for _, span in ipairs(M.state.current_spans or {}) do
		local s_line = math.max(0, math.min(span.start_line - 1, #lines - 1))
		local e_line = math.max(s_line, math.min(span.end_line - 1, #lines - 1))

		local label = string.format(" 🌿 OURS #%d (%s) ", span.id, head_name)
		if span.empty then
			label = string.format(" 🌿 OURS #%d: [Empty / Deleted in %s] ", span.id, head_name)
		end

		pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, s_line, 0, {
			virt_lines = {
				{ { label, "KRSConflictOursHeader" } },
			},
			virt_lines_above = true,
		})

		if not span.empty then
			for l = s_line, e_line do
				pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, l, 0, {
					line_hl_group = "KRSConflictOursChunk",
				})
			end
		end
	end
end

--- Clears and re-applies extmarks to the Top-Right Incoming (Theirs) buffer.
function M.update_incoming_highlights()
	if not M.state.incoming_buf or not vim.api.nvim_buf_is_valid(M.state.incoming_buf) then
		return
	end

	local buf = M.state.incoming_buf
	vim.api.nvim_buf_clear_namespace(buf, M.ns_markers, 0, -1)

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines == 0 then
		return
	end

	local cwd = M.state.cwd or vim.fn.getcwd()
	local _, inc_name = conflicts.get_conflict_branch_names(cwd)

	for _, span in ipairs(M.state.incoming_spans or {}) do
		local s_line = math.max(0, math.min(span.start_line - 1, #lines - 1))
		local e_line = math.max(s_line, math.min(span.end_line - 1, #lines - 1))

		local label = string.format(" 📥 THEIRS #%d (%s) ", span.id, inc_name)
		if span.empty then
			label = string.format(" 📥 THEIRS #%d: [Empty / Deleted in %s] ", span.id, inc_name)
		end

		pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, s_line, 0, {
			virt_lines = {
				{ { label, "KRSConflictTheirsHeader" } },
			},
			virt_lines_above = true,
		})

		if not span.empty then
			for l = s_line, e_line do
				pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, l, 0, {
					line_hl_group = "KRSConflictTheirsChunk",
				})
			end
		end
	end
end

--- Clears and re-applies extmarks to the result buffer with distinct colors for Ours vs Theirs.
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
		local s_line, e_line = get_span_bounds(span)
		local s_row = math.max(0, math.min(s_line - 1, #lines - 1))
		local e_row = math.max(s_row, math.min(e_line - 1, #lines - 1))

		local choice_badge
		local badge_hl
		local line_hl
		if span.resolved then
			if span.choice == "incoming" or span.choice == "theirs" then
				badge_hl = "KRSConflictTheirsHeader"
				line_hl = "KRSConflictTheirsChunk"
				choice_badge = " [RESOLVED: Theirs (Blue)] "
			elseif span.choice == "both" then
				badge_hl = "KRSConflictSeparator"
				line_hl = "KRSConflictBothChunk"
				choice_badge = " [RESOLVED: Both] "
			else
				badge_hl = "KRSConflictOursHeader"
				line_hl = "KRSConflictOursChunk"
				choice_badge = " [RESOLVED: Ours (Green)] "
			end
		else
			badge_hl = "KRSConflictPending"
			line_hl = "KRSConflictResultChunk"
			choice_badge = " [CONFLICT: Ctrl+1/co: Ours (Green)  Ctrl+2/ct: Theirs (Blue)  Ctrl+3/cb: Both  Ctrl+z: Undo] "
		end

		pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, s_row, 0, {
			virt_lines = {
				{
					{ string.format("⚔️ CONFLICT #%d%s", span.id, choice_badge), badge_hl },
				},
			},
			virt_lines_above = true,
		})

		for l = s_row, e_row do
			pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_markers, l, 0, {
				line_hl_group = line_hl,
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
				"%%#KRSConflictOursHeader# 🌿 Ours (%s) [READ-ONLY] %%* │ [Ctrl+1/co] Accept Ours │ [Ctrl+l] Theirs  [Ctrl+j] Result",
				head_name
			)
		end)
	end

	if M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) then
		pcall(function()
			vim.wo[M.state.incoming_win].winbar = string.format(
				"%%#KRSConflictTheirsHeader# 📥 Theirs (%s) [READ-ONLY] %%* │ [Ctrl+2/ct] Accept Theirs │ [Ctrl+k] Ours  [Ctrl+j] Result",
				inc_name
			)
		end)
	end

	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		local status_str = remaining > 0 and string.format("%%#KRSConflictPending# ⚠️ %d remaining %%*", remaining)
			or "%#KRSConflictResolved# ✅ All resolved (0) │ Press [Ctrl+s] to Stage %*"
		pcall(function()
			vim.wo[M.state.result_win].winbar = string.format(
				"%%#Bold# ✏️ Result (Merged) %%* │ %s │ [Ctrl+1] Ours  [Ctrl+2] Theirs  [Ctrl+3] Both  [Ctrl+z] Undo  [Ctrl+s] Stage",
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
	table.insert(lines, " [Ctrl+h] Sidebar (Left)")
	table.insert(lines, " [Ctrl+k] Current (Top-Left)")
	table.insert(lines, " [Ctrl+l] Incoming (Top-Right)")
	table.insert(lines, " [Ctrl+j] Result (Bottom)")
	table.insert(lines, " [Tab] Cycle Panels")
	table.insert(lines, "")
	table.insert(lines, " ⚡ CONFLICT ACTIONS:")
	table.insert(lines, " [Ctrl+1 / 1] Accept Ours (Green)")
	table.insert(lines, " [Ctrl+2 / 2] Accept Theirs (Blue)")
	table.insert(lines, " [Ctrl+3 / 3] Accept Both")
	table.insert(lines, " [Ctrl+z / u] Undo Resolution")
	table.insert(lines, " [Ctrl+s]     Stage & Save")
	table.insert(lines, " [?]          Show Help")
	table.insert(lines, " [Ctrl+q / q] Close Resolver")

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
		"<C-1>",
		"<C-o>",
		"<C-O>",
		"ct",
		"2",
		"<C-2>",
		"<C-t>",
		"<C-T>",
		"cb",
		"3",
		"<C-3>",
		"<C-b>",
		"<C-B>",
		"cB",
		"4",
		"<C-4>",
		"]c",
		"[c",
		"]x",
		"[x",
		"<C-n>",
		"<C-p>",
		"<C-Down>",
		"<C-Up>",
		"s",
		"<C-s>",
		"<C-S>",
		"u",
		"<C-z>",
		"gc",
		"<A-c>",
		"gi",
		"<A-i>",
		"gs",
		"<A-s>",
		"<Tab>",
		"<S-Tab>",
		"?",
		"<C-/>",
		"<C-_>",
		"q",
		"<Esc>",
		"<C-q>",
		"<C-h>",
		"<C-k>",
		"<C-Up>",
		"<A-k>",
		"<M-k>",
		"<C-w>k",
		"<C-w><C-k>",
		"<C-w><Up>",
		"<C-l>",
		"<C-j>",
	}) do
		pcall(vim.keymap.del, { "n", "i" }, k, { buffer = buf })
	end
end

function M.load_file(idx)
	if not M.state.files or #M.state.files == 0 then
		return
	end
	if idx < 1 or idx > #M.state.files then
		return
	end

	-- Save previous result buffer state before switching files
	if
		M.state.result_buf
		and vim.api.nvim_buf_is_valid(M.state.result_buf)
		and M.state.files[M.state.active_idx]
	then
		local prev_item = M.state.files[M.state.active_idx]
		prev_item.saved_lines = vim.api.nvim_buf_get_lines(M.state.result_buf, 0, -1, false)
		prev_item.saved_spans = vim.deepcopy(M.state.spans)
		M.save_session()
		unmap_result_keymaps(M.state.result_buf)
		pcall(vim.api.nvim_buf_clear_namespace, M.state.result_buf, M.ns_markers, 0, -1)
		pcall(vim.api.nvim_buf_clear_namespace, M.state.result_buf, M.ns_spans, 0, -1)
	end

	M.state.active_idx = idx
	local item = M.state.files[idx]
	local rel_path = item.file
	local full_path = item.full_path
	local cwd = M.state.cwd or vim.fn.getcwd()

	-- Working tree lines from disk
	local working_lines = conflicts.read_file_lines(full_path)
	local marker_list = conflicts.parse_markers(working_lines)

	-- 1. Extract clean versions and conflict spans for Ours and Theirs
	local clean_curr, clean_inc, _, c_spans, i_spans = conflicts.extract_clean_versions(working_lines)
	M.state.current_spans = c_spans or {}
	M.state.incoming_spans = i_spans or {}

	-- Current branch content (Ours / HEAD / Stage 2)
	local current_lines = conflicts.get_stage_content(rel_path, 2, cwd)
	if not current_lines or #current_lines == 0 then
		current_lines = clean_curr
	end

	-- 2. Incoming branch content (Theirs / MERGE_HEAD / Stage 3)
	local incoming_lines = conflicts.get_stage_content(rel_path, 3, cwd)
	if not incoming_lines or #incoming_lines == 0 then
		incoming_lines = clean_inc
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

		local restored_from_saved = false
		if item.saved_lines and #item.saved_lines > 0 then
			vim.api.nvim_buf_set_lines(res_buf, 0, -1, false, item.saved_lines)
			M.state.spans = vim.deepcopy(item.saved_spans or {})
			restored_from_saved = true
		else
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

				-- Save initial state for unlimited undo back to the beginning
				if not M.state.history then
					M.state.history = {}
				end
				if not M.state.history[idx] then
					M.state.history[idx] = {
						stack = {},
						initial_lines = vim.deepcopy(clean_lines),
						initial_spans = vim.deepcopy(spans),
						initial_count = #spans,
					}
				end
			else
				M.state.spans = {}
				item.conflict_count = 0
				if #buf_lines > 0 then
					vim.api.nvim_buf_set_lines(res_buf, 0, -1, false, buf_lines)
				end
			end
		end

		-- Setup extmarks for dynamic span tracking in result buffer
		pcall(vim.api.nvim_buf_clear_namespace, res_buf, M.ns_spans, 0, -1)
		local total_lines = vim.api.nvim_buf_line_count(res_buf)
		for _, s in ipairs(M.state.spans or {}) do
			local s_row = math.max(0, math.min((s.start_line or 1) - 1, total_lines - 1))
			local e_row = math.max(s_row, math.min((s.end_line or s.start_line or 1) - 1, total_lines - 1))
			local extmark_id = vim.api.nvim_buf_set_extmark(res_buf, M.ns_spans, s_row, 0, {
				end_row = e_row,
				end_col = 0,
				right_gravity = false,
				end_right_gravity = true,
			})
			s.extmark_id = extmark_id
		end

		M.attach_result_keymaps(res_buf)
		M.update_current_highlights()
		M.update_incoming_highlights()
		M.update_result_highlights()

		if M.state.spans and #M.state.spans > 0 then
			M.center_all_on_span(1)
		end

		if restored_from_saved then
			notify(string.format("💾 Restored conflict progress for %s", rel_path))
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
	local cursor_line = 1
	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		cursor_line = vim.api.nvim_win_get_cursor(M.state.result_win)[1]
	end

	-- Refresh all bounds from extmarks
	for _, s in ipairs(M.state.spans) do
		get_span_bounds(s)
	end

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

	local buf = M.state.result_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- Save snapshot to undo stack before modifying buffer
	local hist = M.state.history and M.state.history[M.state.active_idx]
	if hist then
		local item = M.state.files[M.state.active_idx]
		local snapshot = {
			lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
			spans = vim.deepcopy(M.state.spans),
			conflict_count = item and item.conflict_count or 0,
			cursor = pcall(vim.api.nvim_win_get_cursor, M.state.result_win) and vim.api.nvim_win_get_cursor(
				M.state.result_win
			) or nil,
		}
		table.insert(hist.stack, snapshot)
	end

	local new_chunk = {}
	if choice == "current" or choice == "ours" then
		new_chunk = span.current_lines or {}
		span.choice = "current"
	elseif choice == "incoming" or choice == "theirs" then
		new_chunk = span.incoming_lines or {}
		span.choice = "incoming"
	elseif choice == "both_incoming_first" then
		for _, l in ipairs(span.incoming_lines or {}) do
			table.insert(new_chunk, l)
		end
		for _, l in ipairs(span.current_lines or {}) do
			table.insert(new_chunk, l)
		end
		span.choice = "both"
	else
		for _, l in ipairs(span.current_lines or {}) do
			table.insert(new_chunk, l)
		end
		for _, l in ipairs(span.incoming_lines or {}) do
			table.insert(new_chunk, l)
		end
		span.choice = "both"
	end

	local s_line, e_line = get_span_bounds(span)
	local line_count = vim.api.nvim_buf_line_count(buf)
	local s_idx = math.max(0, math.min(s_line - 1, line_count))
	local e_idx = math.max(s_idx, math.min(e_line, line_count))

	local set_ok = pcall(vim.api.nvim_buf_set_lines, buf, s_idx, e_idx, false, new_chunk)
	if not set_ok then
		pcall(vim.api.nvim_buf_set_lines, buf, s_idx, s_idx, false, new_chunk)
	end

	local new_count = #new_chunk
	local new_end_row = math.max(s_idx, s_idx + math.max(1, new_count) - 1)
	if span.extmark_id then
		pcall(vim.api.nvim_buf_del_extmark, buf, M.ns_spans, span.extmark_id)
	end
	span.extmark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_spans, s_idx, 0, {
		end_row = new_end_row,
		end_col = 0,
		right_gravity = false,
		end_right_gravity = true,
	})
	span.start_line = s_idx + 1
	span.end_line = new_end_row + 1
	span.resolved = true

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

	-- Keep all panels synchronized on the span that was just resolved
	M.center_all_on_span(span.id)

	-- Persist session immediately
	M.save_session()

	local label = (choice == "incoming" or choice == "theirs") and "📥 Incoming (Theirs)"
		or ((choice:find("both")) and "🔀 Both Changes" or "🌿 Current (Ours)")
	notify(string.format("Applied %s for Conflict #%d", label, span.id))
end

--- Undoes the last conflict resolution action on the active file.
--- Can be pressed repeatedly to step back all the way to the original merge state at the beginning.
--- @return boolean
function M.undo()
	local idx = M.state.active_idx
	local hist = M.state.history and M.state.history[idx]
	if not hist or #hist.stack == 0 then
		notify("Already at original merge state at the beginning", vim.log.levels.INFO)
		return false
	end

	local prev = table.remove(hist.stack)
	local buf = M.state.result_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, prev.lines)

	M.state.spans = vim.deepcopy(prev.spans)
	local item = M.state.files[idx]
	if item then
		item.conflict_count = prev.conflict_count
		item.is_staged = false
	end

	-- Re-create extmarks for restored spans
	pcall(vim.api.nvim_buf_clear_namespace, buf, M.ns_spans, 0, -1)
	local total_lines = vim.api.nvim_buf_line_count(buf)
	for _, s in ipairs(M.state.spans or {}) do
		local s_row = math.max(0, math.min((s.start_line or 1) - 1, total_lines - 1))
		local e_row = math.max(s_row, math.min((s.end_line or s.start_line or 1) - 1, total_lines - 1))
		local extmark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_spans, s_row, 0, {
			end_row = e_row,
			end_col = 0,
			right_gravity = false,
			end_right_gravity = true,
		})
		s.extmark_id = extmark_id
	end

	if prev.cursor and M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		pcall(vim.api.nvim_win_set_cursor, M.state.result_win, prev.cursor)
	end

	M.update_result_highlights()
	M.render_sidebar()
	M.update_winbars()
	M.save_session()

	local remaining = (item and item.conflict_count) or 0
	local steps_left = #hist.stack
	if steps_left == 0 then
		notify(
			string.format(
				"↩️ Restored to original merge state at the beginning (%d conflict%s remaining)",
				remaining,
				remaining == 1 and "" or "s"
			)
		)
	else
		notify(
			string.format(
				"↩️ Undid conflict resolution (%d conflict%s remaining)",
				remaining,
				remaining == 1 and "" or "s"
			)
		)
	end
	return true
end

--- Resets the active file to the original merge state at the beginning.
--- @return boolean
function M.reset_to_initial()
	local idx = M.state.active_idx
	local hist = M.state.history and M.state.history[idx]
	if not hist or not hist.initial_lines then
		notify("Already at original merge state", vim.log.levels.INFO)
		return false
	end

	local buf = M.state.result_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local item = M.state.files[idx]
	local snapshot = {
		lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
		spans = vim.deepcopy(M.state.spans),
		conflict_count = item and item.conflict_count or 0,
		cursor = pcall(vim.api.nvim_win_get_cursor, M.state.result_win) and vim.api.nvim_win_get_cursor(M.state.result_win)
			or nil,
	}
	table.insert(hist.stack, snapshot)

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, hist.initial_lines)

	M.state.spans = vim.deepcopy(hist.initial_spans)
	if item then
		item.conflict_count = hist.initial_count
		item.is_staged = false
	end

	-- Re-create extmarks for reset spans
	pcall(vim.api.nvim_buf_clear_namespace, buf, M.ns_spans, 0, -1)
	local total_lines = vim.api.nvim_buf_line_count(buf)
	for _, s in ipairs(M.state.spans or {}) do
		local s_row = math.max(0, math.min((s.start_line or 1) - 1, total_lines - 1))
		local e_row = math.max(s_row, math.min((s.end_line or s.start_line or 1) - 1, total_lines - 1))
		local extmark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_spans, s_row, 0, {
			end_row = e_row,
			end_col = 0,
			right_gravity = false,
			end_right_gravity = true,
		})
		s.extmark_id = extmark_id
	end

	M.update_result_highlights()
	M.render_sidebar()
	M.update_winbars()
	M.save_session()

	notify(
		string.format("🔄 Reset file back to original merge state at the beginning (%d conflicts)", hist.initial_count)
	)
	return true
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

-- ---------------------------------------------------------------------------
-- Panel Scrolling & Cursor Synchronization
-- ---------------------------------------------------------------------------

local is_syncing = false

--- Centers all panels (Result, Current, Incoming) on the given conflict span index.
--- @param span_id integer
function M.center_all_on_span(span_id)
	if not span_id then
		return
	end
	local s = M.state.spans and M.state.spans[span_id]
	local c_s = M.state.current_spans and M.state.current_spans[span_id]
	local i_s = M.state.incoming_spans and M.state.incoming_spans[span_id]

	if s and M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		local sl, _ = get_span_bounds(s)
		pcall(vim.api.nvim_win_set_cursor, M.state.result_win, { math.max(1, sl), 0 })
		pcall(vim.api.nvim_win_call, M.state.result_win, function()
			vim.cmd("normal! zz")
		end)
	end
	if c_s and M.state.current_win and vim.api.nvim_win_is_valid(M.state.current_win) then
		pcall(vim.api.nvim_win_set_cursor, M.state.current_win, { math.max(1, c_s.start_line), 0 })
		pcall(vim.api.nvim_win_call, M.state.current_win, function()
			vim.cmd("normal! zz")
		end)
	end
	if i_s and M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) then
		pcall(vim.api.nvim_win_set_cursor, M.state.incoming_win, { math.max(1, i_s.start_line), 0 })
		pcall(vim.api.nvim_win_call, M.state.incoming_win, function()
			vim.cmd("normal! zz")
		end)
	end
end

--- Maps a line number in the Result buffer to corresponding lines in Current (Ours) and Incoming (Theirs).
--- @param res_line integer
--- @return integer cur_line, integer inc_line
function M.map_result_line_to_top(res_line)
	local spans = M.state.spans or {}
	local c_spans = M.state.current_spans or {}
	local i_spans = M.state.incoming_spans or {}

	if #spans == 0 or #c_spans == 0 or #i_spans == 0 then
		return res_line, res_line
	end

	-- Before first span
	local first_s = spans[1]
	local first_s_start, _ = get_span_bounds(first_s)
	if res_line < first_s_start then
		return res_line, res_line
	end

	-- Inside or between spans
	for idx = 1, #spans do
		local s = spans[idx]
		local c_s = c_spans[idx] or c_spans[#c_spans]
		local i_s = i_spans[idx] or i_spans[#i_spans]
		local s_start, s_end = get_span_bounds(s)

		if res_line >= s_start and res_line <= s_end then
			local offset = res_line - s_start
			local c_line = c_s.start_line + math.min(offset, math.max(0, c_s.end_line - c_s.start_line))
			local i_line = i_s.start_line + math.min(offset, math.max(0, i_s.end_line - i_s.start_line))
			return c_line, i_line
		end

		local next_s = spans[idx + 1]
		if next_s then
			local next_s_start, _ = get_span_bounds(next_s)
			if res_line > s_end and res_line < next_s_start then
				local dist = res_line - s_end
				local c_line = c_s.end_line + dist
				local i_line = i_s.end_line + dist
				return c_line, i_line
			end
		end
	end

	-- After last span
	local last_s = spans[#spans]
	local last_c_s = c_spans[#c_spans]
	local last_i_s = i_spans[#i_spans]
	local _, last_s_end = get_span_bounds(last_s)
	local dist = res_line - last_s_end
	local c_line = last_c_s.end_line + dist
	local i_line = last_i_s.end_line + dist
	return c_line, i_line
end

--- Maps a line number from Current (Ours) or Incoming (Theirs) to the Result buffer.
--- @param top_line integer
--- @param is_incoming boolean
--- @return integer res_line
function M.map_top_line_to_result(top_line, is_incoming)
	local spans = M.state.spans or {}
	local target_spans = is_incoming and (M.state.incoming_spans or {}) or (M.state.current_spans or {})

	if #spans == 0 or #target_spans == 0 then
		return top_line
	end

	local first_t = target_spans[1]
	if top_line < first_t.start_line then
		return top_line
	end

	for idx = 1, #target_spans do
		local t_s = target_spans[idx]
		local s = spans[idx]
		if not s then
			break
		end
		local s_start, s_end = get_span_bounds(s)

		if top_line >= t_s.start_line and top_line <= t_s.end_line then
			local offset = top_line - t_s.start_line
			local res_line = s_start + math.min(offset, math.max(0, s_end - s_start))
			return res_line
		end

		local next_t = target_spans[idx + 1]
		if next_t then
			if top_line > t_s.end_line and top_line < next_t.start_line then
				local dist = top_line - t_s.end_line
				local res_line = s_end + dist
				return res_line
			end
		end
	end

	local last_t = target_spans[#target_spans]
	local last_s = spans[#spans]
	local _, last_s_end = get_span_bounds(last_s)
	local dist = top_line - last_t.end_line
	return last_s_end + dist
end

--- Synchronizes the top panels (Current & Incoming) to match the Result window's cursor position.
function M.sync_top_panels_from_result()
	if is_syncing or not M.state.is_open then
		return
	end
	if not M.state.result_win or not vim.api.nvim_win_is_valid(M.state.result_win) then
		return
	end
	if vim.api.nvim_get_current_win() ~= M.state.result_win then
		return
	end

	is_syncing = true
	pcall(function()
		local cursor = vim.api.nvim_win_get_cursor(M.state.result_win)
		local res_line = cursor[1]
		local cur_line, inc_line = M.map_result_line_to_top(res_line)
		local winline = vim.fn.winline()

		if M.state.current_win and vim.api.nvim_win_is_valid(M.state.current_win) and M.state.current_buf then
			local max_l = vim.api.nvim_buf_line_count(M.state.current_buf)
			local target = math.max(1, math.min(cur_line, max_l))
			local top_l = math.max(1, target - winline + 1)
			vim.api.nvim_win_call(M.state.current_win, function()
				pcall(vim.fn.winrestview, { topline = top_l, lnum = target, col = 0 })
			end)
		end

		if M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) and M.state.incoming_buf then
			local max_l = vim.api.nvim_buf_line_count(M.state.incoming_buf)
			local target = math.max(1, math.min(inc_line, max_l))
			local top_l = math.max(1, target - winline + 1)
			vim.api.nvim_win_call(M.state.incoming_win, function()
				pcall(vim.fn.winrestview, { topline = top_l, lnum = target, col = 0 })
			end)
		end
	end)
	is_syncing = false
end

--- Synchronizes the Result window and Incoming window when moving inside Current (Ours).
function M.sync_from_current_win()
	if is_syncing or not M.state.is_open then
		return
	end
	if not M.state.current_win or not vim.api.nvim_win_is_valid(M.state.current_win) then
		return
	end
	is_syncing = true
	pcall(function()
		local cur_line = vim.api.nvim_win_get_cursor(M.state.current_win)[1]
		local res_line = M.map_top_line_to_result(cur_line, false)
		local winline = vim.fn.winline()

		if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) and M.state.result_buf then
			local max_l = vim.api.nvim_buf_line_count(M.state.result_buf)
			local target = math.max(1, math.min(res_line, max_l))
			local top_l = math.max(1, target - winline + 1)
			vim.api.nvim_win_call(M.state.result_win, function()
				pcall(vim.fn.winrestview, { topline = top_l, lnum = target, col = 0 })
			end)
		end

		if M.state.incoming_win and vim.api.nvim_win_is_valid(M.state.incoming_win) and M.state.incoming_buf then
			local _, inc_line = M.map_result_line_to_top(res_line)
			local max_l = vim.api.nvim_buf_line_count(M.state.incoming_buf)
			local target = math.max(1, math.min(inc_line, max_l))
			local top_l = math.max(1, target - winline + 1)
			vim.api.nvim_win_call(M.state.incoming_win, function()
				pcall(vim.fn.winrestview, { topline = top_l, lnum = target, col = 0 })
			end)
		end
	end)
	is_syncing = false
end

--- Synchronizes the Result window and Current window when moving inside Incoming (Theirs).
function M.sync_from_incoming_win()
	if is_syncing or not M.state.is_open then
		return
	end
	if not M.state.incoming_win or not vim.api.nvim_win_is_valid(M.state.incoming_win) then
		return
	end
	is_syncing = true
	pcall(function()
		local inc_line = vim.api.nvim_win_get_cursor(M.state.incoming_win)[1]
		local res_line = M.map_top_line_to_result(inc_line, true)
		local winline = vim.fn.winline()

		if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) and M.state.result_buf then
			local max_l = vim.api.nvim_buf_line_count(M.state.result_buf)
			local target = math.max(1, math.min(res_line, max_l))
			local top_l = math.max(1, target - winline + 1)
			vim.api.nvim_win_call(M.state.result_win, function()
				pcall(vim.fn.winrestview, { topline = top_l, lnum = target, col = 0 })
			end)
		end

		if M.state.current_win and vim.api.nvim_win_is_valid(M.state.current_win) and M.state.current_buf then
			local cur_line, _ = M.map_result_line_to_top(res_line)
			local max_l = vim.api.nvim_buf_line_count(M.state.current_buf)
			local target = math.max(1, math.min(cur_line, max_l))
			local top_l = math.max(1, target - winline + 1)
			vim.api.nvim_win_call(M.state.current_win, function()
				pcall(vim.fn.winrestview, { topline = top_l, lnum = target, col = 0 })
			end)
		end
	end)
	is_syncing = false
end

function M.next_conflict()
	if not M.state.spans or #M.state.spans == 0 then
		notify("No conflicts in this file")
		return
	end
	local cursor_line = 1
	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		cursor_line = vim.api.nvim_win_get_cursor(M.state.result_win)[1]
	end

	for idx, s in ipairs(M.state.spans) do
		local s_start, _ = get_span_bounds(s)
		if s_start > cursor_line then
			M.center_all_on_span(idx)
			return
		end
	end

	M.center_all_on_span(1)
	notify("Wrapped to first conflict")
end

function M.prev_conflict()
	if not M.state.spans or #M.state.spans == 0 then
		notify("No conflicts in this file")
		return
	end
	local cursor_line = 1
	if M.state.result_win and vim.api.nvim_win_is_valid(M.state.result_win) then
		cursor_line = vim.api.nvim_win_get_cursor(M.state.result_win)[1]
	end

	for i = #M.state.spans, 1, -1 do
		local s = M.state.spans[i]
		local s_start, _ = get_span_bounds(s)
		if s_start < cursor_line then
			M.center_all_on_span(i)
			return
		end
	end

	M.center_all_on_span(#M.state.spans)
	notify("Wrapped to last conflict")
end

--- Aborts the in-progress Git merge and discards saved conflict session.
function M.abort_merge()
	local cwd = M.state.cwd or vim.fn.getcwd()
	local confirm_code = vim.fn.confirm(
		"⚠️ Are you sure you want to abort the Git merge?\nAll uncommitted conflict resolutions will be discarded.",
		"&Abort Merge\n&Cancel",
		2
	)
	if confirm_code ~= 1 then
		return
	end

	local ok_git, git = pcall(require, "krs.core.git")
	local success = false
	if ok_git and git and git.spawn then
		local proc = git.spawn({ "merge", "--abort" }, cwd)
		local res = proc and proc:wait()
		if res and res.code == 0 then
			success = true
		end
	end

	if not success then
		local out = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " merge --abort")
		if vim.v.shell_error == 0 then
			success = true
		else
			notify("Failed to abort merge: " .. tostring(out), vim.log.levels.ERROR)
			return
		end
	end

	M.clear_session(cwd)
	notify("❌ Git merge aborted and conflict session cleared.", vim.log.levels.WARN)
	M.close()
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
			M.clear_session(M.state.cwd)
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

	local function stop_insert_if_needed()
		if vim.fn.mode() == "i" then
			pcall(vim.cmd, "stopinsert")
		end
	end

	-- Conflict resolution actions (Ctrl+ prefixed as requested, plus single-key aliases)
	for _, k in ipairs({ "<C-1>", "<C-o>", "<C-O>", "co", "1" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.accept_current()
		end, opts)
	end

	for _, k in ipairs({ "<C-2>", "<C-t>", "<C-T>", "ct", "2" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.accept_incoming()
		end, opts)
	end

	for _, k in ipairs({ "<C-3>", "<C-b>", "<C-B>", "cb", "3" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.accept_both("current_first")
		end, opts)
	end

	for _, k in ipairs({ "<C-4>", "cB", "4" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.accept_both("incoming_first")
		end, opts)
	end

	-- Undo resolution (Ctrl+z / u)
	for _, k in ipairs({ "<C-z>", "u" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.undo()
		end, opts)
	end

	-- Conflict jumps (Ctrl+n / Ctrl+p / Ctrl+Down / Ctrl+Up, plus ]c / [c / ]x / [x)
	for _, k in ipairs({ "<C-n>", "<C-Down>", "]c", "]x" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.next_conflict()
		end, opts)
	end

	for _, k in ipairs({ "<C-p>", "<C-Up>", "[c", "[x" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.prev_conflict()
		end, opts)
	end

	-- Save & Stage (Ctrl+s, s)
	for _, k in ipairs({ "<C-s>", "<C-S>", "s" }) do
		vim.keymap.set({ "n", "i" }, k, function()
			stop_insert_if_needed()
			M.stage_current_file()
		end, opts)
	end

	-- Direct panel navigation (Ctrl+h/k/l/j, Alt+c/i/s, gc/gi/gs)
	vim.keymap.set("n", "<C-h>", M.focus_sidebar, opts)
	for _, k in ipairs({ "<C-k>", "<C-Up>", "<A-k>", "<M-k>", "<C-w>k", "<C-w><C-k>", "<C-w><Up>" }) do
		vim.keymap.set("n", k, M.focus_up, opts)
	end
	vim.keymap.set("n", "<C-l>", M.focus_incoming, opts)
	vim.keymap.set("n", "<C-j>", M.focus_result, opts)
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
	vim.keymap.set("n", "<C-/>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-_>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-q>", M.close, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
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

	-- Actions from sidebar
	for _, k in ipairs({ "<C-1>", "<C-o>", "1", "co" }) do
		vim.keymap.set("n", k, function()
			M.accept_current()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-2>", "<C-t>", "2", "ct" }) do
		vim.keymap.set("n", k, function()
			M.accept_incoming()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-3>", "<C-b>", "3", "cb" }) do
		vim.keymap.set("n", k, function()
			M.accept_both("current_first")
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-4>", "4", "cB" }) do
		vim.keymap.set("n", k, function()
			M.accept_both("incoming_first")
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-z>", "u" }) do
		vim.keymap.set("n", k, function()
			M.undo()
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-n>", "<C-Down>", "]c", "]x" }) do
		vim.keymap.set("n", k, function()
			M.next_conflict()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-p>", "<C-Up>", "[c", "[x" }) do
		vim.keymap.set("n", k, function()
			M.prev_conflict()
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-s>", "<C-S>", "s" }) do
		vim.keymap.set("n", k, M.stage_current_file, opts)
	end

	-- Panel navigation
	vim.keymap.set("n", "<C-k>", M.focus_current, opts)
	vim.keymap.set("n", "<C-l>", M.focus_incoming, opts)
	vim.keymap.set("n", "<C-j>", M.focus_result, opts)
	vim.keymap.set("n", "c", M.focus_current, opts)
	vim.keymap.set("n", "i", M.focus_incoming, opts)
	vim.keymap.set("n", "r", M.focus_result, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)

	-- Help & Close
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-/>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-_>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-q>", M.close, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
end

function M.attach_current_keymaps()
	local buf = M.state.current_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local opts = { buffer = buf, silent = true, nowait = true }

	for _, k in ipairs({ "<C-1>", "<C-o>", "1", "co" }) do
		vim.keymap.set("n", k, function()
			M.accept_current()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-2>", "<C-t>", "2", "ct" }) do
		vim.keymap.set("n", k, function()
			M.accept_incoming()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-3>", "<C-b>", "3", "cb" }) do
		vim.keymap.set("n", k, function()
			M.accept_both("current_first")
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-4>", "4", "cB" }) do
		vim.keymap.set("n", k, function()
			M.accept_both("incoming_first")
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-z>", "u" }) do
		vim.keymap.set("n", k, function()
			M.undo()
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-n>", "<C-Down>", "]c", "]x" }) do
		vim.keymap.set("n", k, function()
			M.next_conflict()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-p>", "<C-Up>", "[c", "[x" }) do
		vim.keymap.set("n", k, function()
			M.prev_conflict()
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-s>", "<C-S>", "s" }) do
		vim.keymap.set("n", k, M.stage_current_file, opts)
	end

	-- Panel navigation
	vim.keymap.set("n", "<C-h>", M.focus_sidebar, opts)
	vim.keymap.set("n", "<C-l>", M.focus_incoming, opts)
	vim.keymap.set("n", "<C-j>", M.focus_result, opts)
	vim.keymap.set("n", "c", M.focus_current, opts)
	vim.keymap.set("n", "i", M.focus_incoming, opts)
	vim.keymap.set("n", "r", M.focus_result, opts)
	vim.keymap.set("n", "s", M.focus_sidebar, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)

	-- Help & Close
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-/>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-_>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-q>", M.close, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
end

function M.attach_incoming_keymaps()
	local buf = M.state.incoming_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local opts = { buffer = buf, silent = true, nowait = true }

	for _, k in ipairs({ "<C-1>", "<C-o>", "1", "co" }) do
		vim.keymap.set("n", k, function()
			M.accept_current()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-2>", "<C-t>", "2", "ct" }) do
		vim.keymap.set("n", k, function()
			M.accept_incoming()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-3>", "<C-b>", "3", "cb" }) do
		vim.keymap.set("n", k, function()
			M.accept_both("current_first")
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-4>", "4", "cB" }) do
		vim.keymap.set("n", k, function()
			M.accept_both("incoming_first")
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-z>", "u" }) do
		vim.keymap.set("n", k, function()
			M.undo()
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-n>", "<C-Down>", "]c", "]x" }) do
		vim.keymap.set("n", k, function()
			M.next_conflict()
			M.focus_result()
		end, opts)
	end
	for _, k in ipairs({ "<C-p>", "<C-Up>", "[c", "[x" }) do
		vim.keymap.set("n", k, function()
			M.prev_conflict()
			M.focus_result()
		end, opts)
	end

	for _, k in ipairs({ "<C-s>", "<C-S>", "s" }) do
		vim.keymap.set("n", k, M.stage_current_file, opts)
	end

	-- Panel navigation
	vim.keymap.set("n", "<C-h>", M.focus_current, opts)
	vim.keymap.set("n", "<C-k>", M.focus_current, opts)
	vim.keymap.set("n", "<C-j>", M.focus_result, opts)
	vim.keymap.set("n", "c", M.focus_current, opts)
	vim.keymap.set("n", "i", M.focus_incoming, opts)
	vim.keymap.set("n", "r", M.focus_result, opts)
	vim.keymap.set("n", "s", M.focus_sidebar, opts)
	vim.keymap.set("n", "<Tab>", M.cycle_next_panel, opts)
	vim.keymap.set("n", "<S-Tab>", M.cycle_prev_panel, opts)

	-- Help & Close
	vim.keymap.set("n", "?", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-/>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-_>", M.show_help_popup, opts)
	vim.keymap.set("n", "<C-q>", M.close, opts)
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
		" 🧭 PANEL NAVIGATION (Ctrl + Directions):",
		"   <C-h> / s     Jump to Sidebar (left)",
		"   <C-k> / c     Jump to Current / Ours (top-left)",
		"   <C-l> / i     Jump to Incoming / Theirs (top-right)",
		"   <C-j> / r     Jump to Result (bottom)",
		"   <Tab>         Cycle next panel",
		"   <S-Tab>       Cycle previous panel",
		"",
		" ⚡ CONFLICT RESOLUTION (Any Panel / Result):",
		"   <C-1> / <C-o> Accept Ours (Current / HEAD) [Green]",
		"   <C-2> / <C-t> Accept Theirs (Incoming) [Blue]",
		"   <C-3> / <C-b> Accept Both (Ours first)",
		"   <C-4>         Accept Both (Theirs first)",
		"   <C-z> / u     Undo Resolution (repeat to reach initial)",
		"   <C-n> / ]c    Jump to Next conflict",
		"   <C-p> / [c    Jump to Previous conflict",
		"",
		" 💾 FILE ACTIONS:",
		"   <C-s> / s     Save file and stage with git add",
		"   <CR>          In sidebar: switch to file under cursor",
		"   <C-q> / q     Close Conflict Resolver",
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

	-- Check for existing saved session in .krsnvim/conflict_session.json
	local session = M.load_session(cwd)
	if session and session.files then
		for _, item in ipairs(M.state.files) do
			local s_f = session.files[item.file]
			if s_f then
				item.saved_lines = s_f.lines
				item.saved_spans = s_f.spans
				if s_f.conflict_count ~= nil then
					item.conflict_count = s_f.conflict_count
				end
				if s_f.is_staged ~= nil then
					item.is_staged = s_f.is_staged
				end
			end
		end
		if session.active_idx and session.active_idx >= 1 and session.active_idx <= #M.state.files then
			M.state.active_idx = session.active_idx
		end
	end

	M.state.prev_win = vim.api.nvim_get_current_win()
	M.state.prev_tab = vim.api.nvim_get_current_tabpage()

	-- Open dedicated tabpage (full-screen tiled workspace, like DAP UI)
	vim.cmd("tabnew")
	M.state.tab = vim.api.nvim_get_current_tabpage()
	local base_win = vim.api.nvim_get_current_win()

	-- 1. Create Sidebar window on the far left (width matched to neo-tree)
	local sb_width = M.get_sidebar_width()
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
	vim.wo[sidebar_win].winfixwidth = true

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
		vim.wo[sidebar_win].winfixwidth = true
	end

	M.state.is_open = true

	-- Attach keymaps
	M.attach_sidebar_keymaps()
	M.attach_current_keymaps()
	M.attach_incoming_keymaps()

	-- Load active or first conflicted file (restores saved progress if present)
	M.load_file(M.state.active_idx or 1)

	-- Focus on result window
	M.focus_result()

	-- Navigation watcher & Synchronized Scrolling across panels
	M.state.last_top_win = current_win
	local nav_group = vim.api.nvim_create_augroup("KrsConflictResolverNav", { clear = true })
	vim.api.nvim_create_autocmd("WinEnter", {
		group = nav_group,
		callback = function()
			if not M.state.is_open then
				return
			end
			local cur_win = vim.api.nvim_get_current_win()
			if cur_win == M.state.incoming_win then
				M.state.last_top_win = M.state.incoming_win
			elseif cur_win == M.state.current_win then
				M.state.last_top_win = M.state.current_win
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinScrolled" }, {
		group = nav_group,
		callback = function()
			if not M.state.is_open then
				return
			end
			local cur_win = vim.api.nvim_get_current_win()
			if cur_win == M.state.result_win then
				M.sync_top_panels_from_result()
			elseif cur_win == M.state.current_win then
				M.sync_from_current_win()
			elseif cur_win == M.state.incoming_win then
				M.sync_from_incoming_win()
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = nav_group,
		callback = function()
			if not M.state.is_open then
				return
			end
			local cur_buf = vim.api.nvim_get_current_buf()
			if cur_buf == M.state.result_buf then
				M.debounced_save_session()
			end
		end,
	})

	-- Tab closed autocmd to reset state if user closes tab manually
	local augroup = vim.api.nvim_create_augroup("KrsConflictResolverTab", { clear = true })
	vim.api.nvim_create_autocmd("TabClosed", {
		group = augroup,
		callback = function()
			if M.state.tab and not pcall(vim.api.nvim_tabpage_is_valid, M.state.tab) then
				M.save_session()
				M.state.is_open = false
				M.state.tab = nil
				M.state.sidebar_win = nil
				M.state.current_win = nil
				M.state.incoming_win = nil
				M.state.result_win = nil
				M.state.last_top_win = nil
				M.state.history = {}
				pcall(vim.api.nvim_del_augroup_by_name, "KrsConflictResolverNav")
			end
		end,
	})

	-- Resize watcher to enforce that sidebar maintains neo-tree width without growing
	local resize_group = vim.api.nvim_create_augroup("KrsConflictResolverResize", { clear = true })
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = resize_group,
		callback = function()
			if M.is_open() then
				M.enforce_sidebar_width()
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

	-- Save in-progress progress to .krsnvim/conflict_session.json unless all files are staged
	local all_staged = true
	if M.state.files and #M.state.files > 0 then
		for _, f in ipairs(M.state.files) do
			if not f.is_staged and (f.conflict_count or 0) > 0 then
				all_staged = false
				break
			end
		end
	end
	if all_staged then
		M.clear_session(M.state.cwd)
	else
		M.save_session()
	end

	M.state.is_open = false
	pcall(vim.api.nvim_del_augroup_by_name, "KrsConflictResolverResize")
	pcall(vim.api.nvim_del_augroup_by_name, "KrsConflictResolverNav")

	if M.state.result_buf and vim.api.nvim_buf_is_valid(M.state.result_buf) then
		unmap_result_keymaps(M.state.result_buf)
		pcall(vim.api.nvim_buf_clear_namespace, M.state.result_buf, M.ns_markers, 0, -1)
		pcall(vim.api.nvim_buf_clear_namespace, M.state.result_buf, M.ns_spans, 0, -1)
	end
	if M.state.current_buf and vim.api.nvim_buf_is_valid(M.state.current_buf) then
		pcall(vim.api.nvim_buf_clear_namespace, M.state.current_buf, M.ns_markers, 0, -1)
	end
	if M.state.incoming_buf and vim.api.nvim_buf_is_valid(M.state.incoming_buf) then
		pcall(vim.api.nvim_buf_clear_namespace, M.state.incoming_buf, M.ns_markers, 0, -1)
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
	M.state.last_top_win = nil
	M.state.history = {}
	M.state.current_spans = {}
	M.state.incoming_spans = {}

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

	vim.api.nvim_create_user_command("GitConflictUndo", function()
		M.undo()
	end, {
		desc = "Undo last merge conflict resolution step",
	})

	vim.api.nvim_create_user_command("GitConflictReset", function()
		M.reset_to_initial()
	end, {
		desc = "Reset current file back to initial merge conflict state",
	})

	vim.api.nvim_create_user_command("GitConflictAbortMerge", function()
		M.abort_merge()
	end, {
		desc = "Abort git merge and clear conflict session",
	})

	vim.api.nvim_create_user_command("KrsConflictAbortMerge", function()
		M.abort_merge()
	end, {
		desc = "Abort git merge and clear conflict session",
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
		"GitConflictUndo",
		"GitConflictReset",
		"GitConflictAbortMerge",
		"KrsConflictAbortMerge",
	},
	config = function()
		M.setup()
	end,
}, { __index = M })
