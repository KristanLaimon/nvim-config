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

	-- Diff statistics
	stats = nil,
	current_mod_idx = 0,
	change_counts = nil,
}

local EMPTY_TREE_SHA = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

local render_file_list = nil

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
		pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
		pcall(vim.api.nvim_buf_clear_namespace, bufnr, diff.namespace, 0, -1)
		pcall(vim.api.nvim_buf_clear_namespace, bufnr, diff.ts_namespace, 0, -1)
	end
end

--- Clears diff highlights and extmarks from all buffers in Neovim
function M.clear_all_diff_highlights()
	for b, _ in pairs(M.state.highlighted_bufs or {}) do
		if vim.api.nvim_buf_is_valid(b) then
			pcall(vim.api.nvim_buf_clear_namespace, b, M.namespace, 0, -1)
			pcall(vim.api.nvim_buf_clear_namespace, b, diff.namespace, 0, -1)
			pcall(vim.api.nvim_buf_clear_namespace, b, diff.ts_namespace, 0, -1)
		end
	end
	M.state.highlighted_bufs = {}

	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) then
			pcall(vim.api.nvim_buf_clear_namespace, b, M.namespace, 0, -1)
			pcall(vim.api.nvim_buf_clear_namespace, b, diff.namespace, 0, -1)
			pcall(vim.api.nvim_buf_clear_namespace, b, diff.ts_namespace, 0, -1)
		end
	end
	M.state.current_modifications = {}
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
	M.state.highlighted_bufs = M.state.highlighted_bufs or {}
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		M.state.highlighted_bufs[bufnr] = true
	end
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

--- Moves cursor to next modification in active file
--- @param target_win? integer Window to move cursor in (defaults to editor window if in sidebar, else current window)
function M.jump_next_modification(target_win)
	local mods = M.state.current_modifications
	if not mods or #mods == 0 then
		return
	end

	local win = target_win
	if not (win and vim.api.nvim_win_is_valid(win)) then
		local cur_win = vim.api.nvim_get_current_win()
		if cur_win == M.state.file_list_win then
			if
				M.state.mode == "between_branches"
				and M.state.dual_right_win
				and vim.api.nvim_win_is_valid(M.state.dual_right_win)
			then
				win = M.state.dual_right_win
			else
				win = get_valid_editor_win()
			end
		else
			win = cur_win
		end
	end

	if not (win and vim.api.nvim_win_is_valid(win)) then
		return
	end

	local cur_row = vim.api.nvim_win_get_cursor(win)[1]
	local target_row = nil
	local idx = nil
	for i, row in ipairs(mods) do
		if row > cur_row then
			target_row = row
			idx = i
			break
		end
	end

	if not target_row then
		target_row = mods[1]
		idx = 1
	end

	pcall(vim.api.nvim_win_set_cursor, win, { target_row, 0 })
	vim.api.nvim_win_call(win, function()
		pcall(vim.cmd, "normal! zz")
	end)

	if
		M.state.mode == "between_branches"
		and M.state.dual_left_win
		and vim.api.nvim_win_is_valid(M.state.dual_left_win)
	then
		pcall(vim.api.nvim_win_set_cursor, M.state.dual_left_win, { target_row, 0 })
		vim.api.nvim_win_call(M.state.dual_left_win, function()
			pcall(vim.cmd, "normal! zz")
		end)
	end

	M.state.current_mod_idx = idx

	-- Re-render sidebar to update change counter without stealing focus or moving cursor
	if render_file_list and M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		local cur_pos = vim.api.nvim_win_get_cursor(M.state.file_list_win)
		render_file_list()
		if vim.api.nvim_win_is_valid(M.state.file_list_win) then
			pcall(vim.api.nvim_win_set_cursor, M.state.file_list_win, cur_pos)
		end
	end
end

