-- ============================================================================
-- KRS PLUGIN: Git Center -- Panel & Window Controller
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local git = lazy_req("krs.git.cmd")
local status = lazy_req("krs.git.status")
local diff = lazy_req("krs.git.diff")
local submodules = lazy_req("krs.git.submodules")
local ui = lazy_req("krs.core.ui")
local project = lazy_req("krs.core.project")
local path_util = lazy_req("krs.core.path")
local config = require("plugins.krs.git.git_center.config")
local queries = require("plugins.krs.git.git_center.queries")
local render = require("plugins.krs.git.git_center.render")
local modals = require("plugins.krs.git.git_center.modals")

local M = {}

local notify = config.notify
local get_active_target = config.get_active_target
local load_saved_active_tab = config.load_saved_active_tab
local save_active_tab = config.save_active_tab
local load_saved_left_ratio = config.load_saved_left_ratio
local save_left_ratio = config.save_left_ratio
local git_lines = queries.git_lines
local git_run = queries.git_run

--- True when the Git Center is on screen.
--- @return boolean
function M.is_open()
	return (config.main_win ~= nil and vim.api.nvim_win_is_valid(config.main_win))
		or (config.preview_win ~= nil and vim.api.nvim_win_is_valid(config.preview_win))
		or (config.tab_win ~= nil and vim.api.nvim_win_is_valid(config.tab_win))
		or (config.diff_modal_win ~= nil and vim.api.nvim_win_is_valid(config.diff_modal_win))
end

--- Resizes the horizontal split between the left panel and preview pane.
--- Persists the preference immediately so it is remembered across sessions.
--- @param delta number Fraction to adjust left ratio (e.g. -0.03 or 0.03).
function M.resize_split(delta)
	if not M.is_open() or not (config.main_win and vim.api.nvim_win_is_valid(config.main_win)) then
		return
	end

	local cur_ratio = config.current_left_ratio or config.settings.left_ratio
	local new_ratio = ui.resize_dual_panel({
		left_win = config.main_win,
		right_win = config.preview_win,
		tab_win = config.tab_win,
		tab_full_width = true,
		delta = delta,
		left_ratio = cur_ratio,
		width_ratio = config.settings.width_ratio,
		height_ratio = config.settings.height_ratio,
		gap = 2,
		min_ratio = 0.20,
		max_ratio = 0.80,
	})

	config.current_left_ratio = new_ratio
	if config.root_dir then
		save_left_ratio(config.root_dir, config.current_left_ratio)
	end

	if config.refresh then
		pcall(config.refresh)
	end
end

local is_closing = false

--- Closes every window this module owns and forgets their handles.
function M.close_git_center()
	if is_closing then
		return
	end
	is_closing = true
	config.refresh = nil
	local diff_win, prev_win, tab_win, main_win = config.diff_modal_win, config.preview_win, config.tab_win, config.main_win
	config.main_win, config.main_buf = nil, nil
	config.preview_win, config.preview_buf = nil, nil
	config.tab_win, config.tab_buf = nil, nil
	config.diff_modal_win, config.diff_modal_buf = nil, nil

	ui.close(diff_win)
	ui.close(prev_win)
	ui.close(tab_win)
	ui.close(main_win)
	is_closing = false
end

--- Finds the 1-indexed line number of the first change in `file_path`.
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

