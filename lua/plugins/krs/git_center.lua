-- ============================================================================
-- KRS PLUGIN: Git Center (Ctrl + Shift + G) -- stage, commit, push, review.
-- ============================================================================
-- LAYOUT
--   Left  A control panel with submodule tabs at top, followed by four sections:
--         commit box, staged files, unstaged/untracked files, and shortcuts.
--   Right A live VSCode-style diff of the file under the cursor.
--
-- KEYS (inside the panel)
--   Alt+h / Alt+l switch submodule tab     1..4 jump to a section
--   Tab switch panel focus                 s/S  stage file / everything
--   u/U unstage file / everything          r/R  restore file / section
--   d   full-screen diff modal             c/m/t edit title/description/tag
--   C   commit (and tag)                   P    push (asks about upstream)
--   <F5>/<C-r> refresh                     <C-S-j>/<C-S-k> scroll preview
--   q/<Esc>/<C-S-g> close
--
-- OUTSIDE THE PANEL
--   <C-S-g> toggles the Git Center, <C-S-x> / <A-s> stage everything.
--
-- STRUCTURE
--   krs.git.cmd         Running git (sync reads, async writes).
--   krs.git.status      Parsing the repository state.
--   krs.git.diff        Formatting and colouring diffs.
--   krs.git.submodules  Discovering and listing root & submodules.
--   this file           Windows, panel rendering, tab bar and key handling.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local git = lazy_req("krs.git.cmd")
local status = lazy_req("krs.git.status")
local diff = lazy_req("krs.git.diff")
local submodules = lazy_req("krs.git.submodules")
local ui = lazy_req("krs.core.ui")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path_util = lazy_req("krs.core.path")
local icons = lazy_req("krs.core.icons")

local env_ok, env_mod = pcall(require, "krs.core.environment")
local env = env_ok and env_mod.detect() or {}
local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Git Center geometry, as a fraction of the editor. The left panel takes
	--- `left_ratio` of the total width; the preview gets the rest.
	width_ratio = 0.92,
	height_ratio = 0.85,
	left_ratio = 0.30,

	--- Full-screen diff modal geometry.
	modal_width_ratio = 0.94,
	modal_height_ratio = 0.90,

	--- Commit message editor modal.
	editor_width_ratio = 0.65,
	editor_height = 6,

	--- Preview refresh delay after the cursor moves, in milliseconds. Enough to
	--- coalesce held-down `j`, short enough to feel immediate.
	preview_debounce_ms = is_mobile_or_proot and 130 or 40,

	--- Notification titles.
	notify_title = "Git Center",
	control_title = "Git Control Center",

	--- State persistence file name in project `.krsnvim/`.
	config_filename = "git-center.json",

	--- Submodule tab indicator colors mode (default: false = plain text, true = colored).
	tab_colored_indicators = false,

	keys = {
		--- Toggle the Git Center from anywhere.
		toggle = { "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>", "<leader>gc", "<leader>gC" },
		--- Stage everything from anywhere. Many aliases because terminals and GUIs
		--- disagree about how Alt/Meta combinations arrive.
		stage_all = {
			"<C-S-x>",
			"<C-S-X>",
			"<C-A-s>",
			"<C-A-S>",
			"<C-M-s>",
			"<C-M-S>",
			"<A-C-s>",
			"<A-C-S>",
			"<M-C-s>",
			"<M-C-S>",
			"<A-s>",
			"<A-S>",
			"<M-s>",
			"<M-S>",
			"<leader>gs",
		},
		--- Switch submodule tabs (left / right).
		tab_prev = { "<A-h>", "<A-H>", "<M-h>", "<M-H>", "<A-Left>", "<M-Left>" },
		tab_next = { "<A-l>", "<A-L>", "<M-l>", "<M-L>", "<A-Right>", "<M-Right>" },
		--- Resize the split between left control panel and right preview pane.
		resize_left = { "<", ",", "<M-,>", "<A-,>", "<C-w><", "<C-Left>", "<C-S-Left>" },
		resize_right = { ">", ".", "<M-.>", "<A-.>", "<C-w>>", "<C-Right>", "<C-S-Right>" },
		--- Close the panel.
		close = { "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>", "q", "<Esc>", "<esc>", "<ESC>", "<C-[>" },
		--- Scroll the preview pane.
		scroll_down = { "<C-S-j>", "<C-S-J>", "<C-j>", "<C-J>" },
		scroll_up = { "<C-S-k>", "<C-S-K>", "<C-k>", "<C-K>" },
		--- Refresh the panel.
		refresh = { "<F5>", "<C-r>" },
		--- Close the diff modal.
		modal_close = { "q", "<Esc>", "<esc>", "<ESC>", "<C-[>", "<C-c>", "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>" },
		--- Open selected file in a bufferline tab.
		open_tab = { "<S-CR>", "<S-Enter>", "<S-Return>" },
	},
}

-- ============================================================================
-- STATE -- open windows, submodules, and the commit form
-- ============================================================================

M.main_win, M.main_buf = nil, nil
M.preview_win, M.preview_buf = nil, nil
M.tab_win, M.tab_buf = nil, nil
M.diff_modal_win, M.diff_modal_buf = nil, nil

--- Discovered repository list: [1] = root repository, [2..n] = submodules.
M.submodules = {}

local ns_tabs = vim.api.nvim_create_namespace("krs_git_tabs")

--- Index of currently active submodule repository in `M.submodules`.
M.active_submodule_idx = 1

--- Project root directory.
M.root_dir = nil

--- Current left ratio (persisted per project and globally).
M.current_left_ratio = nil

--- Formatted diffs, keyed "<type>:<file>". Cleared on every refresh.
M.diff_cache = {}

--- Panel line number -> `{ type = "staged"|"unstaged"|"untracked", file = ... }`.
M.line_map = {}

--- The commit form, kept between openings so a draft is not lost.
M.commit_data = { title = "", description = "", tag = "" }

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
--- @param title string|nil Defaults to `M.settings.notify_title`.
local function notify(msg, level, title)
	vim.notify(msg, level or vim.log.levels.INFO, { title = title or M.settings.notify_title })
end

-- ============================================================================
-- PERSISTENCE & SUBMODULE TARGET RESOLUTION
-- ============================================================================

local GLOBAL_CONFIG_FILE = vim.fn.stdpath("data") .. "/krs_git_center.json"

--- Resolves the active target table: `{ name, path, is_root, full_path }`.
--- @return table
local function get_active_target()
	if not M.submodules or #M.submodules == 0 then
		local root = M.root_dir or vim.fn.getcwd()
		return { name = "Root", path = ".", is_root = true, full_path = root }
	end
	return M.submodules[M.active_submodule_idx] or M.submodules[1]
end

--- Loads settings from project `.krsnvim/git-center.json` with fallback to global store.
--- @param root string|nil Project root directory.
--- @return table
local function load_git_center_config(root)
	local global_data = store.load(GLOBAL_CONFIG_FILE, {})
	local project_cfg = root and project.config_path(M.settings.config_filename, root)
	local project_data = project_cfg and store.load(project_cfg, nil)

	local merged = {}
	if type(global_data) == "table" then
		for k, v in pairs(global_data) do
			merged[k] = v
		end
	end
	if type(project_data) == "table" then
		for k, v in pairs(project_data) do
			merged[k] = v
		end
	end
	return merged
end

--- Saves settings to both project `.krsnvim/git-center.json` and global store.
--- @param root string|nil Project root directory.
--- @param updates table
local function save_git_center_config(root, updates)
	if root then
		local project_cfg = project.config_path(M.settings.config_filename, root)
		local data = store.load(project_cfg, {})
		for k, v in pairs(updates) do
			data[k] = v
		end
		store.save(project_cfg, data)
	end

	local global_data = store.load(GLOBAL_CONFIG_FILE, {})
	for k, v in pairs(updates) do
		global_data[k] = v
	end
	store.save(GLOBAL_CONFIG_FILE, global_data)
end

--- Loads the last active submodule tab identifier.
--- @param root string Project root directory.
--- @return string|nil saved_path Submodule relative path (e.g. "." or "plugins/foo").
local function load_saved_active_tab(root)
	local data = load_git_center_config(root)
	return data.current_tab or data.active_tab
end

local save_tab_timer = nil
--- Saves the active submodule tab identifier.
--- @param root string Project root directory.
--- @param target_path string Submodule relative path.
local function save_active_tab(root, target_path)
	if save_tab_timer then
		save_tab_timer:stop()
		save_tab_timer = nil
	end
	save_tab_timer = vim.defer_fn(function()
		save_tab_timer = nil
		save_git_center_config(root, { current_tab = target_path, active_tab = target_path })
	end, 500)
end

--- Loads the saved left panel width ratio.
--- @param root string|nil Project root directory.
--- @return number ratio Left panel fraction (e.g. 0.50).
local function load_saved_left_ratio(root)
	local data = load_git_center_config(root)
	local ratio = tonumber(data.left_ratio)
	if ratio and ratio >= 0.15 and ratio <= 0.85 then
		return ratio
	end
	return M.settings.left_ratio
end

--- Saves the left panel width ratio permanently.
--- @param root string|nil Project root directory.
--- @param ratio number Left panel fraction.
local function save_left_ratio(root, ratio)
	save_git_center_config(root, { left_ratio = ratio })
end

-- ============================================================================
-- WINDOW LIFECYCLE & RESIZING
-- ============================================================================

--- True when the Git Center is on screen.
--- @return boolean
function M.is_open()
	return (M.main_win ~= nil and vim.api.nvim_win_is_valid(M.main_win))
		or (M.preview_win ~= nil and vim.api.nvim_win_is_valid(M.preview_win))
		or (M.tab_win ~= nil and vim.api.nvim_win_is_valid(M.tab_win))
		or (M.diff_modal_win ~= nil and vim.api.nvim_win_is_valid(M.diff_modal_win))
end

--- Resizes the horizontal split between the left panel and preview pane.
--- Persists the preference immediately so it is remembered across sessions.
--- @param delta number Fraction to adjust left ratio (e.g. -0.03 or 0.03).
function M.resize_split(delta)
	if not M.is_open() or not (M.main_win and vim.api.nvim_win_is_valid(M.main_win)) then
		return
	end

	local cur_ratio = M.current_left_ratio or M.settings.left_ratio
	local new_ratio = ui.resize_dual_panel({
		left_win = M.main_win,
		right_win = M.preview_win,
		tab_win = M.tab_win,
		delta = delta,
		left_ratio = cur_ratio,
		width_ratio = M.settings.width_ratio,
		height_ratio = M.settings.height_ratio,
		gap = 2,
		min_ratio = 0.20,
		max_ratio = 0.80,
	})

	M.current_left_ratio = new_ratio
	if M.root_dir then
		save_left_ratio(M.root_dir, M.current_left_ratio)
	end

	if M.refresh then
		pcall(M.refresh)
	end
end

local is_closing = false

--- Closes every window this module owns and forgets their handles.
function M.close_git_center()
	if is_closing then
		return
	end
	is_closing = true
	M.refresh = nil
	local diff_win, prev_win, tab_win, main_win = M.diff_modal_win, M.preview_win, M.tab_win, M.main_win
	M.main_win, M.main_buf = nil, nil
	M.preview_win, M.preview_buf = nil, nil
	M.tab_win, M.tab_buf = nil, nil
	M.diff_modal_win, M.diff_modal_buf = nil, nil

	ui.close(diff_win)
	ui.close(prev_win)
	ui.close(tab_win)
	ui.close(main_win)
	is_closing = false
end