--- Moves cursor to previous modification in active file
--- @param target_win? integer Window to move cursor in (defaults to editor window if in sidebar, else current window)
function M.jump_prev_modification(target_win)
	local mods = M.state.current_modifications
	if not mods or #mods == 0 then
		return
	end

	local win = target_win
	if not (win and vim.api.nvim_win_is_valid(win)) then
		local cur_win = vim.api.nvim_get_current_win()
		if cur_win == M.state.file_list_win then
			if
				M.state.mode == "between_branches"
				and M.state.dual_right_win
				and vim.api.nvim_win_is_valid(M.state.dual_right_win)
			then
				win = M.state.dual_right_win
			else
				win = get_valid_editor_win()
			end
		else
			win = cur_win
		end
	end

	if not (win and vim.api.nvim_win_is_valid(win)) then
		return
	end

	local cur_row = vim.api.nvim_win_get_cursor(win)[1]
	local target_row = nil
	local idx = nil
	for i = #mods, 1, -1 do
		local row = mods[i]
		if row < cur_row then
			target_row = row
			idx = i
			break
		end
	end

	if not target_row then
		target_row = mods[#mods]
		idx = #mods
	end

	pcall(vim.api.nvim_win_set_cursor, win, { target_row, 0 })
	vim.api.nvim_win_call(win, function()
		pcall(vim.cmd, "normal! zz")
	end)

	if
		M.state.mode == "between_branches"
		and M.state.dual_left_win
		and vim.api.nvim_win_is_valid(M.state.dual_left_win)
	then
		pcall(vim.api.nvim_win_set_cursor, M.state.dual_left_win, { target_row, 0 })
		vim.api.nvim_win_call(M.state.dual_left_win, function()
			pcall(vim.cmd, "normal! zz")
		end)
	end

	M.state.current_mod_idx = idx

	-- Re-render sidebar to update change counter without stealing focus or moving cursor
	if render_file_list and M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		local cur_pos = vim.api.nvim_win_get_cursor(M.state.file_list_win)
		render_file_list()
		if vim.api.nvim_win_is_valid(M.state.file_list_win) then
			pcall(vim.api.nvim_win_set_cursor, M.state.file_list_win, cur_pos)
		end
	end
end

--- Computes line additions and deletions across all changed files and per-file
--- @param base_ref string
--- @param target_ref string
--- @param cwd string
--- @param files? table[]
--- @return { total_add: integer, total_del: integer, per_file: table<string, { add: integer, del: integer, is_binary?: boolean }> }
function M.compute_diff_stats(base_ref, target_ref, cwd, files)
	cwd = cwd or M.state.cwd or vim.fn.getcwd()
	base_ref = base_ref or M.state.base_ref or "HEAD"
	target_ref = target_ref or M.state.target_ref or "WORKTREE"
	local per_file = {}
	local total_add = 0
	local total_del = 0

	local diff_args
	if target_ref == "WORKTREE" then
		diff_args = { "diff", "--numstat", "--no-ext-diff", base_ref }
	else
		diff_args = { "diff", "--numstat", "--no-ext-diff", base_ref, target_ref }
	end

	local raw_lines = git.lines(diff_args, cwd)
	for _, line in ipairs(raw_lines) do
		local plus, minus, path = line:match("^(%d+)%s+(%d+)%s+(.+)$")
		if plus and minus and path then
			local add = tonumber(plus) or 0
			local del = tonumber(minus) or 0
			local clean_path = path
			if path:find("=>") then
				local pre, mid_new, post = path:match("(.-){.-%=>%s*(.-)}(.*)")
				if pre and mid_new and post then
					clean_path = pre .. mid_new .. post
				else
					clean_path = path:match("%=>%s*(.+)$") or path
				end
			end
			clean_path = vim.trim(clean_path):gsub('^"', ""):gsub('"$', "")
			clean_path = path_util.normalize(clean_path)
			per_file[clean_path] = { add = add, del = del }
			total_add = total_add + add
			total_del = total_del + del
		else
			local bin_path = line:match("^%-%s+%-%s+(.+)$")
			if bin_path then
				local clean_path = vim.trim(bin_path):gsub('^"', ""):gsub('"$', "")
				clean_path = path_util.normalize(clean_path)
				per_file[clean_path] = { add = 0, del = 0, is_binary = true }
			end
		end
	end

	-- Account for untracked files when target is WORKTREE
	if target_ref == "WORKTREE" and files then
		for _, item in ipairs(files) do
			local norm_file = path_util.normalize(item.file)
			if item.status == "?" and not per_file[norm_file] then
				local full = path_util.join(cwd, item.file)
				local count = 0
				local ok, f_lines = pcall(vim.fn.readfile, full)
				if ok and type(f_lines) == "table" then
					count = #f_lines
				end
				per_file[norm_file] = { add = count, del = 0 }
				total_add = total_add + count
			end
		end
	end

	return {
		total_add = total_add,
		total_del = total_del,
		per_file = per_file,
	}
end

--- Retrieves diff stats for a given file
--- @param stats table
--- @param file_path string|nil
--- @param cwd? string
--- @return { add: integer, del: integer, is_binary?: boolean }
function M.get_file_stat(stats, file_path, cwd)
	if not (stats and stats.per_file and file_path) then
		return { add = 0, del = 0 }
	end
	if stats.per_file[file_path] then
		return stats.per_file[file_path]
	end
	local norm = path_util.normalize(file_path)
	if stats.per_file[norm] then
		return stats.per_file[norm]
	end
	if cwd then
		local rel = path_util.relative_to(file_path, cwd)
		if rel and stats.per_file[rel] then
			return stats.per_file[rel]
		end
	end
	return { add = 0, del = 0 }
end

--- Returns cached diff stats or computes them
--- @param force? boolean
--- @return { total_add: integer, total_del: integer, per_file: table }
function M.get_or_compute_stats(force)
	if not force and M.state.stats then
		return M.state.stats
	end
	local cwd = M.state.cwd or vim.fn.getcwd()
	local base_ref = M.state.base_ref or "HEAD"
	local target_ref = M.state.target_ref or "WORKTREE"
	local stats = M.compute_diff_stats(base_ref, target_ref, cwd, M.state.files)
	M.state.stats = stats
	return stats
end

--- Computes total change modifications and per-file change counts across diff hunks
--- @param base_ref string
--- @param target_ref string
--- @param cwd string
--- @param files? table[]
--- @return { total: integer, per_file: table<string, integer> }
function M.compute_change_counts(base_ref, target_ref, cwd, files)
	cwd = cwd or M.state.cwd or vim.fn.getcwd()
	base_ref = base_ref or M.state.base_ref or "HEAD"
	target_ref = target_ref or M.state.target_ref or "WORKTREE"
	local per_file = {}
	local total = 0

	local diff_args
	if target_ref == "WORKTREE" then
		diff_args = { "diff", "-U0", "--no-ext-diff", base_ref }
	else
		diff_args = { "diff", "-U0", "--no-ext-diff", base_ref, target_ref }
	end

	local raw_lines = git.lines(diff_args, cwd)
	local cur_file = nil
	for _, line in ipairs(raw_lines) do
		local raw_path = line:match("^diff %-%-git%s+.-%s+[%w]%/(.+)$")
		if not raw_path then
			raw_path = line:match('^diff %-%-git%s+.-%s+"[^"/]+%/(.+)"$')
		end
		if raw_path then
			cur_file = path_util.normalize(vim.trim(raw_path):gsub('^"', ""):gsub('"$', ""))
			if not per_file[cur_file] then
				per_file[cur_file] = 0
			end
		elseif cur_file and line:match("^@@ %-%d+") then
			per_file[cur_file] = (per_file[cur_file] or 0) + 1
			total = total + 1
		end
	end

	-- Account for untracked files when target is WORKTREE
	if target_ref == "WORKTREE" and files then
		for _, item in ipairs(files) do
			local norm_file = path_util.normalize(item.file)
			if item.status == "?" and not per_file[norm_file] then
				per_file[norm_file] = 1
				total = total + 1
			end
		end
	end

	if files then
		for _, item in ipairs(files) do
			local norm_file = path_util.normalize(item.file)
			if not per_file[norm_file] then
				per_file[norm_file] = 0
			end
		end
	end

	return {
		total = total,
		per_file = per_file,
	}
end

--- Returns cached change counts or computes them
--- @param force? boolean
--- @return { total: integer, per_file: table<string, integer> }
function M.get_or_compute_change_counts(force)
	if not force and M.state.change_counts then
		return M.state.change_counts
	end
	local cwd = M.state.cwd or vim.fn.getcwd()
	local base_ref = M.state.base_ref or "HEAD"
	local target_ref = M.state.target_ref or "WORKTREE"
	local counts = M.compute_change_counts(base_ref, target_ref, cwd, M.state.files)
	M.state.change_counts = counts
	return counts
end

--- Renders contents of right sidebar changed files list window
render_file_list = function()
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

	-- Diff bar at bottom side: separator, stats, and shortcuts
	table.insert(lines, string.rep("─", 36))

	local stats = M.get_or_compute_stats()
	local cur_file = M.state.active_file
	if not cur_file and #M.state.files > 0 then
		local sel_item = M.state.files[M.state.selected_file_idx]
		cur_file = sel_item and sel_item.file
	end
	local cur_stat = M.get_file_stat(stats, cur_file, M.state.cwd)

	local cur_display = "none"
	if cur_file then
		cur_display = path_util.filename(cur_file)
		if #cur_display > 14 then
			cur_display = cur_display:sub(1, 11) .. "..."
		end
	end

	local total_stat_line = #lines + 1
	table.insert(lines, string.format(" 󰊢 Total:    +%d  -%d", stats.total_add or 0, stats.total_del or 0))
	local subtotal_stat_line = #lines + 1
	table.insert(lines, string.format(" 󰈔 Subtotal: +%d  -%d (%s)", cur_stat.add or 0, cur_stat.del or 0, cur_display))

	local change_counts = M.get_or_compute_change_counts()
	local file_changes = 0
	if cur_file and M.state.active_file and cur_file == M.state.active_file and #M.state.current_modifications > 0 then
		file_changes = #M.state.current_modifications
	elseif cur_file then
		local norm_cur = path_util.normalize(cur_file)
		file_changes = change_counts.per_file[norm_cur] or change_counts.per_file[cur_file] or 0
	end

	local cur_mod_idx = 0
	if file_changes > 0 then
		if M.state.current_mod_idx and M.state.current_mod_idx > 0 then
			cur_mod_idx = math.min(M.state.current_mod_idx, file_changes)
		else
			cur_mod_idx = 1
		end
	end

	local total_changes = 0
	local cur_total_idx = 0
	local offset = 0
	local active_norm = cur_file and path_util.normalize(cur_file)

	for _, item in ipairs(M.state.files) do
		local norm = path_util.normalize(item.file)
		local count
		if cur_file and norm == active_norm and file_changes > 0 then
			count = file_changes
		else
			count = change_counts.per_file[norm] or change_counts.per_file[item.file] or 0
		end
		if cur_file and norm == active_norm then
			if cur_mod_idx > 0 then
				cur_total_idx = offset + cur_mod_idx
			end
		elseif cur_total_idx == 0 then
			offset = offset + count
		end
		total_changes = total_changes + count
	end

	if total_changes == 0 and change_counts.total > 0 then
		total_changes = change_counts.total
	end
	if cur_total_idx == 0 and cur_mod_idx > 0 then
		cur_total_idx = cur_mod_idx
	end

	local file_change_line = #lines + 1
	table.insert(lines, string.format(" <%d/%d Changes in file>", cur_mod_idx, file_changes))
	local total_change_line = #lines + 1
	table.insert(lines, string.format(" <%d/%d Changes in total>", cur_total_idx, total_changes))

	table.insert(lines, string.rep("─", 36))
	table.insert(lines, " [J/K / ]c/[c]: Jump Diff")
	table.insert(lines, " [Enter/Space]: Select | [h/Esc]: Code")
	table.insert(lines, " [c]: Range | [e]: Export | [i]: Import")
	table.insert(lines, " [q]: Close")

	vim.bo[M.state.file_list_buf].modifiable = true
	vim.api.nvim_buf_set_lines(M.state.file_list_buf, 0, -1, false, lines)
	vim.bo[M.state.file_list_buf].modifiable = false

	-- Apply highlights
	vim.api.nvim_buf_clear_namespace(M.state.file_list_buf, M.files_namespace, 0, -1)

	-- Highlights for files
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

	-- Highlights for bottom diff bar stats
	pcall(
		vim.api.nvim_buf_add_highlight,
		M.state.file_list_buf,
		M.files_namespace,
		"GitCenterDiffHeader",
		total_stat_line - 1,
		1,
		11
	)
	pcall(
		vim.api.nvim_buf_add_highlight,
		M.state.file_list_buf,
		M.files_namespace,
		"GitCenterDiffHeader",
		subtotal_stat_line - 1,
		1,
		14
	)

	local total_line_str = lines[total_stat_line] or ""
	local total_plus_col = total_line_str:find("%+")
	local total_minus_col = total_line_str:find("%-")
	if total_plus_col and total_minus_col then
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffAddPrefix",
			total_stat_line - 1,
			total_plus_col - 1,
			total_minus_col - 1
		)
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffDeletePrefix",
			total_stat_line - 1,
			total_minus_col - 1,
			-1
		)
	end

	local sub_line_str = lines[subtotal_stat_line] or ""
	local sub_plus_col = sub_line_str:find("%+")
	local sub_minus_col = sub_line_str:find("%-")
	local sub_paren_col = sub_line_str:find("%(")
	if sub_plus_col and sub_minus_col then
		local end_col = sub_paren_col and (sub_paren_col - 1) or -1
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffAddPrefix",
			subtotal_stat_line - 1,
			sub_plus_col - 1,
			sub_minus_col - 1
		)
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffDeletePrefix",
			subtotal_stat_line - 1,
			sub_minus_col - 1,
			end_col
		)
	end
	if sub_paren_col then
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffContext",
			subtotal_stat_line - 1,
			sub_paren_col - 1,
			-1
		)
	end

	-- Highlights for change messages
	pcall(
		vim.api.nvim_buf_add_highlight,
		M.state.file_list_buf,
		M.files_namespace,
		"GitCenterDiffContext",
		file_change_line - 1,
		0,
		-1
	)
	pcall(
		vim.api.nvim_buf_add_highlight,
		M.state.file_list_buf,
		M.files_namespace,
		"GitCenterDiffContext",
		total_change_line - 1,
		0,
		-1
	)

	local file_line_str = lines[file_change_line] or ""
	local fl_lt = file_line_str:find("<")
	local fl_gt = file_line_str:find(">")
	if fl_lt and fl_gt then
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffHeader",
			file_change_line - 1,
			fl_lt - 1,
			fl_gt
		)
	end

	local tot_line_str = lines[total_change_line] or ""
	local tl_lt = tot_line_str:find("<")
	local tl_gt = tot_line_str:find(">")
	if tl_lt and tl_gt then
		pcall(
			vim.api.nvim_buf_add_highlight,
			M.state.file_list_buf,
			M.files_namespace,
			"GitCenterDiffHeader",
			total_change_line - 1,
			tl_lt - 1,
			tl_gt
		)
	end

	-- Update statusline on window if valid
	if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		local status_str = string.format(
			" Diff 󰊢 Total: +%d -%d │ 󰈔 Subtotal: +%d -%d (%s) │ <%d/%d file> <%d/%d total>",
			stats.total_add or 0,
			stats.total_del or 0,
			cur_stat.add or 0,
			cur_stat.del or 0,
			cur_display,
			cur_mod_idx,
			file_changes,
			cur_total_idx,
			total_changes
		)
		pcall(function()
			vim.wo[M.state.file_list_win].statusline = status_str
		end)
	end
