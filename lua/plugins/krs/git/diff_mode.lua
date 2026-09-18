-- ============================================================================
-- KRS PLUGIN: Git Diff Mode (Same Branch & Between Branches)
-- ============================================================================
-- WHAT IT PROVIDES
--   1. Git Diff Mode (Same Branch):
--      - Single code window view (keeps active editor buffer).
--      - Added lines highlighted in green, deleted lines shown via virtual lines in red.
--      - Compares working tree (staged & unstaged changes) against HEAD by default.
--      - Configurable commits behind (HEAD~N vs Working Tree or HEAD~N vs HEAD).
--      - Or comparison between any two selected commits via an interactive picker.
--      - Docked right sidebar files list window with diff status.
--      - Jump to next/previous modification in current file (]c / [c / ]d / [d).
--   2. Git Diff Mode (Between 2 Branches):
--      - Two vertical menus to pick Base Branch (left) and Target Branch (right).
--      - Side-by-side dual windows comparing the same file across both branches.
--      - Selecting a file updates BOTH left and right windows synchronously.
--      - Synchronized scroll and cursor binding.
--      - Modification jumps (]c / [c / ]d / [d).
--   3. Integration:
--      - Toggleable from Git Center with 'v' (menu) or 'V' (instant toggle).
--      - Ex commands: :GitDiffMode, :GitDiffSameBranch, :GitDiffBetweenBranches,
--        :GitDiffClose, :GitDiffToggle.
--      - Command Palette discoverability.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local git = lazy_req("krs.git.cmd")
local diff = lazy_req("krs.git.diff")
local ui = lazy_req("krs.core.ui")
local path_util = lazy_req("krs.core.path")
local project = lazy_req("krs.core.project")
local z_index = lazy_req("krs.core.z_index")

local M = {}

M.namespace = vim.api.nvim_create_namespace("krs_git_diff_mode")
M.files_namespace = vim.api.nvim_create_namespace("krs_git_diff_mode_files")

--- Internal state
M.state = {
	is_active = false,
	mode = "same_branch", -- "same_branch" | "between_branches"
	commits_behind = 0, -- 0 for worktree vs HEAD, or N >= 1 for HEAD~N
	include_worktree = true, -- true to include staged & unstaged changes
	base_ref = "HEAD",
	target_ref = "WORKTREE", -- "WORKTREE" | "HEAD" | commit SHA / branch
	custom_commits = false,
	cwd = nil,
	files = {}, -- array of { file = string, status = string, raw_status = string }
	selected_file_idx = 1,
	active_file = nil,

	-- Sidebar file list window
	file_list_win = nil,
	file_list_buf = nil,

	-- Dual split windows for between_branches
	dual_left_win = nil,
	dual_left_buf = nil,
	dual_right_win = nil,
	dual_right_buf = nil,

	-- Editor window & previous layout
	editor_win = nil,
	prev_win = nil,
	prev_buf = nil,

	-- Line modifications in active file for jumping
	current_modifications = {},
}

local EMPTY_TREE_SHA = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

--- Notifies user with Diff Mode prefix
--- @param msg string
--- @param level integer|nil
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "Git Diff Mode" })
end

--- Validates and sanitizes commits behind count (non-negative integer)
--- @param val any
--- @return integer
function M.sanitize_commits_behind(val)
	local num = tonumber(val)
	if not num or num < 0 then
		return 0
	end
	return math.floor(num)
end

--- Checks if Git Diff Mode is currently active
--- @return boolean
function M.is_open()
	return M.state.is_active
		or (M.state.file_list_win ~= nil and vim.api.nvim_win_is_valid(M.state.file_list_win))
		or (M.state.dual_left_win ~= nil and vim.api.nvim_win_is_valid(M.state.dual_left_win))
end

--- Resolves the effective base ref for HEAD~N, falling back to empty tree if history is shallow
--- @param cwd string
--- @param n integer
--- @return string
local function resolve_head_ancestor(cwd, n)
	n = M.sanitize_commits_behind(n)
	if n == 0 then
		return "HEAD"
	end
	local test_ref = "HEAD~" .. tostring(n)
	local lines = git.lines({ "rev-parse", "--verify", test_ref }, cwd)
	if #lines > 0 and lines[1]:match("^%x+$") then
		return test_ref
	end
	-- Fall back to root commit or empty tree
	local root_commits = git.lines({ "rev-list", "--max-parents=0", "HEAD" }, cwd)
	if #root_commits > 0 and root_commits[1]:match("^%x+$") then
		return root_commits[1]
	end
	return EMPTY_TREE_SHA
end

--- Queries changed files between base_ref and target_ref
--- When target_ref is "WORKTREE", queries against the live working directory (staged + unstaged)
--- @param base_ref string
--- @param target_ref string
--- @param cwd string
--- @return table[] files
function M.get_changed_files(base_ref, target_ref, cwd)
	local raw
	if target_ref == "WORKTREE" then
		raw = git.lines({ "diff", "--name-status", "--no-ext-diff", base_ref }, cwd)
	else
		raw = git.lines({ "diff", "--name-status", "--no-ext-diff", base_ref, target_ref }, cwd)
	end

	local files = {}
	local seen = {}
	for _, line in ipairs(raw) do
		local status_code, file_path = line:match("^([A-Z%d]+)%s+(.+)$")
		if status_code and file_path then
			local new_path = file_path:match("%s+(.+)$") or file_path
			local trimmed = vim.trim(new_path)
			if not seen[trimmed] then
				seen[trimmed] = true
				table.insert(files, {
					status = status_code:sub(1, 1),
					raw_status = status_code,
					file = trimmed,
				})
			end
		end
	end

	if target_ref == "WORKTREE" then
		local untracked = git.lines({ "ls-files", "--others", "--exclude-standard" }, cwd)
		for _, u_file in ipairs(untracked) do
			local trimmed = vim.trim(u_file)
			if trimmed ~= "" and not seen[trimmed] then
				seen[trimmed] = true
				table.insert(files, {
					status = "?",
					raw_status = "?",
					file = trimmed,
				})
			end
		end
	end

	return files