--- Opens the Git Center.
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

	config.root_dir = root

	local root_status_handle = status.info_start(root)

	local submodules_targets, finish_submodules = submodules.list_start(root)
	config.submodules = submodules_targets or finish_submodules()

	local saved_tab_path = load_saved_active_tab(root)
	config.active_submodule_idx = 1
	if saved_tab_path then
		for idx, entry in ipairs(config.submodules) do
			if entry.path == saved_tab_path then
				config.active_submodule_idx = idx
				break
			end
		end
	end

	local active_target = get_active_target()
	local info
	if active_target and active_target.is_secondary then
		info = queries.get_git_info()
	elseif active_target and active_target.full_path == root then
		info = status.info_finish(root_status_handle)
	else
		info = queries.get_git_info(active_target and active_target.full_path)
	end
	if not info then
		notify("Cannot read Git status for " .. active_target.name, vim.log.levels.WARN, "Git Center (KRS)")
		return
	end

	if active_target and active_target.path then
		render.submodule_statuses[active_target.path] = {
			has_changes = info.has_changes or (#info.staged + #info.unstaged + #info.untracked > 0),
			behind = info.behind or 0,
			ahead = info.ahead or 0,
		}
	end

	diff.setup_highlights()
	config.diff_cache = {}

	config.current_left_ratio = load_saved_left_ratio(root)
	local total_width = math.floor(vim.o.columns * config.settings.width_ratio)
	local total_height = math.floor(vim.o.lines * config.settings.height_ratio)
	local left_width = math.floor(total_width * config.current_left_ratio)
	local right_width = total_width - left_width - 2
	local start_row = math.max(2, math.floor((vim.o.lines - total_height) / 2))
	local start_col = math.floor((vim.o.columns - total_width) / 2)

	local tab_buf = vim.api.nvim_create_buf(false, true)
	config.tab_buf = tab_buf
	vim.bo[tab_buf].buftype = "nofile"
	vim.bo[tab_buf].bufhidden = "wipe"
	vim.bo[tab_buf].swapfile = false

	local main_buf = vim.api.nvim_create_buf(false, true)
	config.main_buf = main_buf
	vim.bo[main_buf].buftype = "nofile"
	vim.bo[main_buf].bufhidden = "wipe"
	vim.bo[main_buf].swapfile = false

	local z_index = require("krs.core.z_index")
	local base_z = z_index.next_zindex("git_center")

	config.main_win = vim.api.nvim_open_win(main_buf, true, {
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

	config.tab_win = vim.api.nvim_open_win(tab_buf, false, {
		relative = "editor",
		width = total_width + 2,
		height = 1,
		row = start_row - 1,
		col = start_col - 1,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = base_z + 10,
	})

	local preview_buf = vim.api.nvim_create_buf(false, true)
	config.preview_buf = preview_buf
	vim.bo[preview_buf].buftype = "nofile"
	vim.bo[preview_buf].bufhidden = "wipe"
	vim.bo[preview_buf].swapfile = false

	config.preview_win = vim.api.nvim_open_win(preview_buf, false, {
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

	z_index.register("git_center", { config.main_win, config.preview_win }, { zindex = base_z })
	z_index.register("git_center", config.tab_win, { offset = 10, zindex = base_z + 10 })

	vim.api.nvim_set_option_value("number", true, { win = config.preview_win })
	vim.api.nvim_set_option_value("wrap", false, { win = config.preview_win })

	for _, win in ipairs({ config.main_win, config.preview_win, config.tab_win }) do
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

	render.render_tab_bar(total_width)

	local opts_tab = { buffer = tab_buf, silent = true, noremap = true }
	vim.keymap.set("n", "<LeftMouse>", function()
		local mousepos = vim.fn.getmousepos()
		local col = mousepos.column - start_col
		for _, range in ipairs(render.tab_click_ranges or {}) do
			if col >= range.start_col and col < range.end_col then
				if config.active_submodule_idx ~= range.idx then
					config.active_submodule_idx = range.idx
					local target = config.submodules[config.active_submodule_idx]
					if target then
						save_active_tab(config.root_dir, target.path)
						notify("Switched to repository: " .. target.name)
					end
					config.diff_cache = {}
					if config.refresh then
						config.refresh()
					end
				end
				break
			end
		end
	end, opts_tab)

	local lines, line_map, section_lines = render.build_panel_content(info, left_width)
	config.line_map = line_map

	vim.bo[main_buf].modifiable = true
	vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = main_buf })
	vim.api.nvim_set_option_value("cursorline", true, { win = config.main_win })
	vim.bo[main_buf].modifiable = false
	vim.bo[preview_buf].modifiable = false

	local preview_timer = nil

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
			config.settings.preview_debounce_ms,
			0,
			vim.schedule_wrap(function()
				if not M.is_open() or not (config.preview_win and vim.api.nvim_win_is_valid(config.preview_win)) then
					return
				end

				local row = vim.api.nvim_win_get_cursor(config.main_win)[1]
				local item = config.line_map[row]

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
				if not config.diff_cache[cache_key] then
					local raw_lines, is_untracked = queries.raw_diff_for(item.file, item.type, cur_target.full_path)
					local p_width = (config.preview_win and vim.api.nvim_win_is_valid(config.preview_win))
							and vim.api.nvim_win_get_width(config.preview_win)
						or right_width
					local formatted, l_kinds, r_kinds, col_w = diff.format_side_by_side_single(raw_lines, is_untracked, p_width)
					config.diff_cache[cache_key] =
						{ lines = formatted, l_kinds = l_kinds, r_kinds = r_kinds, col_w = col_w, file = item.file }
				end

				local cached = config.diff_cache[cache_key]
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

	local function refresh(force_clear_cache)
		if force_clear_cache then
			render.submodule_statuses = {}
			render.fetching_submodules = {}
		end

		local cur_target = get_active_target()
		local current = queries.get_git_info(cur_target.full_path)
		if not current or not M.is_open() then
			return
		end

		if cur_target and cur_target.path then
			render.submodule_statuses[cur_target.path] = {
				has_changes = current.has_changes or (#current.staged + #current.unstaged + #current.untracked > 0),
				behind = current.behind or 0,
				ahead = current.ahead or 0,
			}
		end

		local l_width = (config.main_win and vim.api.nvim_win_is_valid(config.main_win)) and vim.api.nvim_win_get_width(config.main_win)
			or left_width
		local new_lines, new_line_map, new_sections = render.build_panel_content(current, l_width)
		config.line_map = new_line_map
		section_lines = new_sections

		local cursor = vim.api.nvim_win_get_cursor(config.main_win)
		vim.bo[main_buf].modifiable = true
		vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, new_lines)
		vim.bo[main_buf].modifiable = false
		pcall(vim.api.nvim_win_set_cursor, config.main_win, { math.min(cursor[1], #new_lines), cursor[2] })

		render.render_tab_bar(math.floor(vim.o.columns * config.settings.width_ratio))

		config.diff_cache = {}
		update_preview()
	end
	config.refresh = refresh

	local function switch_tab(delta)
		if not config.submodules or #config.submodules <= 1 then
			return
		end

		local count = #config.submodules
		local next_idx = config.active_submodule_idx + delta
		if next_idx < 1 then
			next_idx = count
		elseif next_idx > count then
			next_idx = 1
		end

		config.active_submodule_idx = next_idx
		local target = config.submodules[config.active_submodule_idx]
		if target then
			save_active_tab(config.root_dir, target.path)
			notify("Switched to repository: " .. target.name)
		end

		config.diff_cache = {}
		refresh()
	end

	local function current_item()
		return config.line_map[vim.api.nvim_win_get_cursor(config.main_win)[1]]
	end

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
				local item = config.line_map[row]
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

	local key_opts = { buffer = main_buf, noremap = true, silent = true, nowait = true }
	local preview_opts = { buffer = preview_buf, noremap = true, silent = true, nowait = true }

	for _, key in ipairs(config.settings.keys.tab_prev) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(-1)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(-1)
		end, preview_opts)
	end
	for _, key in ipairs(config.settings.keys.tab_next) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(1)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			switch_tab(1)
		end, preview_opts)
	end

	for _, key in ipairs(config.settings.keys.resize_left) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(-0.03)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(-0.03)
		end, preview_opts)
	end
	for _, key in ipairs(config.settings.keys.resize_right) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(0.03)
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			M.resize_split(0.03)
		end, preview_opts)
	end

	local ctrl_d = vim.api.nvim_replace_termcodes("<C-d>", true, false, true)
	local ctrl_u = vim.api.nvim_replace_termcodes("<C-u>", true, false, true)

	local function scroll_preview(direction)
		if not (config.preview_win and vim.api.nvim_win_is_valid(config.preview_win)) then
			return
		end
		vim.api.nvim_win_call(config.preview_win, function()
			vim.cmd("normal! " .. (direction == "down" and ctrl_d or ctrl_u))
		end)
	end

	for _, key in ipairs(config.settings.keys.scroll_down) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("down")
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("down")
		end, preview_opts)
	end
	for _, key in ipairs(config.settings.keys.scroll_up) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("up")
		end, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_preview("up")
		end, preview_opts)
	end

	local function focus_left()
		if config.main_win and vim.api.nvim_win_is_valid(config.main_win) then
			vim.api.nvim_set_current_win(config.main_win)
		end
	end

	local function focus_right()
		if config.preview_win and vim.api.nvim_win_is_valid(config.preview_win) then
			vim.api.nvim_set_current_win(config.preview_win)
		end
	end

	local function handle_left_nav()
		if vim.api.nvim_get_current_win() == config.preview_win then
			focus_left()
		else
			switch_tab(-1)
		end
	end

	local function handle_right_nav()
		if vim.api.nvim_get_current_win() == config.main_win then
			focus_right()
		else
			switch_tab(1)
		end
	end

	local function toggle_focus()
		local target = vim.api.nvim_get_current_win() == config.main_win and config.preview_win or config.main_win
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
			modals.open_diff_modal(item.file, item.type, get_active_target().full_path)
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

	for _, key in ipairs(config.settings.keys.open_tab) do
		vim.keymap.set({ "n", "v", "i" }, key, handle_main_shift_enter, key_opts)
		vim.keymap.set({ "n", "v", "i" }, key, handle_main_shift_enter, preview_opts)
	end

	vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", toggle_focus, key_opts)
	vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", toggle_focus, preview_opts)

	for _, key in ipairs(config.settings.keys.close) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, M.close_git_center, key_opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, M.close_git_center, preview_opts)
	end

	for section = 1, 4 do
		vim.keymap.set("n", tostring(section), function()
			if section_lines[section] and M.is_open() then
				pcall(vim.api.nvim_win_set_cursor, config.main_win, { section_lines[section], 0 })
			end
		end, key_opts)
	end

	vim.keymap.set("n", "b", function()
		modals.open_branch_modal(get_active_target().full_path)
	end, key_opts)

	vim.keymap.set("n", "l", function()
		modals.open_commit_log_modal(get_active_target().full_path)
	end, key_opts)

	vim.keymap.set("n", "L", function()
		modals.open_commit_log_modal(get_active_target().full_path)
	end, key_opts)

	local commit_fields = {
		{ key = "c", field = "title", label = "Commit Title" },
		{ key = "m", field = "description", label = "Commit Description" },
		{ key = "t", field = "tag", label = "Optional Tag (e.g. v1.0.0)" },
	}
	for _, entry in ipairs(commit_fields) do
		vim.keymap.set("n", entry.key, function()
			require("plugins.krs.ui.input_modal").open({
				label = entry.label,
				default_value = config.commit_data[entry.field],
				relative = "editor",
				callback = function(ok, input)
					if ok and input then
						if entry.field == "title" or entry.field == "tag" then
							input = input:gsub("[\r\n]+", " "):gsub("^%s*", ""):gsub("%s*$", "")
						end
						config.commit_data[entry.field] = input
						refresh()
					end
				end,
			})
		end, key_opts)
	end

	vim.keymap.set("n", "s", function()
		local item = current_item()
		if item and (item.type == "unstaged" or item.type == "untracked") then
			git_run({ "add", "--", item.file }, function(ok, output)
				if not ok and output ~= "" then
					notify("❌ Error staging " .. item.file .. ": " .. output, vim.log.levels.ERROR)
				else
					notify("🟢 Staged: " .. item.file)
				end
				refresh()
			end)
		elseif item and item.type == "staged" then
			notify("File is already staged", vim.log.levels.WARN)
		end
	end, key_opts)

	vim.keymap.set("v", "s", function()
		process_visual_selection("stage")
	end, key_opts)

	vim.keymap.set({ "n", "v" }, "S", function()
		local cur_target = get_active_target()
		local current = queries.get_git_info(cur_target.full_path)
		if current and (#current.unstaged > 0 or #current.untracked > 0) then
			local args = { "add", "-A" }
			if cur_target and cur_target.is_secondary then
				args = { "add", "-u" }
			end
			git_run(args, function(ok, output)
				if not ok and output ~= "" then
					local out_str = #output > 500 and (output:sub(1, 500) .. "...\n[Truncated]") or output
					notify("❌ Error staging files: " .. out_str, vim.log.levels.ERROR)
				else
					notify("🟢 Staged all tracked files in " .. cur_target.name)
				end
				refresh()
			end)
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
		if config.commit_data.title == "" then
			notify("Please enter a commit title first with [c]", vim.log.levels.WARN)
			return
		end

		local cur_target = get_active_target()
		local args = { "commit", "-m", config.commit_data.title }
		if config.commit_data.description ~= "" then
			table.insert(args, "-m")
			table.insert(args, config.commit_data.description)
		end

		git_run(args, function(ok, output)
			if ok then
				notify(
					"🚀 Commit successful:\n" .. (output ~= "" and output or "Commit created"),
					nil,
					config.settings.control_title
				)
				if config.commit_data.tag ~= "" then
					git_lines({ "tag", config.commit_data.tag })
					notify("🏷️ Tag created: " .. config.commit_data.tag)
				end
				config.commit_data = { title = "", description = "", tag = "" }
			else
				notify(
					"❌ Commit failed:\n" .. (output ~= "" and output or "Unknown error"),
					vim.log.levels.ERROR,
					config.settings.control_title
				)
			end
			refresh()
		end, cur_target.full_path)
	end, key_opts)

	vim.keymap.set("n", "d", function()
		local item = current_item()
		modals.open_diff_modal(item and item.file or nil, item and item.type or nil, get_active_target().full_path)
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
		local row = vim.api.nvim_win_get_cursor(config.main_win)[1]
		local item = config.line_map[row]

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
		local current = queries.get_git_info(cur_target.full_path)
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
					notify("✅ Push successful to " .. remote .. "/" .. target .. "!", nil, config.settings.control_title)
				else
					notify(
						"❌ Push failed:\n" .. (output ~= "" and output or "Unknown error"),
						vim.log.levels.ERROR,
						config.settings.control_title
					)
				end
				refresh()
			end, cur_target.full_path)
		end

		local remotes = git_lines({ "remote" })
		if #remotes == 0 then
			require("plugins.krs.ui.input_modal").open({
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
					notify("✅ Push successful to remote repository!", nil, config.settings.control_title)
				else
					notify(
						"❌ Push failed:\n" .. (output ~= "" and output or "Unknown error"),
						vim.log.levels.ERROR,
						config.settings.control_title
					)
				end
				refresh()
			end, cur_target.full_path)
			return
		end

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

	for _, key in ipairs(config.settings.keys.refresh) do
		vim.keymap.set("n", key, function()
			refresh(true)
		end, key_opts)
	end
end

return M