end
M.render_file_list = render_file_list

--- Opens or focuses the docked right sidebar changed files list window
--- @param files? table[]
--- @param selected_idx? integer
--- @return integer win, integer buf
function M.open_file_list_window(files, selected_idx)
	if files and files ~= M.state.files then
		M.state.files = files
		M.state.stats = nil
		M.state.change_counts = nil
		M.state.current_mod_idx = 0
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

	-- Auto-close diff mode cleanly if sidebar window is closed externally (e.g. :q, :close, <C-w>c)
	local win_str = tostring(win)
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = win_str,
		once = true,
		callback = function()
			if M.is_open() then
				M.close()
			end
		end,
	})

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
	local function move_down()
		if #M.state.files == 0 then
			return
		end
		M.state.selected_file_idx = (M.state.selected_file_idx % #M.state.files) + 1
		render_file_list()
		pcall(vim.api.nvim_win_set_cursor, win, { 2 + M.state.selected_file_idx, 0 })
	end

	local function move_up()
		if #M.state.files == 0 then
			return
		end
		M.state.selected_file_idx = M.state.selected_file_idx - 1
		if M.state.selected_file_idx < 1 then
			M.state.selected_file_idx = #M.state.files
		end
		render_file_list()
		pcall(vim.api.nvim_win_set_cursor, win, { 2 + M.state.selected_file_idx, 0 })
	end

	vim.keymap.set("n", "j", move_down, opts)
	vim.keymap.set("n", "<Down>", move_down, opts)
	vim.keymap.set("n", "k", move_up, opts)
	vim.keymap.set("n", "<Up>", move_up, opts)

	local function open_selected()
		local file_entry = M.state.files[M.state.selected_file_idx]
		if not file_entry then
			return
		end
		if M.state.mode == "same_branch" then
			M.open_file_same_branch(file_entry.file, { keep_focus = true })
		else
			M.open_file_between_branches(file_entry.file, { keep_focus = true })
		end
		if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
			pcall(vim.api.nvim_set_current_win, M.state.file_list_win)
			pcall(vim.api.nvim_win_set_cursor, M.state.file_list_win, { 2 + M.state.selected_file_idx, 0 })
		end
		render_file_list()
	end

	vim.keymap.set("n", "<CR>", open_selected, opts)
	vim.keymap.set("n", "<Space>", open_selected, opts)

	-- Mouse click to select file without leaving sidebar
	vim.keymap.set("n", "<LeftMouse>", function()
		local mousepos = vim.fn.getmousepos()
		if mousepos.winid == win then
			local row = mousepos.line
			local idx = row - 2
			if idx >= 1 and idx <= #M.state.files then
				M.state.selected_file_idx = idx
				open_selected()
				pcall(vim.api.nvim_win_set_cursor, win, { 2 + M.state.selected_file_idx, 0 })
				return
			end
		end
		pcall(vim.cmd, "normal! <LeftMouse>")
	end, opts)

	-- Shortcuts (only available in this git diff sidebar) to move between changes in same file
	for _, k in ipairs({ "J", "n", "]c", "]d", "]" }) do
		vim.keymap.set("n", k, function()
			M.jump_next_modification()
		end, opts)
	end

	for _, k in ipairs({ "K", "p", "N", "[c", "[d", "[" }) do
		vim.keymap.set("n", k, function()
			M.jump_prev_modification()
		end, opts)
	end

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

	for _, k in ipairs({ "e", "E", "z" }) do
		vim.keymap.set("n", k, function()
			M.export_diff_prompt()
		end, opts)
	end

	for _, k in ipairs({ "i", "I" }) do
		vim.keymap.set("n", k, function()
			M.import_diff_prompt()
		end, opts)
	end

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
--- @param opts? { keep_focus?: boolean }
function M.open_file_same_branch(file_path, opts)
	opts = opts or {}
	M.state.active_file = file_path
	local full_path = path_util.join(M.state.cwd, file_path)

	local origin_win = vim.api.nvim_get_current_win()
	local stay_in_sidebar = opts.keep_focus or (origin_win == M.state.file_list_win)

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
		M.state.current_mod_idx = 1
	else
		M.state.current_mod_idx = 0
	end

	if stay_in_sidebar and M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		pcall(vim.api.nvim_set_current_win, M.state.file_list_win)
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

	-- Live diff highlights refresh on file save
	if M._augroup then
		pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
	end
	M._augroup = vim.api.nvim_create_augroup("krs_git_diff_mode_active", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = M._augroup,
		callback = function(args)
			if M.is_open() and M.state.mode == "same_branch" and M.state.cwd then
				local b = args.buf
				if b and vim.api.nvim_buf_is_valid(b) then
					local bname = vim.api.nvim_buf_get_name(b)
					local rel = path_util.relative_to(bname, M.state.cwd)
					if rel and rel ~= "" and M.state.files then
						for _, item in ipairs(M.state.files) do
							if item.file == rel then
								M.apply_same_branch_highlights(b, rel, M.state.base_ref, M.state.target_ref, M.state.cwd)
								if render_file_list then
									render_file_list()
								end
								break
							end
						end
					end
				end
			end
		end,
	})

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
--- @param opts? { keep_focus?: boolean }
function M.open_file_between_branches(file_path, opts)
	opts = opts or {}
	M.state.active_file = file_path
	local origin_win = vim.api.nvim_get_current_win()
	local stay_in_sidebar = opts.keep_focus or (origin_win == M.state.file_list_win)
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
	M.state.current_mod_idx = #mods > 0 and 1 or 0

	if not stay_in_sidebar then
		M.focus_editor()
	else
		if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
			pcall(vim.api.nvim_set_current_win, M.state.file_list_win)
		end
	end
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
		M.state.stats = nil
		M.state.change_counts = nil
		M.state.current_mod_idx = 0
		M.state.active_file = nil
		M.state.current_modifications = {}
	end

	-- Delete live diff autocmd group
	if M._augroup then
		pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
		M._augroup = nil
	end

	-- Clear diff highlights & extmarks from ALL open buffers in Neovim
	M.clear_all_diff_highlights()

	-- Close file list window
	if M.state.file_list_win and vim.api.nvim_win_is_valid(M.state.file_list_win) then
		local sb_win = M.state.file_list_win
		M.state.file_list_win = nil
		ui.close(sb_win)
	end
	if M.state.file_list_buf and vim.api.nvim_buf_is_valid(M.state.file_list_buf) then
		pcall(vim.api.nvim_buf_delete, M.state.file_list_buf, { force = true })
	end
	M.state.file_list_win = nil
	M.state.file_list_buf = nil

	-- Restore windows from dual mode
	if M.state.mode == "between_branches" then
		local left_buf_to_wipe = M.state.dual_left_buf
		local right_buf_to_wipe = M.state.dual_right_buf

		if M.state.dual_left_win and vim.api.nvim_win_is_valid(M.state.dual_left_win) then
			pcall(vim.api.nvim_set_option_value, "scrollbind", false, { win = M.state.dual_left_win })
			pcall(vim.api.nvim_set_option_value, "cursorbind", false, { win = M.state.dual_left_win })
			if M.state.prev_buf and vim.api.nvim_buf_is_valid(M.state.prev_buf) then
				pcall(vim.api.nvim_win_set_buf, M.state.dual_left_win, M.state.prev_buf)
			elseif M.state.active_file and M.state.cwd then
				local full_p = path_util.join(M.state.cwd, M.state.active_file)
				if vim.fn.filereadable(full_p) == 1 then
					pcall(vim.api.nvim_win_call, M.state.dual_left_win, function()
						vim.cmd("edit " .. vim.fn.fnameescape(full_p))
					end)
				end
			end
		end
		if M.state.dual_right_win and vim.api.nvim_win_is_valid(M.state.dual_right_win) then
			pcall(vim.api.nvim_set_option_value, "scrollbind", false, { win = M.state.dual_right_win })
			pcall(vim.api.nvim_set_option_value, "cursorbind", false, { win = M.state.dual_right_win })
			ui.close(M.state.dual_right_win)
		end

		if left_buf_to_wipe and vim.api.nvim_buf_is_valid(left_buf_to_wipe) then
			pcall(vim.api.nvim_buf_delete, left_buf_to_wipe, { force = true })
		end
		if right_buf_to_wipe and vim.api.nvim_buf_is_valid(right_buf_to_wipe) then
			pcall(vim.api.nvim_buf_delete, right_buf_to_wipe, { force = true })
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