end

--- Clears diff highlights and extmarks in a buffer
--- @param bufnr integer
local function clear_buffer_diff_highlights(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
	end
end

--- Computes diff and applies inline/line highlights to the given buffer
--- @param bufnr integer
--- @param file_path string
--- @param base_ref string
--- @param target_ref string
--- @param cwd string
--- @return integer[] modification_lines
function M.apply_same_branch_highlights(bufnr, file_path, base_ref, target_ref, cwd)
	clear_buffer_diff_highlights(bufnr)
	diff.setup_highlights()

	local rel_path = path_util.relative_to(file_path, cwd) or file_path
	local diff_args
	if target_ref == "WORKTREE" then
		diff_args = { "diff", "-U0", "--no-ext-diff", base_ref, "--", rel_path }
	else
		diff_args = { "diff", "-U0", "--no-ext-diff", base_ref, target_ref, "--", rel_path }
	end
	local raw_diff = git.lines(diff_args, cwd)
	if #raw_diff == 0 and target_ref == "WORKTREE" then
		local untracked = git.lines({ "ls-files", "--others", "--exclude-standard", "--", rel_path }, cwd)
		if #untracked > 0 then
			raw_diff = git.lines({ "diff", "--no-index", "-U0", "--", "/dev/null", rel_path }, cwd)
		end
	end

	local modification_lines = {}
	if #raw_diff == 0 then
		M.state.current_modifications = {}
		return modification_lines
	end

	local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
	local current_hunk_new_start = nil
	local deleted_lines_acc = {}

	local function flush_deleted()
		if #deleted_lines_acc > 0 and current_hunk_new_start then
			local virt_lines = {}
			for _, del in ipairs(deleted_lines_acc) do
				table.insert(virt_lines, { { "  - " .. del, "GitCenterDiffDelete" } })
			end
			local target_row = math.max(0, math.min(buf_line_count - 1, current_hunk_new_start - 1))
			pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, target_row, 0, {
				virt_lines = virt_lines,
				virt_lines_above = true,
				priority = 60,
			})
			deleted_lines_acc = {}
		end
	end

	for _, line in ipairs(raw_diff) do
		local hunk_match = line:match("^@@ %-%d+,?%d* %+(%d+)")
		if hunk_match then
			flush_deleted()
			local new_start = tonumber(hunk_match) or 1
			current_hunk_new_start = math.max(1, new_start)
			table.insert(modification_lines, current_hunk_new_start)
		elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
			table.insert(deleted_lines_acc, line:sub(2))
		elseif line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
			if current_hunk_new_start then
				local row = current_hunk_new_start - 1
				if row >= 0 and row < buf_line_count then
					pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, row, 0, {
						line_hl_group = "GitCenterDiffAdd",
						priority = 50,
					})
				end
				current_hunk_new_start = current_hunk_new_start + 1
			end
		end
	end
	flush_deleted()

	M.state.current_modifications = modification_lines
	return modification_lines
end

--- Moves cursor to next modification in active file
function M.jump_next_modification()
	local mods = M.state.current_modifications
	if not mods or #mods == 0 then
		notify("No diff modifications in active file", vim.log.levels.WARN)
		return
	end

	local cur_row = vim.api.nvim_win_get_cursor(0)[1]
	for _, row in ipairs(mods) do
		if row > cur_row then
			pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
			pcall(vim.cmd, "normal! zz")
			return
		end
	end
	-- Wrap to first
	pcall(vim.api.nvim_win_set_cursor, 0, { mods[1], 0 })
	pcall(vim.cmd, "normal! zz")
	notify("Jumped to first modification (wrapped)")
end