--- Finds the 1-indexed line number of the first change in `file_path`.
--- @param file_path string Target file path.
--- @param cwd string Base repository directory.
--- @param target_type string|nil Change type ("staged", "unstaged", "untracked", or commit hash).
--- @return integer|nil line_number 1-indexed line number, or nil if no diff line found.
local function get_first_changed_line(file_path, cwd, target_type)
	if not file_path or file_path == "" or not cwd then
		return nil
	end

	if target_type == "untracked" then
		return 1
	end

	local rel_path = path_util.relative_to(file_path, cwd) or file_path

	local args = {}
	if target_type == "staged" then
		args = { "diff", "--cached", "--no-ext-diff", "-U0", "--", rel_path }
	elseif target_type == "unstaged" then
		args = { "diff", "--no-ext-diff", "-U0", "--", rel_path }
	elseif target_type and target_type:match("^%x+$") then
		args = { "diff", target_type .. "~1", target_type, "--no-ext-diff", "-U0", "--", rel_path }
	else
		args = { "diff", "HEAD", "--no-ext-diff", "-U0", "--", rel_path }
	end

	local lines = git.lines(args, cwd)
	if #lines == 0 and target_type and target_type:match("^%x+$") then
		lines = git.lines({ "show", "--no-ext-diff", "-U0", "--format=", target_type, "--", rel_path }, cwd)
	end

	for _, line in ipairs(lines) do
		local new_start = line:match("^@@ %-%d+,?%d* %+(%d+)")
		if new_start then
			local line_num = tonumber(new_start)
			if line_num and line_num > 0 then
				return line_num
			end
		end
	end

	if not target_type or target_type == "unstaged" then
		local fallback = git.lines({ "diff", "--no-ext-diff", "-U0", "--", rel_path }, cwd)
		for _, line in ipairs(fallback) do
			local new_start = line:match("^@@ %-%d+,?%d* %+(%d+)")
			if new_start then
				local line_num = tonumber(new_start)
				if line_num and line_num > 0 then
					return line_num
				end
			end
		end
	end

	return nil
end