--- Computes the default filename for exported diff archive based on current commit/branch
--- @param cwd? string
--- @return string default_zip_name
function M.get_default_export_name(cwd)
	cwd = cwd or M.state.cwd or vim.fn.getcwd()
	local commit_slug = git.lines({ "log", "-1", "--format=%f" }, cwd)[1]
	local branch = git.lines({ "branch", "--show-current" }, cwd)[1]

	local default_name = "diff-export.zip"
	if commit_slug and commit_slug ~= "" then
		if branch and branch ~= "" and branch ~= "HEAD" and not commit_slug:lower():find(branch:lower(), 1, true) then
			default_name = branch .. "-" .. commit_slug .. ".zip"
		else
			default_name = commit_slug .. ".zip"
		end
	elseif branch and branch ~= "" and branch ~= "HEAD" then
		default_name = branch .. "-diff.zip"
	end
	return default_name:gsub('[\\/:*?"<>|]', "-")
end

--- Compresses contents of src_dir into zip_dest, preserving relative file paths
--- @param src_dir string Directory containing files to zip
--- @param zip_dest string Absolute path to output zip file
--- @return boolean ok, string|nil err
function M.zip_directory(src_dir, zip_dest)
	local dest_parent = vim.fs.dirname(zip_dest)
	if dest_parent and dest_parent ~= "" then
		vim.fn.mkdir(dest_parent, "p")
	end

	if vim.fn.filereadable(zip_dest) == 1 then
		vim.fn.delete(zip_dest)
	end

	-- 1. Try python3 or python (supports relative directory structure cleanly)
	local py_bin = (vim.fn.executable("python3") == 1 and "python3") or (vim.fn.executable("python") == 1 and "python")
	if py_bin then
		local py_script = "import os, sys, zipfile; src_dir, out_zip = sys.argv[1], sys.argv[2]; "
			.. "zf = zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED); "
			.. "[zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), src_dir)) "
			.. " for r, _, fs in os.walk(src_dir) for f in fs]; "
			.. "zf.close()"
		local res = vim.system({ py_bin, "-c", py_script, src_dir, zip_dest }):wait()
		if res and res.code == 0 and vim.fn.filereadable(zip_dest) == 1 then
			return true
		end
	end

	-- 2. Try zip command line utility
	if vim.fn.executable("zip") == 1 then
		local res = vim.system({ "zip", "-q", "-r", zip_dest, "." }, { cwd = src_dir }):wait()
		if res and res.code == 0 and vim.fn.filereadable(zip_dest) == 1 then
			return true
		end
	end

	-- 3. Try PowerShell on Windows
	if (vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1) and vim.fn.executable("powershell.exe") == 1 then
		local ps_cmd = string.format(
			"Compress-Archive -Path '%s\\*' -DestinationPath '%s' -Force",
			src_dir:gsub("'", "''"),
			zip_dest:gsub("'", "''")
		)
		local res = vim.system({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps_cmd }):wait()
		if res and res.code == 0 and vim.fn.filereadable(zip_dest) == 1 then
			return true
		end
	end

	return false, "No supported zip compression tool found (requires python3, zip, or powershell)"