--- Moves cursor to previous modification in active file
function M.jump_prev_modification()
	local mods = M.state.current_modifications
	if not mods or #mods == 0 then
		notify("No diff modifications in active file", vim.log.levels.WARN)
		return
	end

	local cur_row = vim.api.nvim_win_get_cursor(0)[1]
	for i = #mods, 1, -1 do
		local row = mods[i]
		if row < cur_row then
			pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
			pcall(vim.cmd, "normal! zz")
			return
		end
	end
	-- Wrap to last
	pcall(vim.api.nvim_win_set_cursor, 0, { mods[#mods], 0 })
	pcall(vim.cmd, "normal! zz")
	notify("Jumped to last modification (wrapped)")
end

--- Determines if a window can serve as the main code editor window
--- Rejects nil, invalid windows, the diff sidebar, dual left window, and floating windows
--- @param win integer|nil
--- @return boolean
local function is_valid_editor_win(win)
	if not (win and vim.api.nvim_win_is_valid(win)) then
		return false
	end
	-- Never target the diff sidebar window
	if win == M.state.file_list_win then
		return false
	end
	-- In dual mode, dual_left is Base (scratch), dual_right is Target (editor)
	if win == M.state.dual_left_win then
		return false
	end
	if M.state.mode == "between_branches" and win == M.state.dual_right_win then
		return true
	end
	-- Reject floating windows
	local cfg = vim.api.nvim_win_get_config(win)
	if cfg.relative and cfg.relative ~= "" then
		return false
	end
	-- Reject sidebar/tree buffers if possible
	local b = vim.api.nvim_win_get_buf(win)
	if b and vim.api.nvim_buf_is_valid(b) then
		local ft = vim.bo[b].filetype
		if ft == "krs_diff_sidebar" or ft == "neo-tree" or ft == "NvimTree" then
			return false
		end
	end
	return true
end

--- Finds or creates a valid code editor window
--- @return integer
local function get_valid_editor_win()
	if is_valid_editor_win(M.state.editor_win) then
		return M.state.editor_win
	end
	if is_valid_editor_win(M.state.prev_win) then
		M.state.editor_win = M.state.prev_win
		return M.state.prev_win
	end

	-- Search current tabpage windows for a non-sidebar, non-float window
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if is_valid_editor_win(w) then
			M.state.editor_win = w
			return w
		end
	end

	-- If no valid editor window exists, create a new split to the left of the sidebar
	local cur_win = vim.api.nvim_get_current_win()
	local new_win
	if cur_win == M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		new_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(true, false), true, {
			win = M.state.file_list_win,
			split = "left",
		})
	else
		new_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(true, false), true, {
			win = -1,
			split = "left",
		})
	end
	M.state.editor_win = new_win
	return new_win
end

--- Renders contents of right sidebar changed files list window
local function render_file_list()
	if not (M.state.file_list_buf and vim.api.nvim_buf_is_valid(M.state.file_list_buf)) then
		return
	end

	local lines = {}
	local header_title
	if M.state.mode == "between_branches" then
		header_title = string.format(" 🌿 Diff: %s ⇄ %s", M.state.base_ref, M.state.target_ref)
	elseif M.state.target_ref == "WORKTREE" then
		if M.state.commits_behind > 0 then
			header_title = string.format(" 🔍 Diff: Worktree + HEAD~%d (%s)", M.state.commits_behind, M.state.base_ref)
		else
			header_title = " 🔍 Diff: Worktree (Staged/Unstaged) vs HEAD"
		end
	else
		header_title = string.format(" 🔍 Diff: %s..%s", M.state.base_ref, M.state.target_ref)
	end

	table.insert(lines, header_title)
	table.insert(lines, string.rep("─", 36))

	if #M.state.files == 0 then
		table.insert(lines, "  (No changed files)")
	else
		for idx, item in ipairs(M.state.files) do
			local icon = "󰝤"
			if item.status == "A" then
				icon = ""
			elseif item.status == "D" then
				icon = ""
			elseif item.status == "R" then
				icon = "➜"
			elseif item.status == "?" then
				icon = ""
			end
			local marker = (idx == M.state.selected_file_idx) and "▶" or " "
			local filename = path_util.filename(item.file)
			local parent = vim.fs.dirname(item.file)
			local display_path = (parent and parent ~= "." and parent ~= "") and (filename .. " (" .. parent .. ")")
				or filename
			table.insert(lines, string.format("%s %s [%s] %s", marker, icon, item.status, display_path))
		end
	end

	table.insert(lines, string.rep("─", 36))
	table.insert(lines, " [Enter/Space]: Select | [h/Esc]: Code")
	table.insert(lines, " [c]: Config/Range     | [q]: Close   ")

	vim.bo[M.state.file_list_buf].modifiable = true
	vim.api.nvim_buf_set_lines(M.state.file_list_buf, 0, -1, false, lines)
	vim.bo[M.state.file_list_buf].modifiable = false

	-- Apply highlights to status markers
	vim.api.nvim_buf_clear_namespace(M.state.file_list_buf, M.files_namespace, 0, -1)
	for i = 3, 2 + #M.state.files do
		local item = M.state.files[i - 2]
		if item then
			local hl = "GitCenterDiffContext"
			if item.status == "A" then
				hl = "GitCenterDiffAddPrefix"
			elseif item.status == "D" then
				hl = "GitCenterDiffDeletePrefix"
			elseif item.status == "M" or item.status == "R" then
				hl = "GitCenterDiffHeader"
			elseif item.status == "?" then
				hl = "GitCenterDiffContext"
			end
			pcall(vim.api.nvim_buf_add_highlight, M.state.file_list_buf, M.files_namespace, hl, i - 1, 2, 7)
			if (i - 2) == M.state.selected_file_idx then
				pcall(
					vim.api.nvim_buf_add_highlight,
					M.state.file_list_buf,
					M.files_namespace,
					"GitCenterDiffHeader",
					i - 1,
					0,
					1
				)
			end
		end
	end
end

--- Opens or focuses the docked right sidebar changed files list window
--- @param files? table[]
--- @param selected_idx? integer
--- @return integer win, integer buf
function M.open_file_list_window(files, selected_idx)
	if files then
		M.state.files = files
	end
	if selected_idx then
		M.state.selected_file_idx = selected_idx
	end

	local total_cols = vim.o.columns
	local width = math.min(42, math.max(30, math.floor(total_cols * 0.28)))

	if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		pcall(vim.api.nvim_win_set_width, M.state.file_list_win, width)
		render_file_list()
		return M.state.file_list_win, M.state.file_list_buf
	end

	local buf = vim.api.nvim_create_buf(false, true)
	M.state.file_list_buf = buf
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "krs_diff_sidebar"
	vim.bo[buf].modifiable = false

	local win = vim.api.nvim_open_win(buf, false, {
		win = -1,
		split = "right",
		width = width,
	})
	M.state.file_list_win = win

	vim.wo[win].winfixwidth = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].spell = false

	render_file_list()

	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

	-- Navigation mappings inside file list
	vim.keymap.set("n", "j", function()
		if #M.state.files == 0 then
			return
		end
		M.state.selected_file_idx = (M.state.selected_file_idx % #M.state.files) + 1
		render_file_list()
		pcall(vim.api.nvim_win_set_cursor, win, { 2 + M.state.selected_file_idx, 0 })
	end, opts)

	vim.keymap.set("n", "k", function()
		if #M.state.files == 0 then
			return
		end
		M.state.selected_file_idx = M.state.selected_file_idx - 1
		if M.state.selected_file_idx < 1 then
			M.state.selected_file_idx = #M.state.files
		end
		render_file_list()
		pcall(vim.api.nvim_win_set_cursor, win, { 2 + M.state.selected_file_idx, 0 })
	end, opts)

	local function open_selected()
		local file_entry = M.state.files[M.state.selected_file_idx]
		if not file_entry then
			return
		end
		if M.state.mode == "same_branch" then
			M.open_file_same_branch(file_entry.file)
		else
			M.open_file_between_branches(file_entry.file)
		end
	end

	vim.keymap.set("n", "<CR>", open_selected, opts)
	vim.keymap.set("n", "<Space>", open_selected, opts)

	-- Navigation shortcuts to return focus to code editor
	for _, key in ipairs({ "<Esc>", "h" }) do
		vim.keymap.set("n", key, function()
			M.focus_editor()
		end, opts)
	end

	vim.keymap.set("n", "q", function()
		M.close()
	end, opts)

	vim.keymap.set("n", "c", function()
		M.open_config_dialog()
	end, opts)

	return win, buf
end

--- Toggles focus between the editor and the docked right sidebar
function M.toggle_attention()
	if not M.is_open() then
		return false
	end

	local cur_win = vim.api.nvim_get_current_win()
	if cur_win == M.state.file_list_win then
		M.focus_editor()
	else
		M.focus_file_list()
	end
	return true
end

--- Focuses the docked right sidebar file list window
function M.focus_file_list()
	if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		pcall(vim.api.nvim_set_current_win, M.state.file_list_win)
		if M.state.file_list_buf and vim.api.nvim_buf_is_valid(M.state.file_list_buf) then
			local count = vim.api.nvim_buf_line_count(M.state.file_list_buf)
			local target_row = math.min(count, math.max(1, 2 + (M.state.selected_file_idx or 1)))
			pcall(vim.api.nvim_win_set_cursor, M.state.file_list_win, { target_row, 0 })
		end
	end
end

--- Focuses the main code editor window
--- @return integer|nil
function M.focus_editor()
	if M.state.mode == "between_branches" then
		if M.state.dual_right_win and vim.api.nvim_win_is_valid(M.state.dual_right_win) then
			pcall(vim.api.nvim_set_current_win, M.state.dual_right_win)
			return M.state.dual_right_win
		end
	end

	local win = get_valid_editor_win()
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_set_current_win, win)
		return win
	end
	return nil
