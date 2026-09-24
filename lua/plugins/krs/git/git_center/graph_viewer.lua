-- ============================================================================
-- KRS PLUGIN: Git Center -- GitKraken Style Commit Graph Viewer
-- ============================================================================
-- Interactive dual-pane commit graph viewer with:
--   - 2 modes: "branch" (Actual/Current Branch only) and "all" (--all branches)
--   - GitKraken visual aesthetics: colored branch lanes, circular commit nodes,
--     capsule ref/branch/tag badges, SHA, author, and relative dates.
--   - On-the-fly lazy loading / pagination when scrolling down via Vim motions
--     (d, u, Ctrl+d, Ctrl+u, j, k, G, gg).
--   - Side preview pane with full commit details, changed files, and side-by-side diff.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local ui = lazy_req("krs.core.ui")
local diff = lazy_req("krs.git.diff")
local config = require("plugins.krs.git.git_center.config")
local queries = require("plugins.krs.git.git_center.queries")
local z_index = require("krs.core.z_index")

local M = {}
local canvas_mode = false

M.ns_graph = vim.api.nvim_create_namespace("KRSGitKrakenGraphSpans")

local LANE_COLORS = {
	{ name = "KRSGitKrakenLane1", fg = "#89dceb" }, -- Cyan
	{ name = "KRSGitKrakenLane2", fg = "#cba6f7" }, -- Lavender / Purple
	{ name = "KRSGitKrakenLane3", fg = "#a6e3a1" }, -- Green
	{ name = "KRSGitKrakenLane4", fg = "#f9e2af" }, -- Warm Gold / Yellow
	{ name = "KRSGitKrakenLane5", fg = "#f38ba8" }, -- Coral / Red
	{ name = "KRSGitKrakenLane6", fg = "#fab387" }, -- Peach / Orange
	{ name = "KRSGitKrakenLane7", fg = "#94e2d5" }, -- Teal
	{ name = "KRSGitKrakenLane8", fg = "#89b4fa" }, -- Sky Blue
}