end

--- Exports diff files with their current code into a zip archive
--- @param zip_name string
--- @param files? table[]
--- @param cwd? string
--- @return string|nil out_path
function M.export_diff_files_to_zip(zip_name, files, cwd)
	cwd = cwd or M.state.cwd or vim.fn.getcwd()
	files = files or M.state.files or {}

	local exportable = {}
	for _, item in ipairs(files) do
		if item.status ~= "D" then
			table.insert(exportable, item)
		end
	end

	if #exportable == 0 then
		notify("No files to export (all changed files are deleted)", vim.log.levels.WARN)
		return nil
	end

	local is_abs = zip_name:sub(1, 1) == "/" or zip_name:match("^%a:[/\\]")
	local out_path = is_abs and path_util.normalize(zip_name) or path_util.join(cwd, zip_name)
	local staging_dir = vim.fn.tempname() .. "_diff_zip"
	vim.fn.mkdir(staging_dir, "p")

	local copied_count = 0
	for _, item in ipairs(exportable) do
		local rel_path = item.file
		local dest_file = path_util.join(staging_dir, rel_path)
		local dest_dir = vim.fs.dirname(dest_file)
		if dest_dir and dest_dir ~= "" then
			vim.fn.mkdir(dest_dir, "p")
		end

		local copied = false
		local disk_src = path_util.join(cwd, rel_path)

		-- If worktree or HEAD, read directly from disk if available
		if M.state.target_ref == "WORKTREE" or M.state.target_ref == "HEAD" or not M.state.target_ref then
			if vim.fn.filereadable(disk_src) == 1 then
				if vim.uv.fs_copyfile(disk_src, dest_file) then
					copied = true
				end
			end
		else
			-- Between branches or custom commit: try git show <target_ref>:<file>
			local res = vim.system({ "git", "-C", cwd, "show", M.state.target_ref .. ":" .. rel_path }):wait()
			if res and res.code == 0 and res.stdout then
				local f = io.open(dest_file, "wb")
				if f then
					f:write(res.stdout)
					f:close()
					copied = true
				end
			end
			-- Fallback to disk if git show fails
			if not copied and vim.fn.filereadable(disk_src) == 1 then
				if vim.uv.fs_copyfile(disk_src, dest_file) then
					copied = true
				end
			end
		end

		if copied then
			copied_count = copied_count + 1

			-- Also export base version if available (for 3-way merge on import)
			if item.status ~= "A" and item.status ~= "?" then
				local base_ref = M.state.base_ref or "HEAD"
				local base_res = vim.system({ "git", "-C", cwd, "show", base_ref .. ":" .. rel_path }):wait()
				if base_res and base_res.code == 0 and base_res.stdout then
					local base_dest = path_util.join(staging_dir, ".krs_diff_base", rel_path)
					local base_dest_dir = vim.fs.dirname(base_dest)
					if base_dest_dir and base_dest_dir ~= "" then
						vim.fn.mkdir(base_dest_dir, "p")
					end
					local bf = io.open(base_dest, "wb")
					if bf then
						bf:write(base_res.stdout)
						bf:close()
					end
				end
			end
		end
	end

	if copied_count == 0 then
		pcall(vim.fn.delete, staging_dir, "rf")
		notify("Could not copy any diff files for export", vim.log.levels.ERROR)
		return nil
	end

	-- Generate manifest signature to verify compatibility on import
	local manifest = {
		generator = "krs_git_diff_mode",
		version = "1.0",
		created_at = os.time(),
		branch = git.lines({ "branch", "--show-current" }, cwd)[1] or "",
		commit = git.lines({ "log", "-1", "--format=%h %s" }, cwd)[1] or "",
		base_ref = M.state.base_ref or "",
		target_ref = M.state.target_ref or "",
		files = {},
	}
	for _, item in ipairs(exportable) do
		table.insert(manifest.files, item.file)
	end

	local manifest_path = path_util.join(staging_dir, ".krs_diff_manifest.json")
	local mf = io.open(manifest_path, "w")
	if mf then
		mf:write(vim.json.encode(manifest))
		mf:close()
	end

	local ok, err = M.zip_directory(staging_dir, out_path)
	pcall(vim.fn.delete, staging_dir, "rf")

	if not ok then
		notify("Error exporting zip archive: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end

	pcall(vim.fn.setreg, "+", out_path)
	pcall(vim.fn.setreg, "*", out_path)

	notify(
		string.format(
			"📦 Exported %d diff file(s) with current code to:\n%s\n(Path copied to clipboard)",
			copied_count,
			out_path
		),
		vim.log.levels.INFO
	)

	return out_path
end

--- Reads and validates the KRS diff manifest from a zip archive
--- Ensures only zips exported by this nvim distribution are compatible
--- @param zip_path string Absolute path to zip file
--- @return table|nil manifest, string|nil error_message
function M.read_zip_manifest(zip_path)
	if not zip_path or zip_path == "" or vim.fn.filereadable(zip_path) == 0 then
		return nil, "Zip file not found or unreadable: " .. tostring(zip_path)
	end

	local content = nil

	-- Method 1: Python 3 or Python
	local py_bin = (vim.fn.executable("python3") == 1 and "python3") or (vim.fn.executable("python") == 1 and "python")
	if py_bin then
		local py_script = "import sys, zipfile; "
			.. "try:\n"
			.. "    zf = zipfile.ZipFile(sys.argv[1], 'r')\n"
			.. "    if '.krs_diff_manifest.json' not in zf.namelist(): sys.exit(2)\n"
			.. "    sys.stdout.write(zf.read('.krs_diff_manifest.json').decode('utf-8'))\n"
			.. "    zf.close()\n"
			.. "except Exception as e:\n"
			.. "    sys.exit(3)\n"
		local res = vim.system({ py_bin, "-c", py_script, zip_path }):wait()
		if res and res.code == 0 and res.stdout and res.stdout ~= "" then
			content = res.stdout
		elseif res and res.code == 2 then
			return nil,
				"Incompatible zip archive: Missing .krs_diff_manifest.json signature (not exported by KRS Git Diff Mode)"
		elseif res and res.code == 3 then
			return nil, "Corrupted or invalid zip file"
		end
	end

	-- Method 2: unzip CLI
	if not content and vim.fn.executable("unzip") == 1 then
		local res = vim.system({ "unzip", "-p", zip_path, ".krs_diff_manifest.json" }):wait()
		if res and res.code == 0 and res.stdout and res.stdout ~= "" then
			content = res.stdout
		end
	end

	-- Method 3: PowerShell on Windows
	if
		not content
		and (vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1)
		and vim.fn.executable("powershell.exe") == 1
	then
		local ps_cmd = string.format(
			"[System.IO.Compression.ZipFile]::OpenRead('%s').GetEntry('.krs_diff_manifest.json')"
				.. " | ForEach-Object { (New-Object System.IO.StreamReader($_.Open())).ReadToEnd() }",
			zip_path:gsub("'", "''")
		)
		local res = vim.system({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps_cmd }):wait()
		if res and res.code == 0 and res.stdout and res.stdout ~= "" then
			content = res.stdout
		end
	end

	if not content or content == "" then
		return nil,
			"Incompatible zip archive: Missing .krs_diff_manifest.json signature (not exported by KRS Git Diff Mode)"
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		return nil, "Malformed .krs_diff_manifest.json inside zip archive"
	end

	if decoded.generator ~= "krs_git_diff_mode" or type(decoded.files) ~= "table" then
		return nil, "Incompatible zip archive: Generator signature mismatch (must be 'krs_git_diff_mode')"
	end

	return decoded, nil
end

--- Extracts and merges diff files from a validated KRS zip archive into target_dir
--- Performs a 3-way merge (via git merge-file) against base version (or target repo HEAD/empty)
--- generating standard conflict markers (<<<<<<< / ======= / >>>>>>>) when conflicts occur.
--- @param zip_path string Path to zip archive
--- @param target_dir? string Target project root (defaults to cwd)
--- @param manifest? table Pre-validated manifest (optional)
--- @return boolean ok, string|nil err, table|nil stats
function M.import_diff_files_from_zip(zip_path, target_dir, manifest)
	target_dir = target_dir or M.state.cwd or vim.fn.getcwd()

	if not manifest then
		local mf, err = M.read_zip_manifest(zip_path)
		if not mf then
			return false, err
		end
		manifest = mf
	end

	if not manifest.files or #manifest.files == 0 then
		return false, "Archive manifest contains no files to import"
	end

	local extract_tmp = vim.fn.tempname() .. "_diff_zip_in"
	vim.fn.mkdir(extract_tmp, "p")

	local ok_extract = false
	local err_msg = nil

	-- Method 1: Python
	local py_bin = (vim.fn.executable("python3") == 1 and "python3") or (vim.fn.executable("python") == 1 and "python")
	if py_bin then
		local py_script = "import sys, zipfile; "
			.. "zip_p, target = sys.argv[1], sys.argv[2]; "
			.. "zf = zipfile.ZipFile(zip_p, 'r'); "
			.. "zf.extractall(target); "
			.. "zf.close()"
		local res = vim.system({ py_bin, "-c", py_script, zip_path, extract_tmp }):wait()
		if res and res.code == 0 then
			ok_extract = true
		else
			err_msg = res and res.stderr or "Extraction failed via python"
		end
	end

	-- Method 2: unzip
	if not ok_extract and vim.fn.executable("unzip") == 1 then
		local cmd = { "unzip", "-q", "-o", zip_path, "-d", extract_tmp }
		local res = vim.system(cmd):wait()
		if res and res.code == 0 then
			ok_extract = true
		else
			err_msg = res and res.stderr or "Extraction failed via unzip"
		end
	end

	-- Method 3: PowerShell
	if
		not ok_extract
		and (vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1)
		and vim.fn.executable("powershell.exe") == 1
	then
		local ps_cmd = string.format(
			"Add-Type -AssemblyName System.IO.Compression.FileSystem; "
				.. "[System.IO.Compression.ZipFile]::ExtractToDirectory('%s', '%s')",
			zip_path:gsub("'", "''"),
			extract_tmp:gsub("'", "''")
		)
		local res = vim.system({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps_cmd }):wait()
		if res and res.code == 0 then
			ok_extract = true
		else
			err_msg = res and res.stderr or "Extraction failed via powershell"
		end
	end

	if not ok_extract then
		pcall(vim.fn.delete, extract_tmp, "rf")
		return false, err_msg or "Failed to extract zip archive"
	end

	local zip_filename = vim.fn.fnamemodify(zip_path, ":t")
	local stats = {
		total = #manifest.files,
		added = 0,
		merged_clean = 0,
		identical = 0,
		conflicted = 0,
		total_conflicts = 0,
		conflicted_files = {},
		binary = 0,
	}

	local touched_files = {}

	for _, rel_path in ipairs(manifest.files) do
		-- Basic safety check against path traversal
		if not rel_path:match("^/") and not rel_path:match("%.%.[/\\]") then
			local incoming_path = path_util.join(extract_tmp, rel_path)
			local dest_path = path_util.join(target_dir, rel_path)
			local base_in_zip = path_util.join(extract_tmp, ".krs_diff_base", rel_path)

			if vim.fn.filereadable(incoming_path) == 1 then
				table.insert(touched_files, dest_path)

				-- Save buffer if open and modified in Neovim before merging
				for _, b in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
						local bname = vim.api.nvim_buf_get_name(b)
						if path_util.equals(bname, dest_path) then
							pcall(vim.api.nvim_buf_call, b, function()
								vim.cmd("noautocmd silent write")
							end)
						end
					end
				end

				if vim.fn.filereadable(dest_path) == 0 then
					-- Case 1: Destination file does not exist -> newly added
					local dest_dir = vim.fs.dirname(dest_path)
					if dest_dir and dest_dir ~= "" then
						vim.fn.mkdir(dest_dir, "p")
					end
					vim.uv.fs_copyfile(incoming_path, dest_path)
					stats.added = stats.added + 1
				else
					-- Case 2: Destination file exists -> check if identical or merge
					local function read_file(p)
						local f = io.open(p, "rb")
						if not f then
							return nil
						end
						local content = f:read("*a")
						f:close()
						return content
					end

					local dest_content = read_file(dest_path)
					local inc_content = read_file(incoming_path)

					if dest_content and inc_content and dest_content == inc_content then
						stats.identical = stats.identical + 1
					else
						-- Differences exist: perform 3-way merge
						local base_file_to_use = nil
						local temp_base_file = nil

						if vim.fn.filereadable(base_in_zip) == 1 then
							base_file_to_use = base_in_zip
						else
							-- Try to get base from destination git repo
							local git_base_content = nil
							if vim.fn.executable("git") == 1 then
								if manifest.base_ref and manifest.base_ref ~= "" and manifest.base_ref ~= "WORKTREE" then
									local bres = vim
										.system({
											"git",
											"-C",
											target_dir,
											"show",
											manifest.base_ref .. ":" .. rel_path,
										})
										:wait()
									if bres and bres.code == 0 and bres.stdout then
										git_base_content = bres.stdout
									end
								end
								if not git_base_content then
									local hres = vim.system({ "git", "-C", target_dir, "show", "HEAD:" .. rel_path }):wait()
									if hres and hres.code == 0 and hres.stdout then
										git_base_content = hres.stdout
									end
								end
							end

							temp_base_file = vim.fn.tempname() .. "_base"
							local bf = io.open(temp_base_file, "wb")
							if bf then
								if git_base_content then
									bf:write(git_base_content)
								end
								bf:close()
								base_file_to_use = temp_base_file
							end
						end

						-- Merge using git merge-file
						local merge_ok = false
						if vim.fn.executable("git") == 1 and base_file_to_use then
							local merge_cmd = {
								"git",
								"merge-file",
								"-L",
								"current (workspace)",
								"-L",
								"base",
								"-L",
								string.format("incoming (%s)", zip_filename),
								dest_path,
								base_file_to_use,
								incoming_path,
							}
							local merge_res = vim.system(merge_cmd):wait()
							if merge_res then
								if merge_res.code == 0 then
									-- Clean merge without conflicts
									stats.merged_clean = stats.merged_clean + 1
									merge_ok = true
								elseif merge_res.code > 0 then
									-- Merge with conflicts!
									stats.conflicted = stats.conflicted + 1
									stats.total_conflicts = stats.total_conflicts + merge_res.code
									table.insert(stats.conflicted_files, { file = rel_path, conflicts = merge_res.code })
									merge_ok = true
								else
									-- Return code < 0: Binary file or error
									vim.uv.fs_copyfile(incoming_path, dest_path)
									stats.binary = stats.binary + 1
									merge_ok = true
								end
							end
						end

						-- Fallback if git is not executable
						if not merge_ok then
							local conf_content = string.format(
								"<<<<<<< current (workspace)\n%s\n=======\n%s\n>>>>>>> incoming (%s)\n",
								dest_content or "",
								inc_content or "",
								zip_filename
							)
							local wf = io.open(dest_path, "wb")
							if wf then
								wf:write(conf_content)
								wf:close()
							end
							stats.conflicted = stats.conflicted + 1
							stats.total_conflicts = stats.total_conflicts + 1
							table.insert(stats.conflicted_files, { file = rel_path, conflicts = 1 })
						end

						if temp_base_file then
							pcall(vim.fn.delete, temp_base_file)
						end
					end
				end
			end
		end
	end

	-- Clean up temporary extraction folder
	pcall(vim.fn.delete, extract_tmp, "rf")

	-- Reload any open buffers in Neovim that were touched
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) then
			local bname = vim.api.nvim_buf_get_name(b)
			for _, touched in ipairs(touched_files) do
				if path_util.equals(bname, touched) then
					pcall(vim.api.nvim_buf_call, b, function()
						vim.cmd("edit!")
					end)
					break
				end
			end
		end
	end

	-- Refresh open buffers & editor state
	pcall(vim.cmd, "checktime")
	pcall(function()
		require("neo-tree.sources.manager").refresh("filesystem")
	end)

	if M.is_open() and M.state.mode == "same_branch" then
		M.start_same_branch({ cwd = target_dir })
	end

	return true, nil, stats