end

--- Opens a file in Same Branch Diff Mode (single code window)
--- @param file_path string
function M.open_file_same_branch(file_path)
	M.state.active_file = file_path
	local full_path = path_util.join(M.state.cwd, file_path)

	local target_win = M.focus_editor()
	if
		not target_win
		or target_win == M.state.file_list_win
		or vim.api.nvim_get_current_win() == M.state.file_list_win
	then
		target_win = get_valid_editor_win()
		if target_win and target_win ~= M.state.file_list_win then
			pcall(vim.api.nvim_set_current_win, target_win)
		end
	end

	if vim.api.nvim_get_current_win() == M.state.file_list_win then
		notify("Error: Cannot open diff file inside sidebar window", vim.log.levels.ERROR)
		return
	end

	local ok, _ = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(full_path))
	if not ok then
		notify("Could not open file: " .. file_path, vim.log.levels.WARN)
		return
	end

	local cur_buf = vim.api.nvim_get_current_buf()
	M.apply_same_branch_highlights(cur_buf, file_path, M.state.base_ref, M.state.target_ref, M.state.cwd)

	-- Jump to first modification if present
	if #M.state.current_modifications > 0 then
		pcall(vim.api.nvim_win_set_cursor, 0, { M.state.current_modifications[1], 0 })
		pcall(vim.cmd, "normal! zz")
	end
end

--- Starts Git Diff Mode (Same Branch)
--- @param opts? { commits_behind?: integer, base_ref?: string, target_ref?: string, include_worktree?: boolean, cwd?: string }
function M.start_same_branch(opts)
	if type(opts) == "number" then
		opts = { commits_behind = opts }
	else
		opts = opts or {}
	end
	local cwd = opts.cwd or path_util.normalize(project.root() or vim.fn.getcwd())
	if not git.is_repository(cwd) then
		notify("Current directory is not a Git repository", vim.log.levels.WARN)
		return
	end

	M.state.cwd = cwd
	M.state.mode = "same_branch"
	M.state.is_active = true

	if opts.commits_behind ~= nil then
		M.state.commits_behind = M.sanitize_commits_behind(opts.commits_behind)
	else
		M.state.commits_behind = M.state.commits_behind or 0
	end

	if opts.include_worktree ~= nil then
		M.state.include_worktree = opts.include_worktree
	else
		M.state.include_worktree = (M.state.commits_behind == 0) or (M.state.include_worktree ~= false)
	end

	if opts.base_ref and opts.target_ref then
		M.state.base_ref = opts.base_ref
		M.state.target_ref = opts.target_ref
		M.state.custom_commits = (opts.target_ref ~= "WORKTREE" and opts.target_ref ~= "HEAD")
	else
		M.state.custom_commits = false
		if M.state.commits_behind == 0 then
			M.state.base_ref = "HEAD"
			M.state.target_ref = "WORKTREE"
		elseif M.state.include_worktree then
			M.state.base_ref = resolve_head_ancestor(cwd, M.state.commits_behind)
			M.state.target_ref = "WORKTREE"
		else
			M.state.base_ref = resolve_head_ancestor(cwd, M.state.commits_behind)
			M.state.target_ref = "HEAD"
		end
	end

	-- Resolve editor window BEFORE opening or touching sidebar
	local current = vim.api.nvim_get_current_win()
	if is_valid_editor_win(current) then
		M.state.editor_win = current
		M.state.prev_win = current
		M.state.prev_buf = vim.api.nvim_get_current_buf()
	elseif not is_valid_editor_win(M.state.editor_win) then
		M.state.editor_win = get_valid_editor_win()
	end

	M.state.files = M.get_changed_files(M.state.base_ref, M.state.target_ref, cwd)

	M.open_file_list_window()

	-- Determine initial file to show
	local initial_file = nil
	local cur_file = M.state.prev_buf
			and vim.api.nvim_buf_is_valid(M.state.prev_buf)
			and vim.api.nvim_buf_get_name(M.state.prev_buf)
		or nil
	if cur_file and cur_file ~= "" then
		local rel = path_util.relative_to(cur_file, cwd)
		for idx, item in ipairs(M.state.files) do
			if item.file == rel then
				M.state.selected_file_idx = idx
				initial_file = item.file
				break
			end
		end
	end

	if not initial_file and #M.state.files > 0 then
		if M.state.selected_file_idx and M.state.files[M.state.selected_file_idx] then
			initial_file = M.state.files[M.state.selected_file_idx].file
		else
			M.state.selected_file_idx = 1
			initial_file = M.state.files[1].file
		end
	end

	if initial_file then
		M.open_file_same_branch(initial_file)
	else
		notify("No modified files between " .. M.state.base_ref .. " and " .. M.state.target_ref, vim.log.levels.INFO)
	end

	render_file_list()