--- Opens a file in a bufferline tab.
--- If the file is already open in a buffer, switches to its existing tab.
--- Otherwise, opens the file into a new buffer/tab.
--- Jumps to the first line of changes if available.
--- Closes Git Center and any active modals first.
---
--- @param file_path string Target file path (relative or absolute).
--- @param cwd string|nil Base directory if file_path is relative.
--- @param target_type string|nil Change type ("staged", "unstaged", "untracked", or commit hash).
function M.open_file_in_tab(file_path, cwd, target_type)
	if not file_path or file_path == "" then
		return
	end

	local base_cwd = cwd or (get_active_target() and get_active_target().full_path) or vim.fn.getcwd()
	local full_path = file_path
	if not path_util.is_absolute(full_path) then
		full_path = path_util.join(base_cwd, file_path)
	else
		full_path = path_util.normalize(full_path)
	end

	local first_line = get_first_changed_line(full_path, base_cwd, target_type)

	M.close_git_center()

	vim.schedule(function()
		local cur_win = vim.api.nvim_get_current_win()
		local win_config = vim.api.nvim_win_get_config(cur_win)
		if win_config.relative ~= "" or vim.bo[vim.api.nvim_win_get_buf(cur_win)].buftype ~= "" then
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local cfg = vim.api.nvim_win_get_config(win)
				if cfg.relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
					vim.api.nvim_set_current_win(win)
					break
				end
			end
		end

		local ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(full_path))
		if ok and first_line then
			local buf_lines = vim.api.nvim_buf_line_count(0)
			local target_line = math.min(math.max(1, first_line), math.max(1, buf_lines))
			pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
			pcall(vim.cmd, "normal! zz")
		elseif not ok then
			notify("Failed to open file: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

--- Opens the Git Center, or closes it when it is already open.
function M.toggle_git_center()
	if M.is_open() then
		M.close_git_center()
	else
		M.open_git_center()
	end
end

-- ============================================================================
-- REPOSITORY QUERIES
-- ============================================================================

--- Snapshot of the repository at `cwd` (defaults to active submodule/root).
--- @param cwd string|nil Target repository directory.
--- @return table|nil info nil when the working directory is not a repository.
function M.get_git_info(cwd)
	local target = get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	if target and target.is_secondary and target.repo_alias then
		return status.info(cwd, target.repo_alias)
	end
	return status.info(cwd)
end

--- Raw diff lines for one file, or its contents when it is untracked.
--- @param file string Path relative to the repository.
--- @param file_type string "staged" | "unstaged" | "untracked".
--- @param cwd string|nil Repository directory.
--- @return string[] lines
--- @return boolean is_untracked
local function raw_diff_for(file, file_type, cwd)
	local target = get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()

	if target and target.is_secondary and target.repo_alias then
		local sec_ok, sec = pcall(require, "krs.git.secondary")
		if sec_ok and sec then
			if file_type == "staged" then
				return sec.lines(target.repo_alias, { "diff", "--cached", "--color=never", "--", file }, cwd), false
			end
			if file_type == "unstaged" then
				return sec.lines(target.repo_alias, { "diff", "--color=never", "--", file }, cwd), false
			end
		end
	end

	if file_type == "staged" then
		return git.lines({ "diff", "--cached", "--color=never", "--", file }, cwd), false
	end
	if file_type == "unstaged" then
		return git.lines({ "diff", "--color=never", "--", file }, cwd), false
	end

	local full_path = cwd and (cwd .. "/" .. file) or file
	if vim.fn.filereadable(full_path) == 1 then
		if is_mobile_or_proot then
			return vim.fn.readfile(full_path, "", 500), true
		end
		return vim.fn.readfile(full_path), true
	end
	return { "[ Empty or New File ]" }, true
end

-- ============================================================================
-- STAGE ALL (also reachable without opening the panel)
-- ============================================================================

--- Stages every unstaged and untracked change, reporting how many files moved.
--- Retries once after clearing a stale `index.lock`, which is the usual cause of
--- a failed `git add` right after a crash.
---
--- @param cwd string|nil Repository directory.
function M.stage_all_with_modal(cwd)
	cwd = cwd or (get_active_target() and get_active_target().full_path) or vim.fn.getcwd()
	git.clean_stale_lock(cwd)

	local info = M.get_git_info(cwd)
	if not info then
		notify("❌ Not inside a valid Git repository.", vim.log.levels.ERROR, M.settings.control_title)
		return
	end

	local pending = #info.unstaged + #info.untracked
	if pending == 0 then
		notify(
			"ℹ️ Nothing to stage: no unstaged or untracked changes found.",
			vim.log.levels.WARN,
			M.settings.control_title
		)
		return
	end

	local function execute(is_retry)
		git.run({ "add", "-A" }, function(ok, output)
			if ok then
				notify(
					string.format("✅ Successfully staged %d file%s!", pending, pending == 1 and "" or "s"),
					vim.log.levels.INFO,
					M.settings.control_title
				)
			elseif output:match("index%.lock") and not is_retry and git.clean_stale_lock(cwd) then
				execute(true)
				return
			else
				notify(
					"❌ Failed to stage changes:\n" .. (output ~= "" and output or "Error executing git add"),
					vim.log.levels.ERROR,
					M.settings.control_title
				)
			end

			if M.is_open() and M.refresh then
				M.refresh()
			end
		end, cwd)
	end

	execute(false)
end

-- ============================================================================
-- PANEL CONTENT
-- ============================================================================

--- Renders the control panel.
---
M.submodule_statuses = {}
M.fetching_submodules = {}

local render_tab_bar -- Forward declaration

--- Asynchronously fetches submodule status for non-active tab indicators in background.
--- @param target table
local function fetch_target_status_async(target)
	if not target or not target.full_path or M.fetching_submodules[target.path] then
		return
	end
	M.fetching_submodules[target.path] = true
	local handle = status.info_start(target.full_path)
	if not handle then
		M.fetching_submodules[target.path] = nil
		return
	end

	vim.schedule(function()
		local info = status.info_finish(handle)
		M.fetching_submodules[target.path] = nil
		if info and target and target.path then
			M.submodule_statuses[target.path] = {
				has_changes = info.has_changes or (#info.staged + #info.unstaged + #info.untracked > 0),
				behind = info.behind or 0,
				ahead = info.ahead or 0,
			}
			if render_tab_bar and M.is_open() and M.tab_buf and vim.api.nvim_buf_is_valid(M.tab_buf) and M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
				local l_width = vim.api.nvim_win_get_width(M.main_win)
				render_tab_bar(l_width)
			end
		end
	end)
end

--- Returns submodule status info from cache or triggers background fetch.
--- Never blocks the UI thread.
--- @param target table
--- @return table
local function get_target_status(target)
	if not target or not target.full_path then
		return { has_changes = false, behind = 0, ahead = 0 }
	end
	if M.submodule_statuses[target.path] then
		return M.submodule_statuses[target.path]
	end
	if not is_mobile_or_proot then
		fetch_target_status_async(target)
	end
	return { has_changes = false, behind = 0, ahead = 0 }
end

--- Sets up highlight groups for the submodule tab bar attached to Git Center.
local function setup_tab_highlights()
	local function get_hl(name)
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
		if ok and hl and next(hl) then
			return hl
		end
		return nil
	end

	local sel_hl = get_hl("BufferLineBufferSelected") or get_hl("TabLineSel") or get_hl("Title") or { fg = 16777215, bg = 3883602, bold = true }
	local bg_hl = get_hl("BufferLineBackground") or get_hl("TabLine") or get_hl("Comment") or { fg = 10066329, bg = 1973790 }
	local fill_hl = get_hl("BufferLineFill") or get_hl("TabLineFill") or get_hl("NormalFloat") or { bg = 1579032 }
	local sep_hl = get_hl("BufferLineSeparator") or get_hl("FloatBorder") or { fg = 5592405 }
	local ok_hl = get_hl("GitSignsAdd") or get_hl("DiagnosticOk") or get_hl("String") or { fg = 5307003 }
	local dim_hl = get_hl("Comment") or get_hl("NonText") or { fg = 5132371 }
	local inc_hl = get_hl("GitSignsChange") or get_hl("DiagnosticInfo") or get_hl("Special") or { fg = 9023482 }
	local out_hl = get_hl("DiagnosticWarn") or get_hl("Number") or { fg = 16429932 }

	local active_bg = sel_hl.bg and string.format("#%06x", sel_hl.bg) or "#383c4a"
	local active_fg = sel_hl.fg and string.format("#%06x", sel_hl.fg) or "#ffffff"
	local fill_bg = fill_hl.bg and string.format("#%06x", fill_hl.bg) or "#181818"
	local fill_fg = fill_hl.fg and string.format("#%06x", fill_hl.fg) or "#888888"
	local inactive_bg = bg_hl.bg and string.format("#%06x", bg_hl.bg) or fill_bg
	local inactive_fg = bg_hl.fg and string.format("#%06x", bg_hl.fg) or "#999999"
	local sep_fg = sep_hl.fg and string.format("#%06x", sep_hl.fg) or "#555555"

	local dot_changed_fg = ok_hl.fg and string.format("#%06x", ok_hl.fg) or "#50fa7b"
	local dot_clean_fg = dim_hl.fg and string.format("#%06x", dim_hl.fg) or "#485263"
	local incoming_fg = inc_hl.fg and string.format("#%06x", inc_hl.fg) or "#8be9fd"
	local outgoing_fg = out_hl.fg and string.format("#%06x", out_hl.fg) or "#ffb86c"

	vim.api.nvim_set_hl(0, "KRSGitTabActive", { fg = active_fg, bg = active_bg, bold = true })
	vim.api.nvim_set_hl(0, "KRSGitTabActiveCap", { fg = active_bg, bg = fill_bg })
	vim.api.nvim_set_hl(0, "KRSGitTabInactive", { fg = inactive_fg, bg = inactive_bg })
	vim.api.nvim_set_hl(0, "KRSGitTabFill", { bg = fill_bg, fg = fill_fg })
	vim.api.nvim_set_hl(0, "KRSGitTabSep", { fg = sep_fg, bg = fill_bg })
	vim.api.nvim_set_hl(0, "KRSGitTabBorder", { fg = sep_fg, bg = fill_bg })

	vim.api.nvim_set_hl(0, "KRSGitTabDotChangedActive", { fg = dot_changed_fg, bg = active_bg, bold = true })
	vim.api.nvim_set_hl(0, "KRSGitTabDotCleanActive", { fg = dot_clean_fg, bg = active_bg })
	vim.api.nvim_set_hl(0, "KRSGitTabIncomingActive", { fg = incoming_fg, bg = active_bg, bold = true })
	vim.api.nvim_set_hl(0, "KRSGitTabOutgoingActive", { fg = outgoing_fg, bg = active_bg, bold = true })

	vim.api.nvim_set_hl(0, "KRSGitTabDotChangedInactive", { fg = dot_changed_fg, bg = inactive_bg, bold = true })
	vim.api.nvim_set_hl(0, "KRSGitTabDotCleanInactive", { fg = dot_clean_fg, bg = inactive_bg })
	vim.api.nvim_set_hl(0, "KRSGitTabIncomingInactive", { fg = incoming_fg, bg = inactive_bg, bold = true })
	vim.api.nvim_set_hl(0, "KRSGitTabOutgoingInactive", { fg = outgoing_fg, bg = inactive_bg, bold = true })
end

M.tab_click_ranges = {}

--- Toggles between plain text indicators and colored indicators for submodule tabs.
--- Persists preference to project config and stdpath data.
function M.toggle_colored_tab_indicators()
	M.settings.tab_colored_indicators = not M.settings.tab_colored_indicators
	if M.root_dir then
		save_git_center_config(M.root_dir, { tab_colored_indicators = M.settings.tab_colored_indicators })
	else
		save_git_center_config(nil, { tab_colored_indicators = M.settings.tab_colored_indicators })
	end

	local label = M.settings.tab_colored_indicators and "ENABLED (Colored)" or "DISABLED (Plain Text)"
	notify("🐙 Git Center: Tab Indicator Colors " .. label)

	if M.is_open() and M.refresh then
		M.refresh()
	end
end

--- Renders bufferline-style submodule tabs into M.tab_buf, directly overlaying top border.
--- @param left_w integer Inner width of left panel.
render_tab_bar = function(left_w)
	if not M.tab_buf or not vim.api.nvim_buf_is_valid(M.tab_buf) then
		return
	end

	setup_tab_highlights()

	vim.bo[M.tab_buf].modifiable = true
	vim.api.nvim_buf_clear_namespace(M.tab_buf, ns_tabs, 0, -1)

	local targets = M.submodules
	if not targets or #targets == 0 then
		targets = { get_active_target() }
	end

	M.tab_click_ranges = {}
	local chunks = {}

	table.insert(chunks, { text = "╭", hl = "KRSGitTabBorder" })
	table.insert(chunks, { text = " ", hl = "KRSGitTabFill" })

	for idx, item in ipairs(targets) do
		local st = get_target_status(item)
		local is_active = (idx == M.active_submodule_idx)
		local icon = item.is_root and icons.get("git") or icons.get("dir")
		local name = item.name or "Root"
		local label = string.format("%s %s", icon, name)

		local dot_symbol = st.has_changes and icons.get("dot") or icons.get("clean_dot")
		local inc_symbol = (st.behind > 0) and icons.get("incoming") or ""
		local out_symbol = (st.ahead > 0) and icons.get("outgoing") or ""

		local base_tab_hl = is_active and "KRSGitTabActive" or "KRSGitTabInactive"
		local dot_hl = base_tab_hl
		local inc_hl = base_tab_hl
		local out_hl = base_tab_hl

		if M.settings.tab_colored_indicators then
			dot_hl = is_active
					and (st.has_changes and "KRSGitTabDotChangedActive" or "KRSGitTabDotCleanActive")
				or (st.has_changes and "KRSGitTabDotChangedInactive" or "KRSGitTabDotCleanInactive")

			inc_hl = is_active and "KRSGitTabIncomingActive" or "KRSGitTabIncomingInactive"
			out_hl = is_active and "KRSGitTabOutgoingActive" or "KRSGitTabOutgoingInactive"
		end

		if is_active then
			table.insert(chunks, { text = "", hl = "KRSGitTabActiveCap" })
			table.insert(chunks, { text = string.format(" %s ", label), hl = "KRSGitTabActive", idx = idx })
			table.insert(chunks, { text = dot_symbol, hl = dot_hl, idx = idx })
			if inc_symbol ~= "" then
				table.insert(chunks, { text = " " .. inc_symbol, hl = inc_hl, idx = idx })
			end
			if out_symbol ~= "" then
				table.insert(chunks, { text = " " .. out_symbol, hl = out_hl, idx = idx })
			end
			table.insert(chunks, { text = " ", hl = "KRSGitTabActive", idx = idx })
			table.insert(chunks, { text = "", hl = "KRSGitTabActiveCap" })
			table.insert(chunks, { text = " ", hl = "KRSGitTabFill" })
		else
			table.insert(chunks, { text = string.format("  %s ", label), hl = "KRSGitTabInactive", idx = idx })
			table.insert(chunks, { text = dot_symbol, hl = dot_hl, idx = idx })
			if inc_symbol ~= "" then
				table.insert(chunks, { text = " " .. inc_symbol, hl = inc_hl, idx = idx })
			end
			if out_symbol ~= "" then
				table.insert(chunks, { text = " " .. out_symbol, hl = out_hl, idx = idx })
			end
			table.insert(chunks, { text = "  ", hl = "KRSGitTabInactive", idx = idx })
			if idx < #targets then
				table.insert(chunks, { text = "│", hl = "KRSGitTabSep" })
			else
				table.insert(chunks, { text = " ", hl = "KRSGitTabFill" })
			end
		end
	end

	local full_text = ""
	local highlights = {}
	local cur_cell = 0

	for _, chunk in ipairs(chunks) do
		local start_col = #full_text
		local cell_width = vim.fn.strdisplaywidth(chunk.text)
		local start_cell = cur_cell

		full_text = full_text .. chunk.text
		local end_col = #full_text
		cur_cell = cur_cell + cell_width

		table.insert(highlights, { start_col = start_col, end_col = end_col, hl = chunk.hl })

		if chunk.idx then
			table.insert(M.tab_click_ranges, {
				start_col = start_cell,
				end_col = cur_cell,
				idx = chunk.idx,
			})
		end
	end

	local target_cells = left_w + 1
	local text_cells = vim.fn.strdisplaywidth(full_text)
	if text_cells < target_cells then
		local pad = string.rep("─", target_cells - text_cells)
		local start_col = #full_text
		full_text = full_text .. pad
		local end_col = #full_text
		table.insert(highlights, { start_col = start_col, end_col = end_col, hl = "KRSGitTabBorder" })
	end

	local start_col_r = #full_text
	full_text = full_text .. "╮"
	local end_col_r = #full_text
	table.insert(highlights, { start_col = start_col_r, end_col = end_col_r, hl = "KRSGitTabBorder" })

	vim.api.nvim_buf_set_lines(M.tab_buf, 0, -1, false, { full_text })
	vim.bo[M.tab_buf].modifiable = false

	for _, h in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(M.tab_buf, ns_tabs, 0, h.start_col, {
			end_col = h.end_col,
			hl_group = h.hl,
		})
	end
end

--- @param info table Repository snapshot.
--- @param width integer Panel width, used for the separators.
--- @return string[] lines Panel text.
--- @return table line_map Line number -> `{ type, file }` for file rows.
--- @return table section_lines Section number (1-4) -> line number.
local function build_panel_content(info, width)
	local lines, line_map, section_lines = {}, {}, {}

	local function add(text)
		if type(text) == "string" and (text:find("\n") or text:find("\r")) then
			local split_lines = vim.split(text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
			for _, l in ipairs(split_lines) do
				table.insert(lines, l)
			end
		else
			table.insert(lines, text)
		end
		return #lines
	end

	local function separator(char)
		add(string.rep(char, width - 2))
	end

	--- Adds a file row and records what it points at.
	local function add_file(prefix, file, file_type)
		line_map[add("   " .. prefix .. " " .. file)] = { type = file_type, file = file }
	end

	add(string.format(" 🌿 Branch: %s%s", info.branch, info.upstream and (" (Tracking " .. info.upstream .. ")") or ""))
	add(string.format(" 📊 Changes: +%d -%d lines", info.added, info.deleted))
	add(
		string.format(
			" 🟢 Staged: %d  |  🔴 Unstaged: %d  |  ❓ Untracked: %d",
			#info.staged,
			#info.unstaged,
			#info.untracked
		)
	)
	separator("═")

	section_lines[1] = add(" 📝 [SECTION 1: COMMIT BOX & TAG] (Press 1)")
	local title_display = M.commit_data.title ~= "" and M.commit_data.title or "<Press c to edit in Vim>"
	add("   [c] Title:       " .. title_display)

	if M.commit_data.description ~= "" then
		local desc_lines = vim.split(M.commit_data.description:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
		for i, dline in ipairs(desc_lines) do
			if i == 1 then
				add("   [m] Description: " .. dline)
			else
				add("                    " .. dline)
			end
		end
	else
		add("   [m] Description: <Optional - Press m>")
	end

	local tag_display = M.commit_data.tag ~= "" and M.commit_data.tag or "<Optional - Press t>"
	add("   [t] Tag:         " .. tag_display)
	add("   🚀 [C] Execute Commit & Tag  |  [P] Push Remote")
	separator("─")

	section_lines[2] =
		add(string.format(" 🟢 [SECTION 2: STAGED FILES (%d)] (Press 2 | [u] Unstage / [U] Unstage All)", #info.staged))
	for _, file in ipairs(info.staged) do
		add_file("✓", file, "staged")
	end
	if #info.staged == 0 then
		add("   (no files staged)")
	end
	separator("─")

	local pending = #info.unstaged + #info.untracked
	section_lines[3] = add(
		string.format(" 🔴 [SECTION 3: UNSTAGED & UNTRACKED FILES (%d)] (Press 3 | [s] Stage / [S] Stage All)", pending)
	)
	for _, file in ipairs(info.unstaged) do
		add_file("M", file, "unstaged")
	end
	for _, file in ipairs(info.untracked) do
		add_file("?", file, "untracked")
	end
	if pending == 0 then
		add("   (working tree clean)")
	end
	separator("─")

	section_lines[4] = add(" ⚡ [SECTION 4: QUICK ACTIONS & SHORTCUTS] (Press 4)")
	for _, help in ipairs({
		"   [Alt+h / Alt+l] Switch Submodule Tab  |  [< / >] Resize Split Width",
		"   [b] Branch Manager (Create / Delete / Switch / Rename)",
		"   [l / L] Commit Log & History Viewer (--all)",
		"   [s] Stage file  |  [S] Stage All  |  [u] Unstage file  |  [U] Unstage All",
		"   [r] Restore File  |  [R] Restore Section  |  [d] Side-by-Side Diff Modal",
		"   [c] Commit Title  |  [C] Execute Commit & Tag  |  [P] Push to Remote",
		"   [Tab] Switch panel focus  |  [Ctrl+Shift+J/K] Scroll preview",
	}) do
		add(help)
	end

	return lines, line_map, section_lines
end

-- ============================================================================
-- DIFF MODAL
-- ============================================================================

-- ============================================================================
-- BRANCH MANAGEMENT (b)
-- ============================================================================

--- Opens the Branch Management modal UI.
--- @param target_cwd string|nil Repository path.
function M.open_branch_modal(target_cwd)
	local prev_win = vim.api.nvim_get_current_win()
	local active_cwd = target_cwd or (get_active_target() and get_active_target().full_path) or vim.fn.getcwd()
	local info = M.get_git_info(active_cwd)
	if not info then
		notify("Not inside a valid Git repository", vim.log.levels.WARN)
		return
	end

	local raw_branches = git_lines({ "branch", "-a", "--sort=-committerdate" }, active_cwd)
	local branches = {}
	local current_branch = info.branch or "main"

	for _, line in ipairs(raw_branches) do
		local clean = line:gsub("^%*%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
		if clean ~= "" and not clean:match("HEAD %->") then
			local is_current = line:sub(1, 1) == "*" or clean == current_branch
			local is_remote = clean:match("^remotes/") or clean:match("^origin/")
			local display_name = clean:gsub("^remotes/origin/", ""):gsub("^remotes/", ""):gsub("^origin/", "")

			local exists = false
			for _, b in ipairs(branches) do
				if b.name == display_name and b.is_remote == is_remote then
					exists = true
					break
				end
			end
			if not exists then
				table.insert(branches, {
					raw = clean,
					name = display_name,
					is_current = is_current,
					is_remote = is_remote,
				})
			end
		end
	end

	if #branches == 0 then
		table.insert(branches, { raw = current_branch, name = current_branch, is_current = true, is_remote = false })
	end

	local lines = {}
	local current_idx = 1
	for idx, b in ipairs(branches) do
		if b.is_current then
			current_idx = idx
			table.insert(lines, string.format(" 🌿 %-30s [CURRENT HEAD]", b.name))
		elseif b.is_remote then
			table.insert(lines, string.format(" 🌐 %-30s (remote)", b.name))
		else
			table.insert(lines, string.format(" 🌲 %-30s", b.name))
		end
	end

	local buf, win = ui.float({
		width = 0.68,
		height = math.min(18, math.max(6, #lines + 3)),
		title = " 🌿 Branch Manager | [Enter]: Switch | [c/n]: Create | [d]: Delete | [D]: Force Delete | [r]: Rename ",
		lines = lines,
		modifiable = false,
		zindex = 100,
	})

	vim.api.nvim_set_option_value("cursorline", true, { win = win })
	pcall(vim.api.nvim_win_set_cursor, win, { current_idx, 0 })

	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

	local function close_modal()
		ui.close(win)
		if prev_win and vim.api.nvim_win_is_valid(prev_win) then
			pcall(vim.api.nvim_set_current_win, prev_win)
		elseif M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
			pcall(vim.api.nvim_set_current_win, M.main_win)
		end
	end

	local function checkout_selected()
		local cursor_row = vim.api.nvim_win_get_cursor(win)[1]
		local target_b = branches[cursor_row]
		if not target_b then
			return
		end

		close_modal()

		if target_b.is_current then
			notify("Already on branch: " .. target_b.name, vim.log.levels.WARN)
			return
		end

		notify("🌿 Checking out branch: " .. target_b.name .. "...")
		local cmd_args = { "checkout", target_b.name }
		if target_b.is_remote then
			cmd_args = { "checkout", "-b", target_b.name, target_b.raw }
		end

		git_run(cmd_args, function(ok, output)
			if ok then
				notify("✅ Checked out branch: " .. target_b.name)
			else
				git_run({ "switch", target_b.name }, function(ok2, output2)
					if ok2 then
						notify("✅ Switched to branch: " .. target_b.name)
					else
						notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
					end
					if M.is_open() and M.refresh then
						M.refresh()
					end
				end, active_cwd)
				return
			end
			if M.is_open() and M.refresh then
				M.refresh()
			end
		end, active_cwd)
	end

	local function create_branch()
		close_modal()
		require("plugins.krs.input_modal").open({
			label = "Create & Checkout New Branch",
			default_value = "",
			relative = "editor",
			callback = function(ok, new_name)
				if ok and new_name and new_name ~= "" then
					new_name = new_name:gsub("%s+", "-"):gsub("[^%w%-_/.]", "")
					git_run({ "checkout", "-b", new_name }, function(ok2, output)
						if ok2 then
							notify("🌿 Created and switched to branch: " .. new_name)
						else
							notify("❌ Failed to create branch:\n" .. output, vim.log.levels.ERROR)
						end
						if M.is_open() and M.refresh then
							M.refresh()
						end
					end, active_cwd)
				end
			end,
		})
	end

	local function delete_branch(force)
		local cursor_row = vim.api.nvim_win_get_cursor(win)[1]
		local target_b = branches[cursor_row]
		if not target_b then
			return
		end
		if target_b.is_current then
			notify("Cannot delete current active branch!", vim.log.levels.WARN)
			return
		end

		local flag = force and "-D" or "-d"
		local label = force and "FORCE DELETE" or "Delete"
		if vim.fn.confirm("⚠️ " .. label .. " branch '" .. target_b.name .. "'?", "&Yes\n&No", 2) ~= 1 then
			return
		end

		close_modal()
		git_run({ "branch", flag, target_b.name }, function(ok, output)
			if ok then
				notify("🗑️ Deleted branch: " .. target_b.name)
			elseif not force and output:match("not fully merged") then
				if
					vim.fn.confirm(
						"⚠️ Branch '" .. target_b.name .. "' is not fully merged. Force delete (-D)?",
						"&Yes\n&No",
						2
					) == 1
				then
					git_run({ "branch", "-D", target_b.name }, function(ok2, output2)
						if ok2 then
							notify("🗑️ Force deleted branch: " .. target_b.name)
						else
							notify("❌ Failed to delete branch:\n" .. output2, vim.log.levels.ERROR)
						end
						if M.is_open() and M.refresh then
							M.refresh()
						end
					end, active_cwd)
				end
			else
				notify("❌ Failed to delete branch:\n" .. output, vim.log.levels.ERROR)
			end
			if M.is_open() and M.refresh then
				M.refresh()
			end
		end, active_cwd)
	end

	local function rename_branch()
		local cursor_row = vim.api.nvim_win_get_cursor(win)[1]
		local target_b = branches[cursor_row]
		if not target_b then
			return
		end
		close_modal()

		require("plugins.krs.input_modal").open({
			label = "Rename Branch '" .. target_b.name .. "'",
			default_value = target_b.name,
			relative = "editor",
			callback = function(ok, new_name)
				if ok and new_name and new_name ~= "" and new_name ~= target_b.name then
					new_name = new_name:gsub("%s+", "-"):gsub("[^%w%-_/.]", "")
					git_run({ "branch", "-m", target_b.name, new_name }, function(ok2, output)
						if ok2 then
							notify("✏️ Renamed branch to: " .. new_name)
						else
							notify("❌ Failed to rename branch:\n" .. output, vim.log.levels.ERROR)
						end
						if M.is_open() and M.refresh then
							M.refresh()
						end
					end, active_cwd)
				end
			end,
		})
	end

	vim.keymap.set("n", "<CR>", checkout_selected, opts)
	vim.keymap.set("n", "c", create_branch, opts)
	vim.keymap.set("n", "n", create_branch, opts)
	vim.keymap.set("n", "d", function()
		delete_branch(false)
	end, opts)
	vim.keymap.set("n", "D", function()
		delete_branch(true)
	end, opts)
	vim.keymap.set("n", "r", rename_branch, opts)

	for _, key in ipairs(M.settings.keys.modal_close) do
		vim.keymap.set("n", key, close_modal, opts)
	end
end

-- ============================================================================
-- COMMIT LOG & HISTORY MODAL (l / L)
-- ============================================================================

--- Full commit log modal showing git log --all, commit info, description, author, date, and side-by-side diff.
--- @param target_cwd string|nil Repository path.
function M.open_commit_log_modal(target_cwd)
	local prev_win = vim.api.nvim_get_current_win()
	local orig_cwd = vim.fn.getcwd()
	local active_cwd = target_cwd or (get_active_target() and get_active_target().full_path) or orig_cwd

	local info = M.get_git_info(active_cwd)
	if not info then
		notify("Not inside a valid Git repository", vim.log.levels.WARN)
		return
	end

	local raw_commits = git.lines({
		"log",
		"--all",
		"--pretty=format:%h%x1f%an%x1f%ar%x1f%s%x1f%d",
		"-n",
		"150",
	}, active_cwd)

	local commits = {}
	local list_lines = {}
	for _, line in ipairs(raw_commits) do
		local parts = vim.split(line, "\x1f", { plain = true })
		if #parts >= 4 then
			local hash = parts[1] or ""
			local author = parts[2] or ""
			local date = parts[3] or ""
			local subject = parts[4] or ""
			local refs = parts[5] or ""

			table.insert(commits, {
				hash = hash,
				author = author,
				date = date,
				subject = subject,
				refs = refs,
			})
			table.insert(
				list_lines,
				string.format(
					" %-7s │ %-12.12s │ %-10.10s │ %s%s",
					hash,
					author,
					date,
					subject,
					refs ~= "" and (" " .. refs) or ""
				)
			)
		end
	end

	if #commits == 0 then
		notify("No commit history found", vim.log.levels.INFO)
		return
	end

	diff.setup_highlights()

	local tot_w = math.floor(vim.o.columns * M.settings.width_ratio)
	local tot_h = math.floor(vim.o.lines * M.settings.height_ratio)
	local s_row = math.floor((vim.o.lines - tot_h) / 2)
	local s_col = math.floor((vim.o.columns - tot_w) / 2)

	local ratio = M.current_left_ratio or load_saved_left_ratio(active_cwd)
	local left_w = math.floor(tot_w * ratio)
	local right_w = tot_w - left_w - 2

	local z_index = require("krs.core.z_index")
	local log_z = z_index.next_zindex("git_center_log", { parent = "git_center", offset = 30 })

	local left_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[left_buf].buftype = "nofile"
	vim.bo[left_buf].bufhidden = "wipe"
	vim.bo[left_buf].swapfile = false
	vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, list_lines)

	local left_win = vim.api.nvim_open_win(left_buf, true, {
		relative = "editor",
		width = left_w,
		height = tot_h,
		row = s_row,
		col = s_col,
		style = "minimal",
		border = "rounded",
		zindex = log_z,
		title = " 📜 Git Log (--all) | [j/k]: Move | [K]: Checkout | [Enter/Tab]: Focus | [</>]: Resize | [q/Esc]: Close ",
		title_pos = "center",
	})
	vim.api.nvim_set_option_value("cursorline", true, { win = left_win })

	local right_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[right_buf].buftype = "nofile"
	vim.bo[right_buf].bufhidden = "wipe"
	vim.bo[right_buf].swapfile = false

	local right_win = vim.api.nvim_open_win(right_buf, false, {
		relative = "editor",
		width = right_w,
		height = tot_h,
		row = s_row,
		col = s_col + left_w + 2,
		style = "minimal",
		border = "rounded",
		zindex = log_z,
		title = " 👁️ Commit Details, Edited Files & Side-by-Side Diff ",
		title_pos = "center",
	})
	z_index.register("git_center_log", { left_win, right_win }, { parent = "git_center", offset = 30, zindex = log_z })
	vim.api.nvim_set_option_value("wrap", false, { win = right_win })
	vim.api.nvim_set_option_value("number", true, { win = right_win })

	local is_closed = false
	local function close_log_modal()
		if is_closed then
			return
		end
		is_closed = true
		ui.close(left_win)
		ui.close(right_win)
		if prev_win and vim.api.nvim_win_is_valid(prev_win) then
			pcall(vim.api.nvim_set_current_win, prev_win)
		elseif M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
			pcall(vim.api.nvim_set_current_win, M.main_win)
		end
	end

	for _, win in ipairs({ left_win, right_win }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = function()
				vim.schedule(close_log_modal)
			end,
		})
	end

	local current_commit_hash = nil
	local current_target_file = nil

	local function update_commit_details(target_filepath)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = commits[row]
		if not commit then
			return
		end

		local raw_stat = git_lines({ "show", "--name-status", "--pretty=format:", commit.hash }, active_cwd)
		local edited_files = {}
		for _, line in ipairs(raw_stat) do
			local status_char, filepath = line:match("^([A-Z%d]+)%s+(.+)$")
			if status_char and filepath then
				table.insert(edited_files, { status = status_char:sub(1, 1), filepath = filepath })
			end
		end

		if commit.hash ~= current_commit_hash then
			current_commit_hash = commit.hash
			current_target_file = target_filepath or (edited_files[1] and edited_files[1].filepath)
		elseif target_filepath then
			current_target_file = target_filepath
		end

		local raw_diff = {}
		if current_target_file then
			raw_diff = git_lines({ "show", "--color=never", commit.hash, "--", current_target_file }, active_cwd)
		else
			raw_diff = git_lines({ "show", "--color=never", commit.hash }, active_cwd)
		end
		local combined_diff_lines, l_kinds, r_kinds, col_w = diff.format_side_by_side_single(raw_diff, false, right_w)

		local content = {}
		table.insert(content, string.format(" 📌 Commit:      %s", commit.hash))
		table.insert(content, string.format(" 👤 Author:      %s", commit.author))
		table.insert(content, string.format(" 🕒 Date:        %s", commit.date))
		if commit.refs ~= "" then
			table.insert(content, string.format(" 🏷️ Refs:        %s", commit.refs))
		end
		table.insert(content, string.format(" 💬 Title:       %s", commit.subject))

		if #edited_files > 0 then
			table.insert(content, string.format(" 📁 Files Changed (%d):", #edited_files))
			for _, item in ipairs(edited_files) do
				local active_mark = item.filepath == current_target_file and "▶ " or "  "
				table.insert(
					content,
					string.format(" %s• [%s] %s", active_mark, item.status, item.filepath)
				)
			end
		end

		table.insert(
			content,
			" ──────────────────────────────────────────────────────────────────────────"
		)

		for _, line in ipairs(combined_diff_lines) do
			table.insert(content, line)
		end

		local save_cursor = nil
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			save_cursor = vim.api.nvim_win_get_cursor(right_win)
		end

		vim.bo[right_buf].modifiable = true
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, content)
		vim.bo[right_buf].modifiable = false

		local header_line_count = 6 + (#edited_files > 0 and (#edited_files + 1) or 0)
		diff.apply_highlights_side_by_side_single(right_buf, l_kinds, r_kinds, col_w, header_line_count)

		if save_cursor and save_cursor[1] <= #content then
			pcall(vim.api.nvim_win_set_cursor, right_win, save_cursor)
		end
	end

	local function on_right_cursor_moved()
		if is_closed or not (right_win and vim.api.nvim_win_is_valid(right_win)) then
			return
		end
		local cursor_row = vim.api.nvim_win_get_cursor(right_win)[1]
		local line_text = vim.api.nvim_buf_get_lines(right_buf, cursor_row - 1, cursor_row, false)[1] or ""

		local filepath = line_text:match("•%s*%[[A-Z%d]+%]%s+(.+)$")
		if filepath then
			filepath = filepath:gsub("^%s*", ""):gsub("%s*$", "")
			if filepath ~= current_target_file then
				update_commit_details(filepath)
			end
		end
	end

	local augroup = vim.api.nvim_create_augroup("KRSGitLogModalPreview", { clear = true })

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = left_buf,
		callback = function()
			vim.schedule(function()
				update_commit_details(nil)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = right_buf,
		callback = function()
			vim.schedule(on_right_cursor_moved)
		end,
	})

	update_commit_details(nil)

	local function resize_log_split(delta)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end

		local cur_r = M.current_left_ratio or load_saved_left_ratio(active_cwd)
		local new_r = math.max(0.20, math.min(0.80, cur_r + delta))
		M.current_left_ratio = tonumber(string.format("%.3f", new_r))
		save_left_ratio(M.root_dir or active_cwd, M.current_left_ratio)

		local total_w = math.floor(vim.o.columns * M.settings.width_ratio)
		local total_h = math.floor(vim.o.lines * M.settings.height_ratio)
		local start_r = math.floor((vim.o.lines - total_h) / 2)
		local start_c = math.floor((vim.o.columns - total_w) / 2)

		left_w = math.floor(total_w * M.current_left_ratio)
		right_w = total_w - left_w - 2

		vim.api.nvim_win_set_config(left_win, {
			relative = "editor",
			width = left_w,
			height = total_h,
			row = start_r,
			col = start_c,
		})
		vim.api.nvim_win_set_config(right_win, {
			relative = "editor",
			width = right_w,
			height = total_h,
			row = start_r,
			col = start_c + left_w + 2,
		})

		update_commit_details(current_target_file)
	end

	local ctrl_d = vim.api.nvim_replace_termcodes("<C-d>", true, false, true)
	local ctrl_u = vim.api.nvim_replace_termcodes("<C-u>", true, false, true)

	local function scroll_log_preview(direction)
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			vim.api.nvim_win_call(right_win, function()
				vim.cmd("normal! " .. (direction == "down" and ctrl_d or ctrl_u))
			end)
		end
	end

	local opts = { buffer = left_buf, noremap = true, silent = true, nowait = true }
	local right_opts = { buffer = right_buf, noremap = true, silent = true, nowait = true }

	local function checkout_commit()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = commits[row]
		if not commit then
			return
		end
		if
			vim.fn.confirm("⚠️ Checkout commit " .. commit.hash .. " (" .. commit.subject .. ")?", "&Yes\n&No", 2) ~= 1
		then
			return
		end
		close_log_modal()
		git_run({ "checkout", commit.hash }, function(ok, output)
			if ok then
				notify("✅ Checked out commit: " .. commit.hash)
			else
				notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
			end
			if M.is_open() and M.refresh then
				M.refresh()
			end
		end, active_cwd)
	end

	local function focus_log_left()
		if left_win and vim.api.nvim_win_is_valid(left_win) then
			vim.api.nvim_set_current_win(left_win)
		end
	end

	local function focus_log_right()
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			vim.api.nvim_set_current_win(right_win)
		end
	end

	local function toggle_log_focus()
		local target = vim.api.nvim_get_current_win() == left_win and right_win or left_win
		if target and vim.api.nvim_win_is_valid(target) then
			vim.api.nvim_set_current_win(target)
		end
	end

	local function handle_right_enter()
		if not (right_win and vim.api.nvim_win_is_valid(right_win) and right_buf and vim.api.nvim_buf_is_valid(right_buf)) then
			return
		end
		local cursor_line = vim.api.nvim_win_get_cursor(right_win)[1]
		local line_text = vim.api.nvim_buf_get_lines(right_buf, cursor_line - 1, cursor_line, false)[1] or ""

		local filepath = line_text:match("•%s*%[[A-Z%d]+%]%s+(.+)$")
		if filepath then
			filepath = filepath:gsub("^%s*", ""):gsub("%s*$", "")
			M.open_diff_modal(filepath, nil, active_cwd)
			return
		end

		toggle_log_focus()
	end

	local function current_right_file()
		if not (right_win and vim.api.nvim_win_is_valid(right_win) and right_buf and vim.api.nvim_buf_is_valid(right_buf)) then
			return nil
		end
		local cursor_line = vim.api.nvim_win_get_cursor(right_win)[1]
		local line_text = vim.api.nvim_buf_get_lines(right_buf, cursor_line - 1, cursor_line, false)[1] or ""
		local filepath = line_text:match("^%s*•%s*%[[A-Z%d]+%]%s+(.+)$") or line_text:match("^%s*•%s*(.+)$")
		if filepath then
			return filepath:gsub("^%s*", ""):gsub("%s*$", "")
		end
		return nil
	end

	local function open_right_file_diff()
		local filepath = current_right_file()
		if filepath then
			M.open_diff_modal(filepath, nil, active_cwd)
		end
	end

	local function handle_log_shift_enter()
		local filepath = current_right_file()
		if filepath then
			close_log_modal()
			M.open_file_in_tab(filepath, active_cwd)
		end
	end

	-- Checkout is mapped strictly to Shift+K (K)
	vim.keymap.set("n", "K", checkout_commit, opts)

	-- Focus switching (<CR>, <Tab>, <C-h>, <C-l>)
	vim.keymap.set("n", "<CR>", focus_log_right, opts)
	vim.keymap.set("n", "<CR>", handle_right_enter, right_opts)
	vim.keymap.set("n", "d", open_right_file_diff, right_opts)

	for _, key in ipairs(M.settings.keys.open_tab) do
		vim.keymap.set({ "n", "v", "i" }, key, handle_log_shift_enter, opts)
		vim.keymap.set({ "n", "v", "i" }, key, handle_log_shift_enter, right_opts)
	end

	for _, key in ipairs({ "<C-h>", "<C-H>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_log_left, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_log_left, right_opts)
	end
	for _, key in ipairs({ "<C-l>", "<C-L>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_log_right, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_log_right, right_opts)
	end

	vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", toggle_log_focus, opts)
	vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", toggle_log_focus, right_opts)

	-- Preview scrolling (<C-S-j>, <C-S-k>, <C-j>, <C-k>)
	for _, key in ipairs(M.settings.keys.scroll_down) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() scroll_log_preview("down") end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() scroll_log_preview("down") end, right_opts)
	end
	for _, key in ipairs(M.settings.keys.scroll_up) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() scroll_log_preview("up") end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() scroll_log_preview("up") end, right_opts)
	end

	-- Resizing (< / >, <C-Left> / <C-Right>)
	for _, key in ipairs(M.settings.keys.resize_left) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() resize_log_split(-0.03) end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() resize_log_split(-0.03) end, right_opts)
	end
	for _, key in ipairs(M.settings.keys.resize_right) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() resize_log_split(0.03) end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function() resize_log_split(0.03) end, right_opts)
	end

	-- Closing
	for _, key in ipairs(M.settings.keys.modal_close) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, close_log_modal, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, close_log_modal, right_opts)
	end
	vim.keymap.set("n", "l", close_log_modal, opts)
	vim.keymap.set("n", "L", close_log_modal, opts)
end

-- ============================================================================
-- DIFF MODAL (Side-by-Side Comparison: Left = Before, Right = After)
-- ============================================================================

--- Full-screen side-by-side diff viewer with file rotation and hunk navigation.
--- @param target_file string|nil File to open on. Defaults to the first changed file.
--- @param _target_type string|nil Unused; kept for call-site compatibility.
--- @param target_cwd string|nil Repository directory to view diffs for.
function M.open_diff_modal(target_file, _target_type, target_cwd)
	local prev_win = vim.api.nvim_get_current_win()
	local orig_cwd = vim.fn.getcwd()
	local active_cwd = target_cwd or (get_active_target() and get_active_target().full_path) or orig_cwd

	local info = M.get_git_info(active_cwd)
	if not info then
		notify("Not a valid Git repository", vim.log.levels.WARN)
		return
	end

	local files = {}
	for _, file_type in ipairs({ "staged", "unstaged", "untracked" }) do
		for _, file in ipairs(info[file_type]) do
			table.insert(files, { file = file, type = file_type })
		end
	end
	if #files == 0 then
		notify("No changed files to show diff", vim.log.levels.INFO)
		return
	end

	local index = 1
	for idx, item in ipairs(files) do
		if target_file and item.file == target_file then
			index = idx
			break
		end
	end

	diff.setup_highlights()

	local total_width = math.floor(vim.o.columns * M.settings.modal_width_ratio)
	local total_height = math.floor(vim.o.lines * M.settings.modal_height_ratio)
	local ratio = M.current_left_ratio or load_saved_left_ratio(active_cwd)
	local left_width = math.floor(total_width * ratio)
	local right_width = total_width - left_width - 2
	local start_row = math.floor((vim.o.lines - total_height) / 2)
	local start_col = math.floor((vim.o.columns - total_width) / 2)

	local z_index = require("krs.core.z_index")
	local diff_z = z_index.next_zindex("git_center_diff", { parent = "git_center", offset = 40 })

	local left_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[left_buf].buftype = "nofile"
	vim.bo[left_buf].bufhidden = "wipe"
	vim.bo[left_buf].swapfile = false

	local left_win = vim.api.nvim_open_win(left_buf, true, {
		relative = "editor",
		width = left_width,
		height = total_height,
		row = start_row,
		col = start_col,
		style = "minimal",
		border = "rounded",
		zindex = diff_z,
		title = " 🔴 BEFORE (Old) ",
		title_pos = "center",
	})

	local right_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[right_buf].buftype = "nofile"
	vim.bo[right_buf].bufhidden = "wipe"
	vim.bo[right_buf].swapfile = false

	local right_win = vim.api.nvim_open_win(right_buf, false, {
		relative = "editor",
		width = right_width,
		height = total_height,
		row = start_row,
		col = start_col + left_width + 2,
		style = "minimal",
		border = "rounded",
		zindex = diff_z,
		title = " 🟢 AFTER (New) ",
		title_pos = "center",
	})

	z_index.register("git_center_diff", { left_win, right_win }, { parent = "git_center", offset = 40, zindex = diff_z })

	M.diff_modal_win = left_win
	M.diff_modal_buf = left_buf

	for _, w in ipairs({ left_win, right_win }) do
		vim.api.nvim_set_option_value("number", true, { win = w })
		vim.api.nvim_set_option_value("wrap", false, { win = w })
		vim.api.nvim_set_option_value("scrollbind", true, { win = w })
		vim.api.nvim_set_option_value("cursorbind", true, { win = w })
	end

	--- Renders file `idx`
	local function render(idx)
		index = ((idx - 1) % #files) + 1
		local item = files[index]

		local raw_lines, is_untracked = raw_diff_for(item.file, item.type, active_cwd)
		local l_lines, l_kinds, r_lines, r_kinds = diff.format_side_by_side_dual(raw_lines, is_untracked)

		local label = item.type == "staged" and "🟢 Staged"
			or (item.type == "unstaged" and "🔴 Unstaged" or "❓ Untracked")

		pcall(vim.api.nvim_win_set_config, left_win, {
			title = string.format(" 🔴 BEFORE (%d/%d): %s [%s] | [Ctrl+h/l]: Focus ", index, #files, item.file, label),
			title_pos = "center",
		})
		pcall(vim.api.nvim_win_set_config, right_win, {
			title = string.format(
				" 🟢 AFTER (%d/%d): %s | [q/Esc]: Close | [Tab/S-Tab]: Switch File | [Ctrl+h/l]: Focus ",
				index,
				#files,
				item.file
			),
			title_pos = "center",
		})

		vim.bo[left_buf].modifiable = true
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, l_lines)
		vim.bo[left_buf].modifiable = false

		vim.bo[right_buf].modifiable = true
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, r_lines)
		vim.bo[right_buf].modifiable = false

		diff.apply_highlights_side_by_side_dual(left_buf, l_kinds, right_buf, r_kinds, item.file)

		pcall(vim.api.nvim_win_set_cursor, left_win, { 1, 0 })
		pcall(vim.api.nvim_win_set_cursor, right_win, { 1, 0 })
	end

	render(index)

	local is_closed = false
	local function close_modal()
		if is_closed then
			return
		end
		is_closed = true
		M.diff_modal_win, M.diff_modal_buf = nil, nil
		ui.close(left_win)
		ui.close(right_win)
		if orig_cwd and vim.fn.isdirectory(orig_cwd) == 1 then
			pcall(vim.fn.chdir, orig_cwd)
		end
		if prev_win and vim.api.nvim_win_is_valid(prev_win) then
			pcall(vim.api.nvim_set_current_win, prev_win)
		elseif M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
			pcall(vim.api.nvim_set_current_win, M.main_win)
		end
	end

	local function focus_diff_left()
		if left_win and vim.api.nvim_win_is_valid(left_win) then
			vim.api.nvim_set_current_win(left_win)
		end
	end

	local function focus_diff_right()
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			vim.api.nvim_set_current_win(right_win)
		end
	end

	local ctrl_d = vim.api.nvim_replace_termcodes("<C-d>", true, false, true)
	local ctrl_u = vim.api.nvim_replace_termcodes("<C-u>", true, false, true)

	local function scroll_diff(direction)
		local cur = vim.api.nvim_get_current_win()
		if cur and vim.api.nvim_win_is_valid(cur) then
			vim.api.nvim_win_call(cur, function()
				vim.cmd("normal! " .. (direction == "down" and ctrl_d or ctrl_u))
			end)
		end
	end

	local function resize_modal_split(delta)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end

		local cur_r = M.current_left_ratio or load_saved_left_ratio(active_cwd)
		local new_r = math.max(0.20, math.min(0.80, cur_r + delta))
		M.current_left_ratio = tonumber(string.format("%.3f", new_r))
		save_left_ratio(M.root_dir or active_cwd, M.current_left_ratio)

		local total_w = math.floor(vim.o.columns * M.settings.modal_width_ratio)
		local total_h = math.floor(vim.o.lines * M.settings.modal_height_ratio)
		local start_r = math.floor((vim.o.lines - total_h) / 2)
		local start_c = math.floor((vim.o.columns - total_w) / 2)

		left_width = math.floor(total_w * M.current_left_ratio)
		right_width = total_w - left_width - 2

		pcall(vim.api.nvim_win_set_config, left_win, {
			relative = "editor",
			width = left_width,
			height = total_h,
			row = start_r,
			col = start_c,
		})
		pcall(vim.api.nvim_win_set_config, right_win, {
			relative = "editor",
			width = right_width,
			height = total_h,
			row = start_r,
			col = start_c + left_width + 2,
		})

		render(index)
	end

	for _, win in ipairs({ left_win, right_win }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = close_modal,
		})
	end

	for _, b in ipairs({ left_buf, right_buf }) do
		local opts = { buffer = b, noremap = true, silent = true, nowait = true }
		for _, key in ipairs(M.settings.keys.modal_close) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, close_modal, opts)
		end

		local function handle_diff_shift_enter()
			local item = files[index]
			if item and item.file then
				close_modal()
				M.open_file_in_tab(item.file, active_cwd)
			end
		end

		for _, key in ipairs(M.settings.keys.open_tab) do
			vim.keymap.set({ "n", "v", "i" }, key, handle_diff_shift_enter, opts)
		end

		for _, key in ipairs({ "<C-h>", "<C-H>" }) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, focus_diff_left, opts)
		end
		for _, key in ipairs({ "<C-l>", "<C-L>" }) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, focus_diff_right, opts)
		end

		for _, key in ipairs(M.settings.keys.scroll_down) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function() scroll_diff("down") end, opts)
		end
		for _, key in ipairs(M.settings.keys.scroll_up) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function() scroll_diff("up") end, opts)
		end

		for _, key in ipairs({ "<Tab>", "]" }) do
			vim.keymap.set("n", key, function()
				render(index + 1)
			end, opts)
		end
		for _, key in ipairs({ "<S-Tab>", "[" }) do
			vim.keymap.set("n", key, function()
				render(index - 1)
			end, opts)
		end

		for _, key in ipairs(M.settings.keys.resize_left) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function()
				resize_modal_split(-0.03)
			end, opts)
		end
		for _, key in ipairs(M.settings.keys.resize_right) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function()
				resize_modal_split(0.03)
			end, opts)
		end

		local function jump_hunk(step)
			local win = vim.api.nvim_get_current_win()
			local current = vim.api.nvim_win_get_cursor(win)[1]
			local last = step > 0 and vim.api.nvim_buf_line_count(b) or 1

			for line = current + step, last, step do
				local text = vim.api.nvim_buf_get_lines(b, line - 1, line, false)[1] or ""
				if text:match("─── Hunk") or text:match("^@@") then
					pcall(vim.api.nvim_win_set_cursor, left_win, { line, 0 })
					pcall(vim.api.nvim_win_set_cursor, right_win, { line, 0 })
					return
				end
			end
		end

		vim.keymap.set("n", "]c", function()
			jump_hunk(1)
		end, opts)
		vim.keymap.set("n", "[c", function()
			jump_hunk(-1)
		end, opts)
	end