end

--- Prompts user to select a zip file, validates KRS compatibility, and confirms before importing
--- @param initial_path? string Optional path to zip archive
function M.import_diff_prompt(initial_path)
	local cwd = M.state.cwd or vim.fn.getcwd()

	local function confirm_and_import(target_zip)
		local full_path = (target_zip:sub(1, 1) == "/" or target_zip:match("^%a:[/\\]")) and path_util.normalize(target_zip)
			or path_util.join(cwd, target_zip)

		if vim.fn.filereadable(full_path) == 0 then
			notify("Zip archive not found: " .. full_path, vim.log.levels.ERROR)
			return
		end

		local manifest, err = M.read_zip_manifest(full_path)
		if not manifest then
			notify(
				"❌ Incompatible zip archive:\n"
					.. (err or "Missing .krs_diff_manifest.json (not exported by KRS Git Diff Mode)."),
				vim.log.levels.ERROR
			)
			return
		end

		local file_count = #manifest.files
		local zip_filename = vim.fn.fnamemodify(full_path, ":t")
		local branch_label = (manifest.branch and manifest.branch ~= "") and (" (from branch '" .. manifest.branch .. "')")
			or ""

		-- Confirmation prompt
		local choices = {
			string.format("1. 🔀 Confirm: Merge & import %d file(s)", file_count),
			"2. 📋 Review list of files in archive",
			"3. ❌ Cancel",
		}

		local prompt_title =
			string.format("📦 Import & Merge %d files from '%s'%s?", file_count, zip_filename, branch_label)
		vim.ui.select(choices, { prompt = prompt_title }, function(choice, idx)
			if not choice or not idx or idx == 3 then
				notify("Import cancelled")
				return
			end

			if idx == 2 then
				local file_lines = {}
				for i, f in ipairs(manifest.files) do
					table.insert(file_lines, string.format("%d. %s", i, f))
				end
				notify(string.format("Files in '%s':\n%s", zip_filename, table.concat(file_lines, "\n")), vim.log.levels.INFO)
				vim.schedule(function()
					confirm_and_import(target_zip)
				end)
				return
			end

			if idx == 1 then
				local ok, extract_err, stats = M.import_diff_files_from_zip(full_path, cwd, manifest)
				if ok then
					if stats and stats.conflicted > 0 then
						local conf_msg = string.format(
							"⚠️ Imported %d file(s) from '%s' with %d conflict(s) in %d file(s)!\nConflict markers (<<<<<<< / ======= / >>>>>>>) were generated:\n",
							file_count,
							zip_filename,
							stats.total_conflicts,
							stats.conflicted
						)
						for _, cf in ipairs(stats.conflicted_files) do
							conf_msg = conf_msg
								.. string.format("  • %s (%d conflict%s)\n", cf.file, cf.conflicts, cf.conflicts == 1 and "" or "s")
						end
						conf_msg = conf_msg .. "💡 Tip: Search for '<<<<<<<' or use Conflict Resolver (<leader>gm) to resolve."
						notify(vim.trim(conf_msg), vim.log.levels.WARN)
					else
						notify(
							string.format(
								"✅ Successfully merged & imported %d file(s) from '%s' into project root!",
								file_count,
								zip_filename
							),
							vim.log.levels.INFO
						)
					end
				else
					notify("Failed to import zip files: " .. tostring(extract_err), vim.log.levels.ERROR)
				end
			end
		end)
	end

	if initial_path and initial_path ~= "" then
		confirm_and_import(initial_path)
		return
	end

	-- Scan cwd for .zip files to suggest
	local found_zips = {}
	local handle = vim.uv.fs_scandir(cwd)
	while handle do
		local name, t = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if t == "file" and name:lower():match("%.zip$") then
			table.insert(found_zips, name)
		end
	end

	if #found_zips > 0 then
		local options = {}
		for _, z in ipairs(found_zips) do
			table.insert(options, "📦 " .. z)
		end
		table.insert(options, "📂 Browse / Type custom path...")

		vim.ui.select(options, { prompt = "⚡ Select Diff Zip Archive to Import:" }, function(choice, idx)
			if not choice or not idx then
				return
			end
			if idx <= #found_zips then
				confirm_and_import(found_zips[idx])
			else
				local input_modal = require("plugins.krs.ui.input_modal")
				input_modal.open({
					label = "Enter path to KRS Diff Zip archive:",
					default_value = found_zips[1] or "",
					relative = "editor",
					callback = function(ok, val)
						if ok and val and vim.trim(val) ~= "" then
							confirm_and_import(vim.trim(val))
						end
					end,
				})
			end
		end)
	else
		local input_modal = require("plugins.krs.ui.input_modal")
		input_modal.open({
			label = "Enter path to KRS Diff Zip archive:",
			default_value = "",
			relative = "editor",
			callback = function(ok, val)
				if ok and val and vim.trim(val) ~= "" then
					confirm_and_import(vim.trim(val))
				end
			end,
		})
	end