end

--- Opens a file in Between Branches Diff Mode (side-by-side dual windows)
--- @param file_path string
function M.open_file_between_branches(file_path)
	M.state.active_file = file_path
	local cwd = M.state.cwd
	local base_b = M.state.base_ref
	local target_b = M.state.target_ref

	local editor_win = get_valid_editor_win()

	-- Ensure side-by-side splits exist
	if
		not (M.state.dual_left_win and vim.api.nvim_win_is_valid(M.state.dual_left_win))
		or not (M.state.dual_right_win and vim.api.nvim_win_is_valid(M.state.dual_right_win))
	then
		M.state.dual_left_win = editor_win
		local right_buf = vim.api.nvim_create_buf(false, true)
		local right_win = vim.api.nvim_open_win(right_buf, false, {
			win = editor_win,
			split = "right",
		})
		M.state.dual_right_win = right_win
		M.state.dual_right_buf = right_buf
	end

	-- Create scratch buffers
	local left_buf = M.state.dual_left_buf
	if not (left_buf and vim.api.nvim_buf_is_valid(left_buf)) then
		left_buf = vim.api.nvim_create_buf(false, true)
		M.state.dual_left_buf = left_buf
		vim.api.nvim_win_set_buf(M.state.dual_left_win, left_buf)
	end

	local right_buf = M.state.dual_right_buf
	if not (right_buf and vim.api.nvim_buf_is_valid(right_buf)) then
		right_buf = vim.api.nvim_create_buf(false, true)
		M.state.dual_right_buf = right_buf
		vim.api.nvim_win_set_buf(M.state.dual_right_win, right_buf)
	end

	for _, b in ipairs({ left_buf, right_buf }) do
		vim.bo[b].buftype = "nofile"
		vim.bo[b].bufhidden = "wipe"
		vim.bo[b].swapfile = false
	end

	-- Detect filetype
	local ft = vim.filetype.match({ filename = file_path })
	if ft then
		vim.bo[left_buf].filetype = ft
		vim.bo[right_buf].filetype = ft
	end

	-- Compute side-by-side diff
	local raw_diff = git.lines({ "diff", "-U0", "--no-ext-diff", base_b, target_b, "--", file_path }, cwd)
	local l_lines, left_kinds, r_lines, right_kinds = diff.format_side_by_side_dual(raw_diff, false)

	vim.bo[left_buf].modifiable = true
	vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, l_lines)
	vim.bo[left_buf].modifiable = false

	vim.bo[right_buf].modifiable = true
	vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, r_lines)
	vim.bo[right_buf].modifiable = false

	diff.apply_highlights_side_by_side_dual(left_buf, left_kinds, right_buf, right_kinds, file_path)

	-- Set synchronized scrolling
	for _, w in ipairs({ M.state.dual_left_win, M.state.dual_right_win }) do
		vim.api.nvim_set_option_value("scrollbind", true, { win = w })
		vim.api.nvim_set_option_value("cursorbind", true, { win = w })
		vim.api.nvim_set_option_value("wrap", false, { win = w })
	end

	-- Record modifications for jumping
	local mods = {}
	for idx, kind in ipairs(right_kinds) do
		if kind == "add" or kind == "header" then
			table.insert(mods, idx)
		end
	end
	M.state.current_modifications = mods

	M.focus_editor()
end

--- Starts Git Diff Mode (Between 2 Branches)
--- @param branch1 string
--- @param branch2 string
--- @param cwd? string
function M.start_between_branches(branch1, branch2, cwd)
	cwd = cwd or path_util.normalize(project.root() or vim.fn.getcwd())
	if not git.is_repository(cwd) then
		notify("Current directory is not a Git repository", vim.log.levels.WARN)
		return
	end

	M.state.cwd = cwd
	M.state.mode = "between_branches"
	M.state.is_active = true
	M.state.base_ref = branch1
	M.state.target_ref = branch2

	local current = vim.api.nvim_get_current_win()
	if is_valid_editor_win(current) then
		M.state.editor_win = current
		M.state.prev_win = current
		M.state.prev_buf = vim.api.nvim_get_current_buf()
	elseif not is_valid_editor_win(M.state.editor_win) then
		M.state.editor_win = get_valid_editor_win()
	end

	M.state.files = M.get_changed_files(branch1, branch2, cwd)
	M.state.selected_file_idx = 1

	M.open_file_list_window()

	if #M.state.files > 0 then
		M.open_file_between_branches(M.state.files[1].file)
	else
		notify(string.format("No differences found between %s and %s", branch1, branch2), vim.log.levels.INFO)
	end

	render_file_list()