end

-- ============================================================================
-- MAIN PANEL
-- ============================================================================

--- Opens the Git Center. Calling it while open closes it, which is what makes
--- the same key a toggle.
function M.open_git_center()
	if M.is_open() then
		M.close_git_center()
		return
	end

	local root = path_util.normalize(project.root() or vim.fn.getcwd())
	if not git.is_repository(root) then
		notify("Current directory is not a valid Git repository", vim.log.levels.WARN, "Git Center (KRS)")
		return
	end

	M.root_dir = root

	-- Root is the active tab far more often than not, so its status is
	-- fetched right away, before the (usually cached, occasionally spawned)
	-- submodule list is resolved. `git.spawn`-based calls do not block until
	-- `:wait()`, so starting this first means it runs alongside the
	-- submodule discovery below instead of after it.
	local root_status_handle = status.info_start(root)

	local submodules_targets, finish_submodules = submodules.list_start(root)
	M.submodules = submodules_targets or finish_submodules()

	local saved_tab_path = load_saved_active_tab(root)
	M.active_submodule_idx = 1
	if saved_tab_path then
		for idx, entry in ipairs(M.submodules) do
			if entry.path == saved_tab_path then
				M.active_submodule_idx = idx
				break
			end
		end
	end

	local active_target = get_active_target()
	local info
	if active_target and active_target.is_secondary then
		info = M.get_git_info()
	elseif active_target and active_target.full_path == root then
		info = status.info_finish(root_status_handle)
	else
		info = M.get_git_info(active_target and active_target.full_path)
	end
	if not info then
		notify("Cannot read Git status for " .. active_target.name, vim.log.levels.WARN, "Git Center (KRS)")
		return
	end

	if active_target and active_target.path then
		M.submodule_statuses[active_target.path] = {
			has_changes = info.has_changes or (#info.staged + #info.unstaged + #info.untracked > 0),
			behind = info.behind or 0,
			ahead = info.ahead or 0,
		}
	end

	diff.setup_highlights()
	M.diff_cache = {}

	-- ------------------------------------------------------------------
	-- Windows
	-- ------------------------------------------------------------------
	M.current_left_ratio = load_saved_left_ratio(root)
	local total_width = math.floor(vim.o.columns * M.settings.width_ratio)
	local total_height = math.floor(vim.o.lines * M.settings.height_ratio)
	local left_width = math.floor(total_width * M.current_left_ratio)
	local right_width = total_width - left_width - 2
	local start_row = math.max(2, math.floor((vim.o.lines - total_height) / 2))
	local start_col = math.floor((vim.o.columns - total_width) / 2)

	local tab_buf = vim.api.nvim_create_buf(false, true)
	M.tab_buf = tab_buf
	vim.bo[tab_buf].buftype = "nofile"
	vim.bo[tab_buf].bufhidden = "wipe"
	vim.bo[tab_buf].swapfile = false

	local main_buf = vim.api.nvim_create_buf(false, true)
	M.main_buf = main_buf
	vim.bo[main_buf].buftype = "nofile"
	vim.bo[main_buf].bufhidden = "wipe"
	vim.bo[main_buf].swapfile = false

	local z_index = require("krs.core.z_index")
	local base_z = z_index.next_zindex("git_center")

	M.main_win = vim.api.nvim_open_win(main_buf, true, {
		relative = "editor",
		width = left_width,
		height = total_height,
		row = start_row,
		col = start_col,
		style = "minimal",
		border = "rounded",
		zindex = base_z,
		title = " 🐙 Git Center (Ctrl+h/l or Alt+h/l Tabs/Focus | </> Resize | Ctrl+Shift+J/K Preview | Esc Close) ",
		title_pos = "center",
	})

	pcall(vim.cmd, "stopinsert")

	M.tab_win = vim.api.nvim_open_win(tab_buf, false, {
		relative = "editor",
		width = left_width + 2,
		height = 1,
		row = start_row - 1,
		col = start_col - 1,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = base_z + 10,
	})

	local preview_buf = vim.api.nvim_create_buf(false, true)
	M.preview_buf = preview_buf
	vim.bo[preview_buf].buftype = "nofile"
	vim.bo[preview_buf].bufhidden = "wipe"
	vim.bo[preview_buf].swapfile = false

	M.preview_win = vim.api.nvim_open_win(preview_buf, false, {
		relative = "editor",
		width = right_width,
		height = total_height,
		row = start_row,
		col = start_col + left_width + 2,
		style = "minimal",
		border = "rounded",
		zindex = base_z,
		title = " 👁️ VSCode Live Diff (+ / -) | Ctrl+Shift+J/K: Scroll Text ",
		title_pos = "center",
	})

	z_index.register("git_center", { M.main_win, M.preview_win }, { zindex = base_z })
	z_index.register("git_center", M.tab_win, { offset = 10, zindex = base_z + 10 })

	vim.api.nvim_set_option_value("number", true, { win = M.preview_win })
	vim.api.nvim_set_option_value("wrap", false, { win = M.preview_win })

	-- Closing the panel by any other means still has to clean up the preview and state.
	for _, win in ipairs({ M.main_win, M.preview_win, M.tab_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_create_autocmd("WinClosed", {
				pattern = tostring(win),
				once = true,
				callback = function()
					vim.schedule(M.close_git_center)
				end,
			})
		end
	end

	render_tab_bar(left_width)

	local opts_tab = { buffer = tab_buf, silent = true, noremap = true }
	vim.keymap.set("n", "<LeftMouse>", function()
		local mousepos = vim.fn.getmousepos()
		local col = mousepos.column - start_col
		for _, range in ipairs(M.tab_click_ranges or {}) do
			if col >= range.start_col and col < range.end_col then
				if M.active_submodule_idx ~= range.idx then
					M.active_submodule_idx = range.idx
					local target = M.submodules[M.active_submodule_idx]
					if target then
						save_active_tab(M.root_dir, target.path)
						notify("Switched to repository: " .. target.name)
					end
					M.diff_cache = {}
					if M.refresh then
						M.refresh()
					end
				end
				break
			end
		end
	end, opts_tab)

	local lines, line_map, section_lines = build_panel_content(info, left_width)
	M.line_map = line_map

	vim.bo[main_buf].modifiable = true
	vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = main_buf })
	vim.api.nvim_set_option_value("cursorline", true, { win = M.main_win })
	vim.bo[main_buf].modifiable = false
	vim.bo[preview_buf].modifiable = false

	-- ------------------------------------------------------------------
	-- Live preview
	-- ------------------------------------------------------------------
	local preview_timer = nil

	--- Re-renders the preview shortly after the cursor settles.
	local function update_preview()
		if preview_timer then
			preview_timer:stop()
			if not preview_timer:is_closing() then
				preview_timer:close()
			end
			preview_timer = nil
		end

		preview_timer = vim.uv.new_timer()
		preview_timer:start(
			M.settings.preview_debounce_ms,
			0,
			vim.schedule_wrap(function()
				if not M.is_open() or not (M.preview_win and vim.api.nvim_win_is_valid(M.preview_win)) then
					return
				end

				local row = vim.api.nvim_win_get_cursor(M.main_win)[1]
				local item = M.line_map[row]

				vim.bo[preview_buf].modifiable = true
				if not item or not item.file then
					vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {
						" 💡 Select a staged or unstaged file to view diff.",
					})
					vim.bo[preview_buf].modifiable = false
					vim.api.nvim_buf_clear_namespace(preview_buf, diff.namespace, 0, -1)
					vim.api.nvim_buf_clear_namespace(preview_buf, diff.ts_namespace, 0, -1)
					return
				end

				local cur_target = get_active_target()
				local cache_key = cur_target.path .. ":" .. item.type .. ":" .. item.file
				if not M.diff_cache[cache_key] then
					local raw_lines, is_untracked = raw_diff_for(item.file, item.type, cur_target.full_path)
					local p_width = (M.preview_win and vim.api.nvim_win_is_valid(M.preview_win))
							and vim.api.nvim_win_get_width(M.preview_win)
						or right_width
					local formatted, l_kinds, r_kinds, col_w = diff.format_side_by_side_single(raw_lines, is_untracked, p_width)
					M.diff_cache[cache_key] =
						{ lines = formatted, l_kinds = l_kinds, r_kinds = r_kinds, col_w = col_w, file = item.file }
				end

				local cached = M.diff_cache[cache_key]
				vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, cached.lines)
				vim.bo[preview_buf].modifiable = false
				diff.apply_highlights_side_by_side_single(preview_buf, cached.l_kinds, cached.r_kinds, cached.col_w)
			end)
		)
	end

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = vim.api.nvim_create_augroup("KRSGitCenterPreview", { clear = true }),
		buffer = main_buf,
		callback = update_preview,
	})
	update_preview()

	-- ------------------------------------------------------------------
	-- Actions
	-- ------------------------------------------------------------------

	--- Redraws the panel in place -- no window is closed, so there is no flicker.
	--- @param force_clear_cache boolean|nil
	local function refresh(force_clear_cache)
		if force_clear_cache then
			M.submodule_statuses = {}
			M.fetching_submodules = {}
		end

		local cur_target = get_active_target()
		local current = M.get_git_info(cur_target.full_path)
		if not current or not M.is_open() then
			return
		end

		if cur_target and cur_target.path then
			M.submodule_statuses[cur_target.path] = {
				has_changes = current.has_changes or (#current.staged + #current.unstaged + #current.untracked > 0),
				behind = current.behind or 0,
				ahead = current.ahead or 0,
			}
		end

		local l_width = (M.main_win and vim.api.nvim_win_is_valid(M.main_win)) and vim.api.nvim_win_get_width(M.main_win)
			or left_width
		local new_lines, new_line_map, new_sections = build_panel_content(current, l_width)
		M.line_map = new_line_map
		section_lines = new_sections

		local cursor = vim.api.nvim_win_get_cursor(M.main_win)
		vim.bo[main_buf].modifiable = true
		vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, new_lines)
		vim.bo[main_buf].modifiable = false
		pcall(vim.api.nvim_win_set_cursor, M.main_win, { math.min(cursor[1], #new_lines), cursor[2] })

		render_tab_bar(l_width)

		M.diff_cache = {}
		update_preview()
	end
	M.refresh = refresh

	--- Switch active submodule tab by delta (-1 for left, 1 for right).
	--- @param delta integer -1 or 1
	local function switch_tab(delta)
		if not M.submodules or #M.submodules <= 1 then
			return
		end

		local count = #M.submodules
		local next_idx = M.active_submodule_idx + delta
		if next_idx < 1 then
			next_idx = count
		elseif next_idx > count then
			next_idx = 1
		end

		M.active_submodule_idx = next_idx
		local target = M.submodules[M.active_submodule_idx]
		if target then
			save_active_tab(M.root_dir, target.path)
			notify("Switched to repository: " .. target.name)
		end

		M.diff_cache = {}
		refresh()
	end

	--- File the cursor is on, or nil.
	--- @return table|nil item `{ type, file }`
	local function current_item()
		return M.line_map[vim.api.nvim_win_get_cursor(M.main_win)[1]]
	end

	--- Runs git synchronously in the active repository target.
	--- @param args string[] Arguments after `git`.
	--- @param cwd string|nil
	--- @return string[] output
	local function git_lines(args, cwd)
		local target = get_active_target()
		cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
		if target and target.is_secondary and target.repo_alias then
			local sec_ok, sec = pcall(require, "krs.git.secondary")
			if sec_ok and sec then
				return sec.lines(target.repo_alias, args, cwd)
			end
		end
		return git.lines(args, cwd)
	end

	--- Runs git asynchronously in the active repository target.
	--- @param args string[] Arguments after `git`.
	--- @param on_done function(ok, output)
	--- @param cwd string|nil
	local function git_run(args, on_done, cwd)
		local target = get_active_target()
		cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
		if target and target.is_secondary and target.repo_alias then
			local sec_ok, sec = pcall(require, "krs.git.secondary")
			if sec_ok and sec then
				sec.run(target.repo_alias, args, on_done, cwd)
				return
			end
		end
		git.run(args, on_done, cwd)
	end

	--- Unstaging changed spelling across git versions: `restore --staged` is the
	--- modern form, `reset HEAD` the fallback for older ones, `rm --cached` for fresh repos without HEAD.
	--- @param paths string[] Paths, or `{ "." }` for everything.
	local function unstage(paths)
		local cur_target = get_active_target()
		if cur_target and cur_target.is_secondary then
			local rm_args = { "rm", "--cached", "-r", "--" }
			vim.list_extend(rm_args, paths)
			git_lines(rm_args)
			return
		end

		local args = { "restore", "--staged", "--" }
		vim.list_extend(args, paths)
		local result = git_lines(args)

		local is_err = (#result > 0 and (result[1]:match("fatal") or result[1]:match("error")))
		if is_err then
			local fallback1 = { "reset", "HEAD", "--" }
			vim.list_extend(fallback1, paths)
			local res2 = git_lines(fallback1)
			if #res2 > 0 and (res2[1]:match("fatal") or res2[1]:match("error")) then
				local fallback2 = { "rm", "--cached", "-r", "--" }
				vim.list_extend(fallback2, paths)
				git_lines(fallback2)
			end
		end
	end

	--- Applies a staging action to every file inside the visual selection.
	--- @param action "stage"|"unstage"
	local function process_visual_selection(action)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

		vim.schedule(function()
			local first = vim.api.nvim_buf_get_mark(main_buf, "<")[1]
			local last = vim.api.nvim_buf_get_mark(main_buf, ">")[1]
			if first > last then
				first, last = last, first
			end

			local files = {}
			for row = first, last do
				local item = M.line_map[row]
				if item and item.file then
					table.insert(files, item.file)
				end
			end

			if #files > 0 then
				if action == "stage" then
					local args = { "add", "--" }
					vim.list_extend(args, files)
					git_lines(args)
				else
					unstage(files)
				end
			end
			refresh()
		end)
	end

	-- ------------------------------------------------------------------
	-- Keymaps
	-- ------------------------------------------------------------------
	local key_opts = { buffer = main_buf, noremap = true, silent = true, nowait = true }
	local preview_opts = { buffer = preview_buf, noremap = true, silent = true, nowait = true }

	-- Tab switching keymaps (Alt+h / Alt+l)
	for _, key in ipairs(M.settings.keys.tab_prev) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(-1)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(-1)
		end, preview_opts)
	end
	for _, key in ipairs(M.settings.keys.tab_next) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(1)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(1)
		end, preview_opts)
	end

	-- Split resizing keymaps (< / >)
	for _, key in ipairs(M.settings.keys.resize_left) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(-0.03)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(-0.03)
		end, preview_opts)
	end
	for _, key in ipairs(M.settings.keys.resize_right) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(0.03)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(0.03)
		end, preview_opts)
	end

	--- Scrolls the preview with a native half-page motion, so it behaves exactly
	--- like <C-d>/<C-u> would inside that window.
	local ctrl_d = vim.api.nvim_replace_termcodes("<C-d>", true, false, true)
	local ctrl_u = vim.api.nvim_replace_termcodes("<C-u>", true, false, true)

	local function scroll_preview(direction)
		if not (M.preview_win and vim.api.nvim_win_is_valid(M.preview_win)) then
			return
		end
		vim.api.nvim_win_call(M.preview_win, function()
			vim.cmd("normal! " .. (direction == "down" and ctrl_d or ctrl_u))
		end)
	end

	for _, key in ipairs(M.settings.keys.scroll_down) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("down")
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("down")
		end, preview_opts)
	end
	for _, key in ipairs(M.settings.keys.scroll_up) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("up")
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("up")
		end, preview_opts)
	end

	local function focus_left()
		if M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
			vim.api.nvim_set_current_win(M.main_win)
		end
	end

	local function focus_right()
		if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
			vim.api.nvim_set_current_win(M.preview_win)
		end
	end

	local function handle_left_nav()
		if vim.api.nvim_get_current_win() == M.preview_win then
			focus_left()
		else
			switch_tab(-1)
		end
	end

	local function handle_right_nav()
		if vim.api.nvim_get_current_win() == M.main_win then
			focus_right()
		else
			switch_tab(1)
		end
	end

	local function toggle_focus()
		local target = vim.api.nvim_get_current_win() == M.main_win and M.preview_win or M.main_win
		if target and vim.api.nvim_win_is_valid(target) then
			vim.api.nvim_set_current_win(target)
		end
	end

	for _, key in ipairs({ "<C-h>", "<C-H>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, handle_left_nav, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, handle_left_nav, preview_opts)
	end
	for _, key in ipairs({ "<C-l>", "<C-L>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, handle_right_nav, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, handle_right_nav, preview_opts)
	end

	local function handle_main_enter()
		local item = current_item()
		if item and item.file then
			M.open_diff_modal(item.file, item.type, get_active_target().full_path)
		else
			toggle_focus()
		end
	end

	vim.keymap.set("n", "<CR>", handle_main_enter, key_opts)

	local function handle_main_shift_enter()
		local item = current_item()
		if item and item.file then
			M.open_file_in_tab(item.file, get_active_target().full_path, item.type)
		end
	end

	for _, key in ipairs(M.settings.keys.open_tab) do
		vim.keymap.set({ "n", "v", "i" }, key, handle_main_shift_enter, key_opts)
		vim.keymap.set({ "n", "v", "i" }, key, handle_main_shift_enter, preview_opts)
	end

	vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", toggle_focus, key_opts)
	vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", toggle_focus, preview_opts)

	for _, key in ipairs(M.settings.keys.close) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, M.close_git_center, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, M.close_git_center, preview_opts)
	end

	for section = 1, 4 do
		vim.keymap.set("n", tostring(section), function()
			if section_lines[section] and M.is_open() then
				pcall(vim.api.nvim_win_set_cursor, M.main_win, { section_lines[section], 0 })
			end
		end, key_opts)
	end

	vim.keymap.set("n", "b", function()
		M.open_branch_modal(get_active_target().full_path)
	end, key_opts)

	vim.keymap.set("n", "l", function()
		M.open_commit_log_modal(get_active_target().full_path)
	end, key_opts)

	vim.keymap.set("n", "L", function()
		M.open_commit_log_modal(get_active_target().full_path)
	end, key_opts)

	--- Commit form fields, each edited through the shared input modal.
	local commit_fields = {
		{ key = "c", field = "title", label = "Commit Title" },
		{ key = "m", field = "description", label = "Commit Description" },
		{ key = "t", field = "tag", label = "Optional Tag (e.g. v1.0.0)" },
	}
	for _, entry in ipairs(commit_fields) do
		vim.keymap.set("n", entry.key, function()
			require("plugins.krs.input_modal").open({
				label = entry.label,
				default_value = M.commit_data[entry.field],
				relative = "editor",
				callback = function(ok, input)
					if ok and input then
						if entry.field == "title" or entry.field == "tag" then
							input = input:gsub("[\r\n]+", " "):gsub("^%s*", ""):gsub("%s*$", "")
						end
						M.commit_data[entry.field] = input
						refresh()
					end
				end,
			})
		end, key_opts)
	end

	vim.keymap.set("n", "s", function()
		local item = current_item()
		if item and (item.type == "unstaged" or item.type == "untracked") then
			git_lines({ "add", "--", item.file })
			refresh()
			notify("🟢 Staged: " .. item.file)
		elseif item and item.type == "staged" then
			notify("File is already staged", vim.log.levels.WARN)
		end
	end, key_opts)

	vim.keymap.set("v", "s", function()
		process_visual_selection("stage")
	end, key_opts)

	vim.keymap.set({ "n", "v" }, "S", function()
		local cur_target = get_active_target()
		local current = M.get_git_info(cur_target.full_path)
		if current and (#current.unstaged > 0 or #current.untracked > 0) then
			git_lines({ "add", "-A" })
			refresh()
			notify("🟢 Staged all files in " .. cur_target.name)
		else
			notify("ℹ️ Nothing to stage: working tree is clean.", vim.log.levels.WARN)
		end
	end, key_opts)

	vim.keymap.set("n", "u", function()
		local item = current_item()
		if item and item.type == "staged" then
			unstage({ item.file })
			refresh()
			notify("🔴 Unstaged: " .. item.file)
		elseif item and (item.type == "unstaged" or item.type == "untracked") then
			notify("File is not staged", vim.log.levels.WARN)
		else
			notify("Please select a staged file (✓) to unstage", vim.log.levels.WARN)
		end
	end, key_opts)

	vim.keymap.set("v", "u", function()
		process_visual_selection("unstage")
	end, key_opts)

	vim.keymap.set({ "n", "v" }, "U", function()
		local cur_target = get_active_target()
		unstage({ "." })
		refresh()
		notify("🔴 Unstaged all files in " .. cur_target.name)
	end, key_opts)

	vim.keymap.set("n", "C", function()
		if M.commit_data.title == "" then
			notify("Please enter a commit title first with [c]", vim.log.levels.WARN)
			return
		end

		local cur_target = get_active_target()
		local args = { "commit", "-m", M.commit_data.title }
		if M.commit_data.description ~= "" then
			table.insert(args, "-m")
			table.insert(args, M.commit_data.description)
		end

		git_run(args, function(ok, output)
			if ok then
				notify("🚀 Commit successful:\n" .. (output ~= "" and output or "Commit created"), nil, M.settings.control_title)
				if M.commit_data.tag ~= "" then
					git_lines({ "tag", M.commit_data.tag })
					notify("🏷️ Tag created: " .. M.commit_data.tag)
				end
				M.commit_data = { title = "", description = "", tag = "" }
			else
				notify(
					"❌ Commit failed:\n" .. (output ~= "" and output or "Unknown error"),
					vim.log.levels.ERROR,
					M.settings.control_title
				)
			end
			refresh()
		end, cur_target.full_path)
	end, key_opts)

	vim.keymap.set("n", "d", function()
		local item = current_item()
		M.open_diff_modal(item and item.file or nil, item and item.type or nil, get_active_target().full_path)
	end, key_opts)

	vim.keymap.set("n", "r", function()
		local item = current_item()
		if not (item and item.file) then
			notify("Please place cursor over a file to restore", vim.log.levels.WARN)
			return
		end
		if vim.fn.confirm("⚠️ Discard changes / Restore '" .. item.file .. "'?", "&Yes\n&No", 2) ~= 1 then
			return
		end

		local cur_target = get_active_target()
		local full_file_path = path_util.join(cur_target.full_path, item.file)

		if item.type == "staged" then
			unstage({ item.file })
			git_lines({ "restore", "--", item.file })
		elseif item.type == "unstaged" then
			git_lines({ "restore", "--", item.file })
		elseif vim.fn.isdirectory(full_file_path) == 1 then
			vim.fn.delete(full_file_path, "rf")
		else
			os.remove(full_file_path)
		end

		refresh()
		notify("↺ Restored: " .. item.file)
	end, key_opts)

	vim.keymap.set("n", "R", function()
		local row = vim.api.nvim_win_get_cursor(M.main_win)[1]
		local item = M.line_map[row]

		-- Either the file under the cursor is staged, or the cursor sits inside
		-- section 2 (the staged block) with no file selected.
		local in_staged_section = (item and item.type == "staged")
			or (row >= (section_lines[2] or 0) and row < (section_lines[3] or 999))

		local label = in_staged_section and "STAGED FILES" or "UNSTAGED & UNTRACKED FILES"
		if vim.fn.confirm("⚠️ RESTORE ALL " .. label .. "? Changes will be permanently lost!", "&Yes\n&No", 2) ~= 1 then
			return
		end

		if in_staged_section then
			unstage({ "." })
			git_lines({ "restore", "." })
		else
			git_lines({ "restore", "." })
			git_lines({ "clean", "-fd" })
		end

		refresh()
		notify("↺ Restored all " .. label:lower())
	end, key_opts)

	vim.keymap.set("n", "P", function()
		local cur_target = get_active_target()
		local current = M.get_git_info(cur_target.full_path)
		local branch = current and current.branch or "HEAD"

		if
			vim.fn.confirm(
				"🚀 Execute 'git push' for branch '" .. branch .. "' in " .. cur_target.name .. "?",
				"&Yes\n&No",
				1
			) ~= 1
		then
			return
		end

		--- Pushes `branch` to `remote/target`, optionally setting the upstream.
		local function perform_push(remote, target, set_upstream)
			notify("🚀 Pushing to " .. remote .. "/" .. target .. "...")

			local args = { "push" }
			if set_upstream then
				table.insert(args, "-u")
			end
			table.insert(args, remote)
			table.insert(args, branch .. ":" .. target)

			git_run(args, function(ok, output)
				if ok then
					notify("✅ Push successful to " .. remote .. "/" .. target .. "!", nil, M.settings.control_title)
				else
					notify(
						"❌ Push failed:\n" .. (output ~= "" and output or "Unknown error"),
						vim.log.levels.ERROR,
						M.settings.control_title
					)
				end
				refresh()
			end, cur_target.full_path)
		end

		local remotes = git_lines({ "remote" })
		if #remotes == 0 then
			require("plugins.krs.input_modal").open({
				label = "No remote found. Add remote URL (origin)",
				default_value = "",
				relative = "editor",
				callback = function(ok, url)
					if ok and url and url ~= "" then
						git_lines({ "remote", "add", "origin", url })
						perform_push("origin", branch, true)
					end
				end,
			})
			return
		end

		local remote = remotes[1] or "origin"

		local upstream = git_lines({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
		local has_upstream = #upstream > 0 and not upstream[1]:match("fatal") and not upstream[1]:match("error")

		if has_upstream then
			notify("🚀 Pushing to upstream...")
			git_run({ "push" }, function(ok, output)
				if ok then
					notify("✅ Push successful to remote repository!", nil, M.settings.control_title)
				else
					notify(
						"❌ Push failed:\n" .. (output ~= "" and output or "Unknown error"),
						vim.log.levels.ERROR,
						M.settings.control_title
					)
				end
				refresh()
			end, cur_target.full_path)
			return
		end

		-- No upstream yet: offer to create one, or to target an existing branch.
		git_lines({ "fetch", remote })

		local remote_branches = {}
		for _, line in ipairs(git_lines({ "branch", "-r" })) do
			local name = vim.trim(line)
			if name ~= "" and not name:match("%->") then
				table.insert(remote_branches, name)
			end
		end

		local choices = {
			"1. 🚀 Push and set upstream to "
				.. remote
				.. "/"
				.. branch
				.. " (git push -u "
				.. remote
				.. " "
				.. branch
				.. ")",
		}
		for index, name in ipairs(remote_branches) do
			table.insert(choices, string.format("%d. 🌿 Push to existing remote branch: %s", index + 1, name))
		end

		pcall(vim.ui.select, choices, {
			prompt = "No upstream branch set for '" .. branch .. "'. Select target branch:",
		}, function(choice, index)
			if not choice or not index then
				return
			end
			if index == 1 then
				perform_push(remote, branch, true)
				return
			end

			local chosen = remote_branches[index - 1]
			if chosen then
				perform_push(remote, chosen:gsub("^[^/]+/", ""), true)
			end
		end)
	end, key_opts)

	for _, key in ipairs(M.settings.keys.refresh) do
		vim.keymap.set("n", key, function()
			refresh(true)
		end, key_opts)
	end
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers the user commands and the global keymaps.
--- Runs from the lazy spec's `config`, i.e. once neogit is loaded.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	pcall(vim.api.nvim_create_user_command, "GitCenter", function()
		M.toggle_git_center()
	end, { desc = "Toggle Git Control Center" })

	pcall(vim.api.nvim_create_user_command, "GitStageAll", function()
		M.stage_all_with_modal()
	end, { desc = "Stage All Unstaged & Untracked Changes with Modal Confirmation" })

	pcall(vim.api.nvim_create_user_command, "GitLog", function()
		M.open_commit_log_modal()
	end, { desc = "Open Git Commit Log & History Viewer" })

	pcall(vim.api.nvim_create_user_command, "GitHistory", function()
		M.open_commit_log_modal()
	end, { desc = "Open Git Commit Log & History Viewer" })

	--- Reloads this module from disk, for editing it without restarting nvim.
	local function reload()
		package.loaded["plugins.krs.git_center"] = nil
		_G.GitCenter = nil
		local reloaded = require("plugins.krs.git_center")
		if reloaded and reloaded.config then
			reloaded.config()
		end
		notify("🐙 Git Control Center reloaded successfully!")
	end

	for _, name in ipairs({ "GitCenterReload", "ReloadGitCenter" }) do
		pcall(vim.api.nvim_create_user_command, name, reload, { desc = "Reload Git Control Center" })
	end

	pcall(vim.api.nvim_create_user_command, "GitCenterToggleTabColors", function()
		M.toggle_colored_tab_indicators()
	end, { desc = "Toggle Git Center Colored Tab Indicators" })

	pcall(vim.api.nvim_create_user_command, "GitCenterToggle", function()
		M.toggle_git_center()
	end, { desc = "Toggle Git Control Center" })

	local function from_any_mode(fn)
		return function()
			local cur_buf = vim.api.nvim_get_current_buf()
			local is_term = vim.bo[cur_buf].buftype == "terminal" or vim.b[cur_buf].krs_is_multi_term
			local mode = vim.fn.mode()

			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end

			fn()

			if is_term and mode == "t" then
				vim.schedule(function()
					if vim.api.nvim_get_current_buf() == cur_buf then
						pcall(vim.cmd, "startinsert")
					end
				end)
			end
		end
	end

	for _, key in ipairs(M.settings.keys.toggle) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.toggle_git_center), {
			noremap = true,
			silent = true,
			desc = "Toggle Git Control Center",
		})
	end
	for _, key in ipairs(M.settings.keys.stage_all) do
		vim.keymap.set(
			{ "n", "i", "v", "t" },
			key,
			from_any_mode(function()
				M.stage_all_with_modal()
			end),
			{
				noremap = true,
				silent = true,
				desc = "Stage All Unstaged & Untracked Changes (Modal Confirmation)",
			}
		)
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.GitCenter = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_git_center",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "GitCenter", "GitCenterStage", "GitCenterCommit", "GitCenterPush", "GitCenterDiff" },
	keys = {
		{ "<C-S-g>", mode = { "n", "i", "v", "t" }, desc = "Open Git Control Center" },
		{ "<leader>gc", mode = { "n", "v" }, desc = "Open Git Control Center" },
		{ "<leader>gC", mode = { "n", "v" }, desc = "Open Git Control Center" },
		{ "<C-S-x>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<C-S-X>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<A-s>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<M-s>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<leader>gs", mode = { "n", "v" }, desc = "Stage All Git Changes" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"sindrets/diffview.nvim",
		"nvim-telescope/telescope.nvim",
	},
	config = M.setup,
}, { __index = M })