end

--- Prompts user for zip filename and exports current diff files
function M.export_diff_prompt()
	if not M.is_open() then
		notify("Git Diff Mode is not active", vim.log.levels.WARN)
		return
	end

	if not M.state.files or #M.state.files == 0 then
		notify("No changed files in diff mode to export", vim.log.levels.WARN)
		return
	end

	local exportable = {}
	for _, f in ipairs(M.state.files) do
		if f.status ~= "D" then
			table.insert(exportable, f)
		end
	end

	if #exportable == 0 then
		notify("All changed files are deletions; nothing to export", vim.log.levels.WARN)
		return
	end

	local default_name = M.get_default_export_name(M.state.cwd)
	local input_modal = require("plugins.krs.ui.input_modal")
	input_modal.open({
		label = string.format("📦 Export %d Diff File(s) to Zip Archive:", #exportable),
		default_value = default_name,
		relative = "editor",
		callback = function(ok, val)
			if not ok or not val or vim.trim(val) == "" then
				return
			end
			local zip_name = vim.trim(val)
			if not zip_name:lower():match("%.zip$") then
				zip_name = zip_name .. ".zip"
			end
			M.export_diff_files_to_zip(zip_name, exportable, M.state.cwd)
		end,
	})
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

	pcall(vim.api.nvim_create_user_command, "GitDiffExportZip", function()
		M.export_diff_prompt()
	end, { desc = "Export currently diffed files to a zip archive" })

	pcall(vim.api.nvim_create_user_command, "GitDiffImportZip", function(opts)
		local arg = opts.args and vim.trim(opts.args) or nil
		M.import_diff_prompt(arg ~= "" and arg or nil)
	end, {
		desc = "Import and apply diff files from a KRS zip archive",
		nargs = "?",
		complete = "file",
	})
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
		"GitDiffExportZip",
		"GitDiffImportZip",
	},
	config = function()
		M.setup()
	end,
}, { __index = M })