--- Registers highlight groups for GitKraken aesthetics.
function M.setup_highlights()
	for _, lane in ipairs(LANE_COLORS) do
		vim.api.nvim_set_hl(0, lane.name, { fg = lane.fg, bold = true, default = true })
	end

	vim.api.nvim_set_hl(0, "KRSGitKrakenSha", { fg = "#eed49f", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenSubject", { fg = "#cdd6f4", default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenAuthor", { fg = "#89dceb", default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenDate", { fg = "#a6adc8", default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenDim", { fg = "#585b70", default = true })

	-- Ref badges
	vim.api.nvim_set_hl(0, "KRSGitKrakenBadgeHead", { fg = "#11111b", bg = "#a6e3a1", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenBadgeRemote", { fg = "#11111b", bg = "#89b4fa", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenBadgeTag", { fg = "#11111b", bg = "#f9e2af", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenBadgeBranch", { fg = "#11111b", bg = "#cba6f7", bold = true, default = true })

	-- Header / Mode badge
	vim.api.nvim_set_hl(0, "KRSGitKrakenHeader", { fg = "#89dceb", bold = true, default = true })
	vim.api.nvim_set_hl(0, "KRSGitKrakenModeBadge", { fg = "#11111b", bg = "#89dceb", bold = true, default = true })
end

--- Converts raw ASCII git-graph characters into GitKraken-style Unicode box glyphs.
--- @param raw_prefix string
--- @return string
function M.beautify_graph_prefix(raw_prefix)
	local res = {}
	for i = 1, #raw_prefix do
		local c = raw_prefix:sub(i, i)
		if c == "*" then
			table.insert(res, "●")
		elseif c == "|" then
			table.insert(res, "│")
		elseif c == "/" then
			table.insert(res, "╱")
		elseif c == "\\" then
			table.insert(res, "╲")
		elseif c == "_" or c == "-" then
			table.insert(res, "─")
		elseif c == "." then
			table.insert(res, "⬝")
		else
			table.insert(res, c)
		end
	end
	return table.concat(res)
end

--- Parses ref decoration string (e.g. "(HEAD -> main, origin/main, tag: v1.0.0)").
--- @param refs_str string|nil
--- @return table[] badges
local function parse_refs(refs_str)
	if not refs_str or refs_str == "" then
		return {}
	end
	local clean = refs_str:gsub("^%s*%(?", ""):gsub("%)?%s*$", "")
	if clean == "" then
		return {}
	end

	local items = vim.split(clean, ", ", { plain = true })
	local badges = {}
	for _, item in ipairs(items) do
		item = item:gsub("^%s*", ""):gsub("%s*$", "")
		if item ~= "" and item ~= "origin/HEAD" then
			if item:match("^HEAD %-> (.+)$") then
				local b = item:match("^HEAD %-> (.+)$")
				table.insert(badges, { text = "🌿 " .. b, hl = "KRSGitKrakenBadgeHead" })
			elseif item:match("^tag:%s*(.+)$") then
				local t = item:match("^tag:%s*(.+)$")
				table.insert(badges, { text = "🏷️ " .. t, hl = "KRSGitKrakenBadgeTag" })
			elseif item:match("^remotes/origin/(.+)$") or item:match("^origin/(.+)$") then
				local r = item:gsub("^remotes/origin/", ""):gsub("^origin/", "")
				table.insert(badges, { text = "☁️ " .. r, hl = "KRSGitKrakenBadgeRemote" })
			else
				table.insert(badges, { text = "🌲 " .. item, hl = "KRSGitKrakenBadgeBranch" })
			end
		end
	end
	return badges
end

--- Parses a raw line from `git log --graph --pretty=format:%h%x1f%d%x1f%an%x1f%cr%x1f%s`.
--- @param raw_line string
--- @return table parsed
function M.parse_raw_graph_line(raw_line)
	local sep = "\x1f"
	local first_sep = raw_line:find(sep, 1, true)

	if not first_sep then
		-- Pure graph connector line without a commit (e.g. branch merge/split)
		return {
			is_commit = false,
			graph_raw = raw_line,
			hash = nil,
			refs = "",
			author = "",
			date = "",
			subject = "",
		}
	end

	local prefix_and_hash = raw_line:sub(1, first_sep - 1)
	local rest = raw_line:sub(first_sep + 1)
	local parts = vim.split(rest, sep, { plain = true })

	local graph_prefix, hash = prefix_and_hash:match("^(.-)%s*(%x%x%x%x%x%x%x+)$")
	if not hash then
		graph_prefix = prefix_and_hash
		hash = ""
	end

	return {
		is_commit = true,
		graph_raw = graph_prefix or "",
		hash = hash,
		refs = parts[1] or "",
		author = parts[2] or "",
		date = parts[3] or "",
		subject = parts[4] or "",
	}
end

--- Formats a parsed graph entry into a rendered line string and extmark span highlights.
--- @param parsed table
--- @return string line_text
--- @return table[] spans
function M.format_commit_line(parsed)
	local line_text = ""
	local byte_len = 0
	local spans = {}

	local function append(chunk, hl_group)
		if not chunk or chunk == "" then
			return
		end
		local start_byte = byte_len
		line_text = line_text .. chunk
		byte_len = byte_len + #chunk
		if hl_group then
			table.insert(spans, { col_start = start_byte, col_end = byte_len, hl_group = hl_group })
		end
	end

	-- Left margin
	append(" ")

	-- Beautified graph with column-based lane colors
	local raw = parsed.graph_raw or ""
	for col = 1, #raw do
		local c = raw:sub(col, col)
		local lane_idx = ((col - 1) % #LANE_COLORS) + 1
		local hl = LANE_COLORS[lane_idx].name

		if c == "*" then
			append("●", hl)
		elseif c == "|" then
			append("│", hl)
		elseif c == "/" then
			append("╱", hl)
		elseif c == "\\" then
			append("╲", hl)
		elseif c == "_" or c == "-" then
			append("─", hl)
		elseif c == "." then
			append("⬝", hl)
		elseif c == " " then
			append(" ", nil)
		else
			append(c, hl)
		end
	end

	if not parsed.is_commit or not parsed.hash or parsed.hash == "" then
		return line_text, spans
	end

	append(" ")

	-- Short commit hash
	append(parsed.hash, "KRSGitKrakenSha")
	append(" ")

	-- Ref badges
	local badges = parse_refs(parsed.refs)
	for _, badge in ipairs(badges) do
		append(" " .. badge.text .. " ", badge.hl)
		append(" ")
	end

	-- Commit subject
	if parsed.subject and parsed.subject ~= "" then
		append(parsed.subject, "KRSGitKrakenSubject")
	else
		append("(no commit message)", "KRSGitKrakenDim")
	end

	-- Author & Relative date
	if parsed.author and parsed.author ~= "" then
		append("  👤 " .. parsed.author, "KRSGitKrakenAuthor")
	end
	if parsed.date and parsed.date ~= "" then
		append("  🕒 " .. parsed.date, "KRSGitKrakenDate")
	end

	return line_text, spans
end

--- Fetches commit graph lines from Git.
--- @param limit integer Number of commits to request.
--- @param cwd string Repository directory.
--- @param mode "branch"|"all" Mode to run git log in.
--- @return table result
function M.fetch_commits(limit, cwd, mode)
	local cmd = {
		"log",
		"--graph",
		"--color=never",
		"--pretty=format:%h%x1f%d%x1f%an%x1f%cr%x1f%s",
		"-n",
		tostring(limit),
	}
	if mode == "all" then
		table.insert(cmd, 2, "--all")
	else
		table.insert(cmd, "HEAD")
	end

	local raw_lines = queries.git_lines(cmd, cwd)

	local rendered_lines = {}
	local all_spans = {}
	local line_commits = {}
	local commits = {}

	for idx, raw_line in ipairs(raw_lines) do
		local parsed = M.parse_raw_graph_line(raw_line)
		local line_text, spans = M.format_commit_line(parsed)

		table.insert(rendered_lines, line_text)
		table.insert(all_spans, spans)

		if parsed.is_commit and parsed.hash and parsed.hash ~= "" then
			line_commits[idx] = parsed.hash
			table.insert(commits, parsed)
		end
	end

	-- If git returned fewer commits than limit, all commits were fetched
	local all_fetched = #commits < limit

	return {
		lines = rendered_lines,
		spans = all_spans,
		line_commits = line_commits,
		commits = commits,
		total_commits = #commits,
		all_fetched = all_fetched,
	}
end

--- Opens the full-screen GitKraken-style Commit Graph Viewer.
--- @param target_cwd string|nil Repository directory.
--- @param initial_mode? "branch"|"all" Defaults to "branch".
function M.open(target_cwd, initial_mode)
	local prev_win = vim.api.nvim_get_current_win()
	local active_cwd = target_cwd
		or (config.get_active_target() and config.get_active_target().full_path)
		or vim.fn.getcwd()

	local info = queries.get_git_info(active_cwd)
	if not info then
		config.notify("Not inside a valid Git repository", vim.log.levels.WARN)
		return
	end

	M.setup_highlights()
	diff.setup_highlights()

	local mode = initial_mode or "branch"
	local current_limit = 50
	local batch_size = 50
	local is_fetching = false
	local all_fetched = false

	local current_branch = (info.branch and info.branch ~= "") and info.branch
		or (queries.git_lines({ "branch", "--show-current" }, active_cwd)[1] or "HEAD")

	local initial_data = M.fetch_commits(current_limit, active_cwd, mode)
	if #initial_data.lines == 0 then
		config.notify("No commit history found in repository", vim.log.levels.INFO)
		return
	end

	all_fetched = initial_data.all_fetched
	local rendered_lines = initial_data.lines
	local all_spans = initial_data.spans
	local line_commits = initial_data.line_commits
	local commits_data = initial_data.commits
	local total_commits_count = initial_data.total_commits

	-- Geometry calculation using dual panel
	local tot_w = math.floor(vim.o.columns * config.settings.width_ratio)
	local tot_h = math.floor(vim.o.lines * config.settings.height_ratio)
	local s_row = math.floor((vim.o.lines - tot_h) / 2)
	local s_col = math.floor((vim.o.columns - tot_w) / 2)

	local ratio = config.current_left_ratio or config.load_saved_left_ratio(active_cwd)
	-- For graph tree, default to 52% width so graph + message + badges fit comfortably
	if not config.current_left_ratio then
		ratio = 0.52
	end
	local left_w = math.floor(tot_w * ratio)
	local right_w = tot_w - left_w - 2

	local graph_z = z_index.next_zindex("git_center_graph", { parent = "git_center", offset = 30 })

	-- Create Left (Graph) Buffer & Window
	local left_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[left_buf].buftype = "nofile"
	vim.bo[left_buf].bufhidden = "wipe"
	vim.bo[left_buf].swapfile = false
	vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, rendered_lines)
	vim.bo[left_buf].modifiable = false

	-- Apply spans highlights
	vim.api.nvim_buf_clear_namespace(left_buf, M.ns_graph, 0, -1)
	for row_idx, spans in ipairs(all_spans) do
		for _, s in ipairs(spans) do
			pcall(vim.api.nvim_buf_add_highlight, left_buf, M.ns_graph, s.hl_group, row_idx - 1, s.col_start, s.col_end)
		end
	end

	local function format_title(loading)
		local mode_str = mode == "all" and "🌐 All Branches (--all) [a: Switch to Current]"
			or string.format("🌿 Current Branch (%s) [a: Switch to --all]", current_branch)
		local count_str = all_fetched and string.format("(All %d commits)", total_commits_count)
			or string.format("(%d commits)", total_commits_count)
		local load_str = loading and " ⏳ Loading..." or ""
		return string.format(" 📊 GitKraken Graph │ Mode: %s │ %s%s ", mode_str, count_str, load_str)
	end

	local left_win = vim.api.nvim_open_win(left_buf, true, {
		relative = "editor",
		width = left_w,
		height = tot_h,
		row = s_row,
		col = s_col,
		style = "minimal",
		border = "rounded",
		zindex = graph_z,
		title = format_title(false),
		title_pos = "center",
	})
	vim.api.nvim_set_option_value("cursorline", true, { win = left_win })
	vim.api.nvim_set_option_value("wrap", false, { win = left_win })

	-- Create Right (Commit Details) Buffer & Window
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
		zindex = graph_z,
		title = " 👁️ Commit Details & Side-by-Side Diff │ [Tab]: Focus │ [Enter]: Full Diff ",
		title_pos = "center",
	})
	vim.api.nvim_set_option_value("wrap", false, { win = right_win })
	vim.api.nvim_set_option_value("number", true, { win = right_win })

	z_index.register(
		"git_center_graph",
		{ left_win, right_win },
		{ parent = "git_center", offset = 30, zindex = graph_z }
	)

	config.graph_win = left_win
	config.graph_buf = left_buf
	config.graph_right_win = right_win
	config.graph_right_buf = right_buf

	local is_closed = false

	local function update_window_title(loading)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		if canvas_mode then
			vim.api.nvim_win_set_config(left_win, {
				title = " 📊 Git Graph — Canvas Mode (f: split, ?: help) ",
				title_pos = "center",
			})
		else
			vim.api.nvim_win_set_config(left_win, {
				title = format_title(loading),
				title_pos = "center",
			})
		end
	end

	local function close_viewer(keep_screen)
		if is_closed then
			return
		end
		is_closed = true

		if keep_screen == true then
			config.cached_view = "graph"
			config.cached_view_data.cwd = active_cwd
			config.cached_view_data.mode = mode
		elseif keep_screen == false then
			config.cached_view = "panel"
			config.cached_view_data = {}
		end

		config.graph_win, config.graph_buf = nil, nil
		config.graph_right_win, config.graph_right_buf = nil, nil

		z_index.unregister("git_center_graph")
		ui.close(left_win)
		ui.close(right_win)

		if
			prev_win
			and vim.api.nvim_win_is_valid(prev_win)
			and not (config.main_win and vim.api.nvim_win_is_valid(config.main_win))
		then
			pcall(vim.api.nvim_set_current_win, prev_win)
		elseif config.main_win and vim.api.nvim_win_is_valid(config.main_win) then
			pcall(vim.api.nvim_set_current_win, config.main_win)
		end
	end

	for _, win in ipairs({ left_win, right_win }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = function()
				vim.schedule(close_viewer)
			end,
		})
	end

	-- Commit details cache & state
	local commit_cache = {}
	local current_commit_hash = nil
	local current_target_file = nil

	local function get_commit_at_row(row)
		local hash = line_commits[row]
		if not hash then
			-- Search nearest lines for commit
			for r = row, 1, -1 do
				if line_commits[r] then
					hash = line_commits[r]
					break
				end
			end
			if not hash then
				for r = row, #rendered_lines do
					if line_commits[r] then
						hash = line_commits[r]
						break
					end
				end
			end
		end
		if not hash then
			return nil
		end
		if commit_cache[hash] then
			return commit_cache[hash]
		end

		local meta = queries.git_lines(
			{ "show", "-s", "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%ar%x1f%s%x1f%b%x1f%d", hash },
			active_cwd
		)
		local commit = {
			full_hash = hash,
			hash = hash:sub(1, 7),
			author = "",
			email = "",
			date = "",
			rel_date = "",
			subject = "",
			body = "",
			refs = "",
		}
		if #meta > 0 then
			local parts = vim.split(meta[1], "\x1f", { plain = true })
			commit.full_hash = parts[1] or hash
			commit.hash = parts[2] or hash:sub(1, 7)
			commit.author = parts[3] or ""
			commit.email = parts[4] or ""
			commit.date = parts[5] or ""
			commit.rel_date = parts[6] or ""
			commit.subject = parts[7] or ""
			commit.body = parts[8] or ""
			commit.refs = parts[9] or ""
		end

		commit_cache[hash] = commit
		return commit
	end

	local function update_commit_details(target_filepath)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		if canvas_mode then
			return
		end
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if not commit then
			return
		end

		local raw_stat = queries.git_lines({ "show", "--name-status", "--pretty=format:", commit.full_hash }, active_cwd)
		local edited_files = {}
		for _, line in ipairs(raw_stat) do
			local status_char, filepath = line:match("^([A-Z%d]+)%s+(.+)$")
			if status_char and filepath then
				table.insert(edited_files, { status = status_char:sub(1, 1), filepath = filepath })
			end
		end

		if commit.full_hash ~= current_commit_hash then
			current_commit_hash = commit.full_hash
			current_target_file = target_filepath or (edited_files[1] and edited_files[1].filepath)
		elseif target_filepath then
			current_target_file = target_filepath
		end

		local raw_diff = {}
		if current_target_file then
			raw_diff = queries.git_lines({ "show", "--color=never", commit.full_hash, "--", current_target_file }, active_cwd)
		else
			raw_diff = queries.git_lines({ "show", "--color=never", commit.full_hash }, active_cwd)
		end
		local combined_diff_lines, l_kinds, r_kinds, col_w = diff.format_side_by_side_single(raw_diff, false, right_w)

		local content = {}
		table.insert(content, string.format(" 📌 Commit:      %s (%s)  [y: copy SHA]", commit.full_hash, commit.hash))
		table.insert(content, string.format(" 👤 Author:      %s <%s>", commit.author, commit.email))
		table.insert(content, string.format(" 🕒 Date:        %s (%s)", commit.date, commit.rel_date))
		if commit.refs and commit.refs ~= "" then
			table.insert(
				content,
				string.format(" 🏷️ Refs:        %s", commit.refs:gsub("^%s*%(?", ""):gsub("%)?%s*$", ""))
			)
		end
		table.insert(content, string.format(" 💬 Title:       %s", commit.subject))

		if commit.body and commit.body ~= "" then
			local body_lines = vim.split(commit.body, "\n", { plain = true })
			for _, bl in ipairs(body_lines) do
				if bl ~= "" then
					table.insert(content, "    " .. bl)
				end
			end
		end

		if #edited_files > 0 then
			table.insert(content, string.format(" 📁 Files Changed (%d): [Enter on file for diff]", #edited_files))
			for _, item in ipairs(edited_files) do
				local active_mark = item.filepath == current_target_file and "▶ " or "  "
				table.insert(content, string.format(" %s• [%s] %s", active_mark, item.status, item.filepath))
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

	-- On-the-fly fetch implementation
	local function fetch_more(target_row)
		if is_fetching or all_fetched then
			if target_row and left_win and vim.api.nvim_win_is_valid(left_win) then
				local max_r = vim.api.nvim_buf_line_count(left_buf)
				pcall(vim.api.nvim_win_set_cursor, left_win, { math.min(target_row, max_r), 0 })
			end
			return
		end

		is_fetching = true
		current_limit = current_limit + batch_size
		update_window_title(true)

		vim.schedule(function()
			local ok, result = pcall(M.fetch_commits, current_limit, active_cwd, mode)
			is_fetching = false
			if ok and result then
				if result.total_commits <= #commits_data then
					all_fetched = true
				else
					commits_data = result.commits
					total_commits_count = result.total_commits
					all_fetched = result.all_fetched
					rendered_lines = result.lines
					all_spans = result.spans
					line_commits = result.line_commits

					if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
						vim.bo[left_buf].modifiable = true
						vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, rendered_lines)
						vim.bo[left_buf].modifiable = false

						vim.api.nvim_buf_clear_namespace(left_buf, M.ns_graph, 0, -1)
						for row_idx, spans in ipairs(all_spans) do
							for _, s in ipairs(spans) do
								pcall(
									vim.api.nvim_buf_add_highlight,
									left_buf,
									M.ns_graph,
									s.hl_group,
									row_idx - 1,
									s.col_start,
									s.col_end
								)
							end
						end
					end
				end
			end

			update_window_title(false)

			if target_row and left_win and vim.api.nvim_win_is_valid(left_win) then
				local max_r = vim.api.nvim_buf_line_count(left_buf)
				pcall(vim.api.nvim_win_set_cursor, left_win, { math.min(target_row, max_r), 0 })
			end
		end)
	end

	-- Motions: Half-page down / up, Down / Up
	local function half_page_down()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		local h = vim.api.nvim_win_get_height(left_win)
		local step = math.max(1, math.floor(h / 2))
		local line_count = vim.api.nvim_buf_line_count(left_buf)
		local target_row = row + step

		if (target_row >= line_count - 10 or row >= line_count - 1) and not all_fetched and not is_fetching then
			fetch_more(target_row)
		else
			pcall(vim.api.nvim_win_set_cursor, left_win, { math.min(target_row, line_count), 0 })
		end
	end

	local function half_page_up()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		local h = vim.api.nvim_win_get_height(left_win)
		local step = math.max(1, math.floor(h / 2))
		local target_row = math.max(1, row - step)
		pcall(vim.api.nvim_win_set_cursor, left_win, { target_row, 0 })
	end

	local function move_down()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		local line_count = vim.api.nvim_buf_line_count(left_buf)
		local target_row = row + 1

		if target_row > line_count then
			if not all_fetched and not is_fetching then
				fetch_more(target_row)
			end
			return
		end

		if target_row >= line_count - 8 and not all_fetched and not is_fetching then
			fetch_more(nil)
		end

		pcall(vim.api.nvim_win_set_cursor, left_win, { target_row, 0 })
	end

	local function move_up()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		pcall(vim.api.nvim_win_set_cursor, left_win, { math.max(1, row - 1), 0 })
	end

	local function jump_bottom()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local line_count = vim.api.nvim_buf_line_count(left_buf)
		if not all_fetched and not is_fetching then
			fetch_more(line_count + 50)
		else
			pcall(vim.api.nvim_win_set_cursor, left_win, { line_count, 0 })
		end
	end

	local function jump_top()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		pcall(vim.api.nvim_win_set_cursor, left_win, { 1, 0 })
	end

	-- Toggle mode (Current Branch <-> All Branches)
	local function toggle_mode()
		mode = (mode == "branch") and "all" or "branch"
		current_limit = 50
		all_fetched = false
		commits_data = {}
		rendered_lines = {}
		all_spans = {}
		line_commits = {}

		update_window_title(true)

		vim.schedule(function()
			local result = M.fetch_commits(current_limit, active_cwd, mode)
			commits_data = result.commits
			total_commits_count = result.total_commits
			all_fetched = result.all_fetched
			rendered_lines = result.lines
			all_spans = result.spans
			line_commits = result.line_commits

			if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
				vim.bo[left_buf].modifiable = true
				vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, rendered_lines)
				vim.bo[left_buf].modifiable = false

				vim.api.nvim_buf_clear_namespace(left_buf, M.ns_graph, 0, -1)
				for row_idx, spans in ipairs(all_spans) do
					for _, s in ipairs(spans) do
						pcall(vim.api.nvim_buf_add_highlight, left_buf, M.ns_graph, s.hl_group, row_idx - 1, s.col_start, s.col_end)
					end
				end
			end

			pcall(vim.api.nvim_win_set_cursor, left_win, { 1, 0 })
			update_window_title(false)
			update_commit_details(nil)

			local mode_name = (mode == "all") and "🌐 All Branches (--all)"
				or ("🌿 Current Branch (" .. current_branch .. ")")
			config.notify("Switched Git Graph Mode: " .. mode_name)
		end)
	end

	-- Canvas Mode Toggle
	local function toggle_canvas_mode()
		canvas_mode = not canvas_mode
		if canvas_mode then
			-- Close right pane
			if right_win and vim.api.nvim_win_is_valid(right_win) then
				ui.close(right_win)
				config.graph_right_win = nil
			end
			-- Resize left pane to full width
			if left_win and vim.api.nvim_win_is_valid(left_win) then
				local total_w = math.floor(vim.o.columns * config.settings.width_ratio)
				local s_col = math.floor((vim.o.columns - total_w) / 2)
				vim.api.nvim_win_set_config(left_win, {
					width = total_w - 2,
					col = s_col,
				})
				-- Update title
				vim.api.nvim_win_set_config(left_win, {
					title = " 📊 Git Graph — Canvas Mode (f: split, ?: help) ",
				})
				-- Enable mouse scrolling
				vim.wo[left_win].scrolloff = 0
				vim.wo[left_win].mousescroll = "ver:3,hor:0"
			end
		else
			-- Re-open right pane and restore split
			local cwd = active_cwd
			local current_mode = mode
			close_viewer(false)
			M.open(cwd, current_mode)
		end
	end

	-- Split resizing
	local function resize_split(delta)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end

		local cur_r = config.current_left_ratio or ratio
		local new_r = math.max(0.25, math.min(0.75, cur_r + delta))
		config.current_left_ratio = tonumber(string.format("%.3f", new_r))
		config.save_left_ratio(config.root_dir or active_cwd, config.current_left_ratio)

		local total_w = math.floor(vim.o.columns * config.settings.width_ratio)
		local total_h = math.floor(vim.o.lines * config.settings.height_ratio)
		local start_r = math.floor((vim.o.lines - total_h) / 2)
		local start_c = math.floor((vim.o.columns - total_w) / 2)

		left_w = math.floor(total_w * config.current_left_ratio)
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

	-- Focus toggling
	local function toggle_focus()
		local target = vim.api.nvim_get_current_win() == left_win and right_win or left_win
		if target and vim.api.nvim_win_is_valid(target) then
			vim.api.nvim_set_current_win(target)
		end
	end

	-- Actions: Copy SHA, Checkout, Full Diff
	local function yank_sha()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if commit then
			vim.fn.setreg("+", commit.full_hash)
			vim.fn.setreg("*", commit.full_hash)
			config.notify("📋 Copied Commit SHA to clipboard: " .. commit.hash)
		end
	end

	local function checkout_commit()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if not commit then
			return
		end
		if
			vim.fn.confirm("⚠️ Checkout commit " .. commit.hash .. " (" .. commit.subject .. ")?", "&Yes\n&No", 2) ~= 1
		then
			return
		end
		close_viewer()
		queries.git_run({ "checkout", commit.full_hash }, function(ok, output)
			local gc = package.loaded["plugins.krs.git.git_center"]
			if ok then
				config.notify("✅ Checked out commit: " .. commit.hash)
			else
				config.notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
			end
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
			end
		end, active_cwd)
	end

	local function open_full_diff()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if commit then
			local modals = require("plugins.krs.git.git_center.modals")
			modals.open_diff_modal(current_target_file, "commit", active_cwd, commit.full_hash)
		end
	end

	local function handle_right_enter()
		if
			not (right_win and vim.api.nvim_win_is_valid(right_win) and right_buf and vim.api.nvim_buf_is_valid(right_buf))
		then
			return
		end
		local cursor_line = vim.api.nvim_win_get_cursor(right_win)[1]
		local line_text = vim.api.nvim_buf_get_lines(right_buf, cursor_line - 1, cursor_line, false)[1] or ""

		local filepath = line_text:match("•%s*%[[A-Z%d]+%]%s+(.+)$") or line_text:match("•%s*(.+)$")
		if filepath then
			filepath = filepath:gsub("^%s*", ""):gsub("%s*$", "")
			local row = vim.api.nvim_win_get_cursor(left_win)[1]
			local commit = get_commit_at_row(row)
			local modals = require("plugins.krs.git.git_center.modals")
			modals.open_diff_modal(filepath, "commit", active_cwd, commit and commit.full_hash)
			return
		end

		open_full_diff()
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

	local function show_help_modal()
		local help_lines = {
			" 📊 GitKraken Commit Graph Shortcuts",
			" ──────────────────────────────────────────────────────────",
			"  [f]            Toggle Canvas Mode (fullscreen graph)",
			"  [a]            Toggle Mode (🌿 Current Branch <-> 🌐 --all)",
			"  [d / <C-d>]    Half-Page Down (Fetches on the fly)",
			"  [u / <C-u>]    Half-Page Up",
			"  [j / k]        Move down / up 1 commit (Auto-fetches)",
			"  [G / gg]       Jump to Bottom (Fetch all) / Jump to Top",
			"  [Tab]          Switch focus between Graph Tree & Details pane",
			"  [<CR> / Enter] In Graph: Focus details │ In Details: File Diff",
			"  [y]            Yank commit SHA to clipboard",
			"  [K]            Checkout selected commit",
			"  [D]            Open full-screen side-by-side diff modal",
			"  [r / <F5>]     Refresh graph from git",
			"  [< / >]        Resize split width",
			"  [q / <Esc>]    Close Commit Graph Viewer",
			" ──────────────────────────────────────────────────────────",
			"  Press any key to dismiss",
		}
		ui.float({
			title = " ❓ Help: GitKraken Graph Viewer ",
			lines = help_lines,
			width = 0.55,
			height = #help_lines + 2,
			zindex = graph_z + 20,
			close_on_keys = { "q", "<Esc>", "<CR>", "<Space>" },
		})
	end

	-- Autocmds
	local augroup = vim.api.nvim_create_augroup("KRSGitKrakenGraph", { clear = true })

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = left_buf,
		callback = function()
			vim.schedule(function()
				if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
					return
				end
				local cur = vim.api.nvim_win_get_cursor(left_win)
				local row = cur[1]
				local line_count = vim.api.nvim_buf_line_count(left_buf)

				if line_count > 0 and row >= (line_count - 10) and not all_fetched and not is_fetching then
					fetch_more(nil)
				end

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

	-- Keybindings
	local opts = { buffer = left_buf, noremap = true, silent = true, nowait = true }
	local right_opts = { buffer = right_buf, noremap = true, silent = true, nowait = true }

	-- Vim motions: d, u, Ctrl+d, Ctrl+u
	vim.keymap.set("n", "d", half_page_down, opts)
	vim.keymap.set("n", "<C-d>", half_page_down, opts)
	vim.keymap.set("n", "u", half_page_up, opts)
	vim.keymap.set("n", "<C-u>", half_page_up, opts)

	-- Single line motion with auto background fetch
	vim.keymap.set("n", "j", move_down, opts)
	vim.keymap.set("n", "<Down>", move_down, opts)
	vim.keymap.set("n", "k", move_up, opts)
	vim.keymap.set("n", "<Up>", move_up, opts)

	-- Jumps
	vim.keymap.set("n", "G", jump_bottom, opts)
	vim.keymap.set("n", "gg", jump_top, opts)

	-- Mode toggle: 'a'
	vim.keymap.set("n", "a", toggle_mode, opts)

	-- Focus & Details navigation
	vim.keymap.set({ "n", "v" }, "<Tab>", toggle_focus, opts)
	vim.keymap.set({ "n", "v" }, "<Tab>", toggle_focus, right_opts)
	vim.keymap.set("n", "<CR>", function()
		if canvas_mode then
			-- Show commit details in a floating popup
			local row = vim.api.nvim_win_get_cursor(left_win)[1]
			local hash = line_commits[row]
			if not hash then
				local commit = get_commit_at_row(row)
				if commit then
					hash = commit.full_hash
				end
			end
			if hash then
				local details = queries.git_lines(
					{ "show", "--stat", "--format=Author: %an <%ae>%nDate:   %cr%n%n%s%n%n%b", hash },
					active_cwd
				)
				local detail_buf, detail_win = ui.float({
					lines = details,
					width = 0.6,
					height = math.min(#details + 2, 30),
					title = string.format(" Commit %s ", hash:sub(1, 7)),
					border = "rounded",
					relative = "editor",
					zindex = graph_z + 10,
				})
				if detail_win and vim.api.nvim_win_is_valid(detail_win) then
					ui.close_on_keys(detail_buf, detail_win, { "q", "<Esc>", "<CR>" })
				end
			end
			return
		end
		toggle_focus()
	end, opts)
	vim.keymap.set("n", "<CR>", handle_right_enter, right_opts)

	-- Canvas Mode
	vim.keymap.set("n", "f", toggle_canvas_mode, opts)

	-- Actions
	vim.keymap.set("n", "y", yank_sha, opts)
	vim.keymap.set("n", "K", checkout_commit, opts)
	vim.keymap.set("n", "D", open_full_diff, opts)
	vim.keymap.set("n", "?", show_help_modal, opts)
	vim.keymap.set("n", "?", show_help_modal, right_opts)

	-- Split resizing
	vim.keymap.set("n", "<", function()
		resize_split(-0.03)
	end, opts)
	vim.keymap.set("n", ">", function()
		resize_split(0.03)
	end, opts)
	vim.keymap.set("n", "<", function()
		resize_split(-0.03)
	end, right_opts)
	vim.keymap.set("n", ">", function()
		resize_split(0.03)
	end, right_opts)

	-- Refresh
	vim.keymap.set("n", "r", function()
		current_limit = 50
		all_fetched = false
		fetch_more(1)
		config.notify("🔄 Commit Graph Refreshed")
	end, opts)
	vim.keymap.set("n", "<F5>", function()
		current_limit = 50
		all_fetched = false
		fetch_more(1)
		config.notify("🔄 Commit Graph Refreshed")
	end, opts)

	-- Close
	local close_keys = { "q", "<Esc>", "<esc>", "<ESC>", "<C-[>", "<C-c>" }
	for _, k in ipairs(close_keys) do
		vim.keymap.set("n", k, function()
			close_viewer(false)
		end, opts)
		vim.keymap.set("n", k, function()
			close_viewer(false)
		end, right_opts)
	end

	-- Initial commit details preview
	update_commit_details(nil)
end

return M