end

--- Closes Git Diff Mode and restores previous layout
--- @param opts? { keep_state?: boolean }
function M.close(opts)
	opts = opts or {}
	if not opts.keep_state then
		M.state.is_active = false
	end

	-- Clear extmarks
	if M.state.prev_buf and vim.api.nvim_buf_is_valid(M.state.prev_buf) then
		clear_buffer_diff_highlights(M.state.prev_buf)
	end
	local cur_buf = vim.api.nvim_get_current_buf()
	if cur_buf and vim.api.nvim_buf_is_valid(cur_buf) then
		clear_buffer_diff_highlights(cur_buf)
	end

	-- Close file list window
	if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		ui.close(M.state.file_list_win)
	end
	M.state.file_list_win = nil
	M.state.file_list_buf = nil

	-- Restore windows from dual mode
	if M.state.mode == "between_branches" then
		if M.state.dual_left_win and vim.api.nvim_win_is_valid(M.state.dual_left_win) then
			pcall(vim.api.nvim_set_option_value, "scrollbind", false, { win = M.state.dual_left_win })
			pcall(vim.api.nvim_set_option_value, "cursorbind", false, { win = M.state.dual_left_win })
			if M.state.prev_buf and vim.api.nvim_buf_is_valid(M.state.prev_buf) then
				pcall(vim.api.nvim_win_set_buf, M.state.dual_left_win, M.state.prev_buf)
			end
		end
		if M.state.dual_right_win and vim.api.nvim_win_is_valid(M.state.dual_right_win) then
			pcall(vim.api.nvim_set_option_value, "scrollbind", false, { win = M.state.dual_right_win })
			pcall(vim.api.nvim_set_option_value, "cursorbind", false, { win = M.state.dual_right_win })
			ui.close(M.state.dual_right_win)
		end
		M.state.dual_left_win, M.state.dual_left_buf = nil, nil
		M.state.dual_right_win, M.state.dual_right_buf = nil, nil
	end

	local target_win = M.state.editor_win or M.state.prev_win
	if target_win and vim.api.nvim_win_is_valid(target_win) then
		pcall(vim.api.nvim_set_current_win, target_win)
	end
	M.state.editor_win = nil
end

--- Opens two vertical menus to select Base Branch (left) and Target Branch (right)
--- If fewer than 2 branches exist, prompts via input_modal rather than failing
--- @param cwd string|nil
function M.open_branch_selector_modal(cwd)
	cwd = cwd or path_util.normalize(project.root() or vim.fn.getcwd())
	local queries = require("plugins.krs.git.git_center.queries")
	local input_modal = require("plugins.krs.ui.input_modal")
	local raw_branches = queries.git_lines({ "branch", "-a", "--sort=-committerdate" }, cwd)

	local branch_names = {}
	local current_branch = queries.git_lines({ "branch", "--show-current" }, cwd)[1] or "main"

	for _, line in ipairs(raw_branches) do
		local clean = line:gsub("^%*%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
		if clean ~= "" and not clean:match("HEAD %->") then
			local display_name = clean:gsub("^remotes/", "")
			local exists = false
			for _, b in ipairs(branch_names) do
				if b == display_name then
					exists = true
					break
				end
			end
			if not exists then
				table.insert(branch_names, display_name)
			end
		end
	end

	-- Also fetch git tags to enrich available refs
	local raw_tags = queries.git_lines({ "tag", "--sort=-creatordate" }, cwd)
	for _, tag in ipairs(raw_tags) do
		local clean_tag = vim.trim(tag)
		if clean_tag ~= "" then
			local exists = false
			for _, b in ipairs(branch_names) do
				if b == clean_tag then
					exists = true
					break
				end
			end
			if not exists then
				table.insert(branch_names, clean_tag)
			end
		end
	end

	-- When fewer than 2 branches exist, prompt user directly for refs instead of error toast
	if #branch_names < 2 then
		local def_base = branch_names[1] or current_branch or "HEAD"
		input_modal.open({
			label = "Base Branch / Ref (Left side):",
			default_value = def_base,
			relative = "editor",
			callback = function(ok1, base_ref)
				if not ok1 or not base_ref or vim.trim(base_ref) == "" then
					return
				end
				base_ref = vim.trim(base_ref)
				local def_target = base_ref:match("^origin/") and base_ref:gsub("^origin/", "") or ("origin/" .. base_ref)
				input_modal.open({
					label = "Target Branch / Ref to compare with (Right side):",
					default_value = def_target,
					relative = "editor",
					callback = function(ok2, target_ref)
						if not ok2 or not target_ref or vim.trim(target_ref) == "" then
							return
						end
						target_ref = vim.trim(target_ref)
						M.start_between_branches(base_ref, target_ref, cwd)
					end,
				})
			end,
		})
		return
	end

	local custom_label = "✏️ [Type Custom Branch / Ref...]"
	local lines = {}
	for _, b in ipairs(branch_names) do
		local marker = (b == current_branch) and " (current)" or ""
		table.insert(lines, string.format(" 🌿 %-24s%s", b, marker))
	end
	table.insert(lines, " " .. custom_label)

	local total_w = math.floor(vim.o.columns * 0.85)
	local menu_w = math.floor((total_w - 4) / 2)
	local menu_h = math.min(18, math.max(8, #lines + 3))
	local start_row = math.floor((vim.o.lines - menu_h) / 2)
	local start_col = math.floor((vim.o.columns - total_w) / 2)

	local b_z = z_index.next_zindex("git_diff_branch_select", { parent = "git_center", offset = 35 })

	-- Left Menu: Base Branch
	local left_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[left_buf].buftype = "nofile"
	vim.bo[left_buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, lines)

	local left_win = vim.api.nvim_open_win(left_buf, true, {
		relative = "editor",
		width = menu_w,
		height = menu_h,
		row = start_row,
		col = start_col,
		style = "minimal",
		border = "rounded",
		zindex = b_z,
		title = " 🌿 1. Select Base Branch (Left) | [Enter/Tab/l]: Next ",
		title_pos = "center",
	})
	vim.api.nvim_set_option_value("cursorline", true, { win = left_win })

	-- Right Menu: Target Branch
	local right_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[right_buf].buftype = "nofile"
	vim.bo[right_buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, lines)

	local right_win = vim.api.nvim_open_win(right_buf, false, {
		relative = "editor",
		width = menu_w,
		height = menu_h,
		row = start_row,
		col = start_col + menu_w + 2,
		style = "minimal",
		border = "rounded",
		zindex = b_z,
		title = " 🌿 2. Select Target Branch (Right) | [Enter]: Compare ",
		title_pos = "center",
	})
	vim.api.nvim_set_option_value("cursorline", true, { win = right_win })
	z_index.register(
		"git_diff_branch_select",
		{ left_win, right_win },
		{ parent = "git_center", offset = 35, zindex = b_z }
	)

	local selected_base = branch_names[1]
	local selected_target = branch_names[2] or branch_names[1]

	local is_closed = false
	local function close_menus()
		if is_closed then
			return
		end
		is_closed = true
		ui.close(left_win)
		ui.close(right_win)
	end

	local function confirm_and_launch()
		close_menus()
		if selected_base and selected_target then
			M.start_between_branches(selected_base, selected_target, cwd)
		end
	end

	local function select_base_and_proceed()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		if row > #branch_names then
			input_modal.open({
				label = "Type Custom Base Branch / Ref (Left side):",
				default_value = current_branch or "HEAD",
				relative = "editor",
				callback = function(ok, val)
					if ok and val and vim.trim(val) ~= "" then
						selected_base = vim.trim(val)
						pcall(vim.api.nvim_set_current_win, right_win)
					end
				end,
			})
		else
			selected_base = branch_names[row]
			pcall(vim.api.nvim_set_current_win, right_win)
		end
	end

	local function select_target_and_launch()
		local row = vim.api.nvim_win_get_cursor(right_win)[1]
		if row > #branch_names then
			local def_val = "origin/" .. (selected_base or current_branch or "HEAD")
			input_modal.open({
				label = "Type Custom Target Branch / Ref (Right side):",
				default_value = def_val,
				relative = "editor",
				callback = function(ok, val)
					if ok and val and vim.trim(val) ~= "" then
						selected_target = vim.trim(val)
						confirm_and_launch()
					end
				end,
			})
		else
			selected_target = branch_names[row]
			confirm_and_launch()
		end
	end

	local l_opts = { buffer = left_buf, noremap = true, silent = true, nowait = true }
	local r_opts = { buffer = right_buf, noremap = true, silent = true, nowait = true }

	vim.keymap.set("n", "<CR>", select_base_and_proceed, l_opts)
	vim.keymap.set("n", "<Tab>", select_base_and_proceed, l_opts)
	vim.keymap.set("n", "l", function()
		pcall(vim.api.nvim_set_current_win, right_win)
	end, l_opts)
	vim.keymap.set("n", "<Right>", function()
		pcall(vim.api.nvim_set_current_win, right_win)
	end, l_opts)

	vim.keymap.set("n", "<CR>", select_target_and_launch, r_opts)
	vim.keymap.set("n", "h", function()
		pcall(vim.api.nvim_set_current_win, left_win)
	end, r_opts)
	vim.keymap.set("n", "<Left>", function()
		pcall(vim.api.nvim_set_current_win, left_win)
	end, r_opts)

	for _, k in ipairs({ "q", "<Esc>", "<C-c>" }) do
		vim.keymap.set("n", k, close_menus, l_opts)
		vim.keymap.set("n", k, close_menus, r_opts)
	end
end

--- Opens a commit picker to select two specific commits to compare
--- @param cwd string|nil
function M.open_two_commits_picker(cwd)
	cwd = cwd or path_util.normalize(project.root() or vim.fn.getcwd())
	local queries = require("plugins.krs.git.git_center.queries")
	local raw_commits = queries.get_all_commit_graph(cwd, 60)
	if #raw_commits == 0 then
		notify("No commit history found", vim.log.levels.WARN)
		return
	end

	local commits = {}
	local items = {}
	for _, raw_line in ipairs(raw_commits) do
		local clean = raw_line:gsub("\27%[[0-9;]*m", "")
		local hash = clean:match("(%x%x%x%x%x%x%x+)")
		if hash then
			table.insert(commits, hash)
			table.insert(items, clean)
		end
	end

	vim.ui.select(items, { prompt = "Select Base Commit (Older):" }, function(choice1, idx1)
		if not choice1 or not idx1 then
			return
		end
		local commit1 = commits[idx1]
		vim.ui.select(items, { prompt = "Select Target Commit (Newer / HEAD):" }, function(choice2, idx2)
			if not choice2 or not idx2 then
				return
			end
			local commit2 = commits[idx2]
			M.start_same_branch({ base_ref = commit1, target_ref = commit2, cwd = cwd })
		end)
	end)
end

--- Opens configuration dialog for diff scope / commits behind
function M.open_config_dialog()
	local input_modal = require("plugins.krs.ui.input_modal")
	local choices = {
		"1. 🟢 Working Tree vs HEAD (Staged & Unstaged changes) [Default]",
		string.format(
			"2. 📦 Working Tree + Last N Commits (HEAD~N vs Working Tree) [Current N: %d]",
			math.max(1, M.state.commits_behind)
		),
		string.format(
			"3. 🔒 Committed History Only (HEAD~N vs HEAD) [Current N: %d]",
			math.max(1, M.state.commits_behind)
		),
		"4. 📜 Compare 2 Specific Commits (Commit Graph)",
	}

	vim.ui.select(choices, { prompt = "⚡ Select Diff Scope / Range:" }, function(choice, idx)
		if not choice or not idx then
			return
		end

		if idx == 1 then
			M.state.commits_behind = 0
			M.state.include_worktree = true
			M.state.base_ref = "HEAD"
			M.state.target_ref = "WORKTREE"
			M.state.custom_commits = false
			notify("Diff scope: Working Tree (Staged & Unstaged) vs HEAD")
			if M.state.is_active and M.state.mode == "same_branch" then
				M.start_same_branch({ commits_behind = 0, include_worktree = true, cwd = M.state.cwd })
			end
		elseif idx == 2 then
			input_modal.open({
				label = "Quantity of commits behind (N >= 1, includes working tree changes):",
				default_value = tostring(math.max(1, M.state.commits_behind)),
				relative = "editor",
				callback = function(ok, val)
					if ok and val then
						local n = math.max(1, M.sanitize_commits_behind(val))
						M.state.commits_behind = n
						M.state.include_worktree = true
						notify(string.format("Diff scope: Working Tree + last %d commit(s)", n))
						if M.state.is_active and M.state.mode == "same_branch" then
							M.start_same_branch({ commits_behind = n, include_worktree = true, cwd = M.state.cwd })
						end
					end
				end,
			})
		elseif idx == 3 then
			input_modal.open({
				label = "Quantity of commits behind (N >= 1, committed changes only):",
				default_value = tostring(math.max(1, M.state.commits_behind)),
				relative = "editor",
				callback = function(ok, val)
					if ok and val then
						local n = math.max(1, M.sanitize_commits_behind(val))
						M.state.commits_behind = n
						M.state.include_worktree = false
						notify(string.format("Diff scope: Committed history only (HEAD~%d vs HEAD)", n))
						if M.state.is_active and M.state.mode == "same_branch" then
							M.start_same_branch({ commits_behind = n, include_worktree = false, cwd = M.state.cwd })
						end
					end
				end,
			})
		elseif idx == 4 then
			M.open_two_commits_picker(M.state.cwd)
		end
	end)
end

--- Opens the main Git Diff Mode interactive launcher menu
function M.open()
	local status_label = (M.state.is_active and M.state.mode == "same_branch") and "ACTIVE" or "Toggle"
	local same_branch_title
	if M.state.target_ref == "WORKTREE" then
		if M.state.commits_behind > 0 then
			same_branch_title =
				string.format("1. 🔍 Same Branch Diff (Worktree + HEAD~%d) [%s]", M.state.commits_behind, status_label)
		else
			same_branch_title = string.format("1. 🔍 Same Branch Diff (Worktree vs HEAD) [%s]", status_label)
		end
	else
		same_branch_title =
			string.format("1. 🔍 Same Branch Diff (HEAD vs HEAD~%d) [%s]", M.state.commits_behind, status_label)
	end

	local choices = {
		same_branch_title,
		"2. 🌿 Between 2 Branches Diff (Side-by-Side Dual Menus)",
		"3. ⚙️ Configure Diff Scope / Range (Working Tree vs Commits)",
		"4. 📜 Select 2 Commits to Compare",
		"5. ❌ Close / Exit Git Diff Mode",
	}

	vim.ui.select(choices, { prompt = "⚡ Git Diff Mode Manager:" }, function(choice, idx)
		if not choice or not idx then
			return
		end
		if idx == 1 then
			if M.state.is_active and M.state.mode == "same_branch" then
				M.close()
				notify("Git Diff Mode closed")
			else
				M.start_same_branch()
			end
		elseif idx == 2 then
			M.open_branch_selector_modal()
		elseif idx == 3 then
			M.open_config_dialog()
		elseif idx == 4 then
			M.open_two_commits_picker()
		elseif idx == 5 then
			M.close()
			notify("Git Diff Mode closed")
		end
	end)
end

--- Toggles Git Diff Mode on/off
function M.toggle()
	if M.is_open() then
		M.close()
		notify("Git Diff Mode disabled")
	else
		M.start_same_branch()
	end
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	diff.setup_highlights()

	pcall(vim.api.nvim_create_user_command, "GitDiffMode", function()
		M.open()
	end, { desc = "Open Git Diff Mode Manager" })

	pcall(vim.api.nvim_create_user_command, "GitDiffSameBranch", function()
		M.start_same_branch()
	end, { desc = "Start Git Diff Mode (Same branch)" })

	pcall(vim.api.nvim_create_user_command, "GitDiffBetweenBranches", function()
		M.open_branch_selector_modal()
	end, { desc = "Start Git Diff Mode between 2 branches" })

	pcall(vim.api.nvim_create_user_command, "GitDiffToggle", function()
		M.toggle()
	end, { desc = "Toggle Git Diff Mode" })

	pcall(vim.api.nvim_create_user_command, "GitDiffClose", function()
		M.close()
	end, { desc = "Close Git Diff Mode" })
end

return setmetatable({
	name = "krs_git_diff_mode",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = {
		"GitDiffMode",
		"GitDiffSameBranch",
		"GitDiffBetweenBranches",
		"GitDiffToggle",
		"GitDiffClose",
	},
	config = function()
		M.setup()
	end,
}, { __index = M })
