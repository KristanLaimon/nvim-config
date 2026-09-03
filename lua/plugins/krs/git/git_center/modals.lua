-- ============================================================================
-- KRS PLUGIN: Git Center -- Modals (Diff, Log, Branch)
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local ui = lazy_req("krs.core.ui")
local diff = lazy_req("krs.git.diff")
local path_util = lazy_req("krs.core.path")
local config = require("plugins.krs.git.git_center.config")
local queries = require("plugins.krs.git.git_center.queries")

local M = {}

local notify = config.notify
local get_active_target = config.get_active_target
local git_lines = queries.git_lines
local git_run = queries.git_run

--- Opens the Branch Management modal UI.
--- @param target_cwd string|nil Repository path.
function M.open_branch_modal(target_cwd)
	local prev_win = vim.api.nvim_get_current_win()
	local active_cwd = target_cwd or (get_active_target() and get_active_target().full_path) or vim.fn.getcwd()
	local info = queries.get_git_info(active_cwd)
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
		elseif config.main_win and vim.api.nvim_win_is_valid(config.main_win) then
			pcall(vim.api.nvim_set_current_win, config.main_win)
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
			local gc = package.loaded["plugins.krs.git.git_center"]
			if ok then
				notify("✅ Checked out branch: " .. target_b.name)
			else
				git_run({ "switch", target_b.name }, function(ok2, output2)
					if ok2 then
						notify("✅ Switched to branch: " .. target_b.name)
					else
						notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
					end
					if gc and gc.is_open and gc.is_open() and gc.refresh then
						gc.refresh()
					end
				end, active_cwd)
				return
			end
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
			end
		end, active_cwd)
	end

	local function create_branch()
		close_modal()
		require("plugins.krs.ui.input_modal").open({
			label = "Create & Checkout New Branch",
			default_value = "",
			relative = "editor",
			callback = function(ok, new_name)
				if ok and new_name and new_name ~= "" then
					new_name = new_name:gsub("%s+", "-"):gsub("[^%w%-_/.]", "")
					git_run({ "checkout", "-b", new_name }, function(ok2, output)
						local gc = package.loaded["plugins.krs.git.git_center"]
						if ok2 then
							notify("🌿 Created and switched to branch: " .. new_name)
						else
							notify("❌ Failed to create branch:\n" .. output, vim.log.levels.ERROR)
						end
						if gc and gc.is_open and gc.is_open() and gc.refresh then
							gc.refresh()
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
			local gc = package.loaded["plugins.krs.git.git_center"]
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
						if gc and gc.is_open and gc.is_open() and gc.refresh then
							gc.refresh()
						end
					end, active_cwd)
				end
			else
				notify("❌ Failed to delete branch:\n" .. output, vim.log.levels.ERROR)
			end
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
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

		require("plugins.krs.ui.input_modal").open({
			label = "Rename Branch '" .. target_b.name .. "'",
			default_value = target_b.name,
			relative = "editor",
			callback = function(ok, new_name)
				if ok and new_name and new_name ~= "" and new_name ~= target_b.name then
					new_name = new_name:gsub("%s+", "-"):gsub("[^%w%-_/.]", "")
					git_run({ "branch", "-m", target_b.name, new_name }, function(ok2, output)
						local gc = package.loaded["plugins.krs.git.git_center"]
						if ok2 then
							notify("✏️ Renamed branch to: " .. new_name)
						else
							notify("❌ Failed to rename branch:\n" .. output, vim.log.levels.ERROR)
						end
						if gc and gc.is_open and gc.is_open() and gc.refresh then
							gc.refresh()
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

	for _, key in ipairs(config.settings.keys.modal_close) do
		vim.keymap.set("n", key, close_modal, opts)
	end
end

--- Full commit log modal showing git log --all.
--- @param target_cwd string|nil Repository path.
function M.open_commit_log_modal(target_cwd)
	local prev_win = vim.api.nvim_get_current_win()
	local orig_cwd = vim.fn.getcwd()
	local active_cwd = target_cwd or (get_active_target() and get_active_target().full_path) or orig_cwd

	local info = queries.get_git_info(active_cwd)
	if not info then
		notify("Not inside a valid Git repository", vim.log.levels.WARN)
		return
	end

	local raw_commits = git_lines({
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

	local tot_w = math.floor(vim.o.columns * config.settings.width_ratio)
	local tot_h = math.floor(vim.o.lines * config.settings.height_ratio)
	local s_row = math.floor((vim.o.lines - tot_h) / 2)
	local s_col = math.floor((vim.o.columns - tot_w) / 2)

	local ratio = config.current_left_ratio or config.load_saved_left_ratio(active_cwd)
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
		elseif config.main_win and vim.api.nvim_win_is_valid(config.main_win) then
			pcall(vim.api.nvim_set_current_win, config.main_win)
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

		local cur_r = config.current_left_ratio or config.load_saved_left_ratio(active_cwd)
		local new_r = math.max(0.20, math.min(0.80, cur_r + delta))
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
			local gc = package.loaded["plugins.krs.git.git_center"]
			if ok then
				notify("✅ Checked out commit: " .. commit.hash)
			else
				notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
			end
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
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
		if
			not (right_win and vim.api.nvim_win_is_valid(right_win) and right_buf and vim.api.nvim_buf_is_valid(right_buf))
		then
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
		if
			not (right_win and vim.api.nvim_win_is_valid(right_win) and right_buf and vim.api.nvim_buf_is_valid(right_buf))
		then
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
		local panel = package.loaded["plugins.krs.git.git_center.panel"]
		if filepath and panel then
			close_log_modal()
			panel.open_file_in_tab(filepath, active_cwd)
		end
	end

	vim.keymap.set("n", "K", checkout_commit, opts)

	vim.keymap.set("n", "<CR>", focus_log_right, opts)
	vim.keymap.set("n", "<CR>", handle_right_enter, right_opts)
	vim.keymap.set("n", "d", open_right_file_diff, right_opts)

	for _, key in ipairs(config.settings.keys.open_tab) do
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

	for _, key in ipairs(config.settings.keys.scroll_down) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_log_preview("down")
		end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_log_preview("down")
		end, right_opts)
	end
	for _, key in ipairs(config.settings.keys.scroll_up) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_log_preview("up")
		end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_log_preview("up")
		end, right_opts)
	end

	for _, key in ipairs(config.settings.keys.resize_left) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			resize_log_split(-0.03)
		end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			resize_log_split(-0.03)
		end, right_opts)
	end
	for _, key in ipairs(config.settings.keys.resize_right) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			resize_log_split(0.03)
		end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			resize_log_split(0.03)
		end, right_opts)
	end

	for _, key in ipairs(config.settings.keys.modal_close) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, close_log_modal, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, close_log_modal, right_opts)
	end
	vim.keymap.set("n", "l", close_log_modal, opts)
	vim.keymap.set("n", "L", close_log_modal, opts)
end

--- Full-screen side-by-side diff viewer with file rotation and hunk navigation.
--- @param target_file string|nil File to open on. Defaults to the first changed file.
--- @param _target_type string|nil Unused; kept for call-site compatibility.
--- @param target_cwd string|nil Repository directory to view diffs for.
function M.open_diff_modal(target_file, _target_type, target_cwd)
	local prev_win = vim.api.nvim_get_current_win()
	local orig_cwd = vim.fn.getcwd()
	local active_cwd = target_cwd or (get_active_target() and get_active_target().full_path) or orig_cwd

	local info = queries.get_git_info(active_cwd)
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

	local total_width = math.floor(vim.o.columns * config.settings.modal_width_ratio)
	local total_height = math.floor(vim.o.lines * config.settings.modal_height_ratio)
	local ratio = config.current_left_ratio or config.load_saved_left_ratio(active_cwd)
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

	config.diff_modal_win = left_win
	config.diff_modal_buf = left_buf

	for _, w in ipairs({ left_win, right_win }) do
		vim.api.nvim_set_option_value("number", true, { win = w })
		vim.api.nvim_set_option_value("wrap", false, { win = w })
		vim.api.nvim_set_option_value("scrollbind", true, { win = w })
		vim.api.nvim_set_option_value("cursorbind", true, { win = w })
	end

	local function render(idx)
		index = ((idx - 1) % #files) + 1
		local item = files[index]

		local raw_lines, is_untracked = queries.raw_diff_for(item.file, item.type, active_cwd)
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
		config.diff_modal_win, config.diff_modal_buf = nil, nil
		ui.close(left_win)
		ui.close(right_win)
		if orig_cwd and vim.fn.isdirectory(orig_cwd) == 1 then
			pcall(vim.fn.chdir, orig_cwd)
		end
		if prev_win and vim.api.nvim_win_is_valid(prev_win) then
			pcall(vim.api.nvim_set_current_win, prev_win)
		elseif config.main_win and vim.api.nvim_win_is_valid(config.main_win) then
			pcall(vim.api.nvim_set_current_win, config.main_win)
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

		local cur_r = config.current_left_ratio or config.load_saved_left_ratio(active_cwd)
		local new_r = math.max(0.20, math.min(0.80, cur_r + delta))
		config.current_left_ratio = tonumber(string.format("%.3f", new_r))
		config.save_left_ratio(config.root_dir or active_cwd, config.current_left_ratio)

		local total_w = math.floor(vim.o.columns * config.settings.modal_width_ratio)
		local total_h = math.floor(vim.o.lines * config.settings.modal_height_ratio)
		local start_r = math.floor((vim.o.lines - total_h) / 2)
		local start_c = math.floor((vim.o.columns - total_w) / 2)

		left_width = math.floor(total_w * config.current_left_ratio)
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
		for _, key in ipairs(config.settings.keys.modal_close) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, close_modal, opts)
		end

		local function handle_diff_shift_enter()
			local item = files[index]
			local panel = package.loaded["plugins.krs.git.git_center.panel"]
			if item and item.file and panel then
				close_modal()
				panel.open_file_in_tab(item.file, active_cwd)
			end
		end

		for _, key in ipairs(config.settings.keys.open_tab) do
			vim.keymap.set({ "n", "v", "i" }, key, handle_diff_shift_enter, opts)
		end

		for _, key in ipairs({ "<C-h>", "<C-H>" }) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, focus_diff_left, opts)
		end
		for _, key in ipairs({ "<C-l>", "<C-L>" }) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, focus_diff_right, opts)
		end

		for _, key in ipairs(config.settings.keys.scroll_down) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function()
				scroll_diff("down")
			end, opts)
		end
		for _, key in ipairs(config.settings.keys.scroll_up) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function()
				scroll_diff("up")
			end, opts)
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

		for _, key in ipairs(config.settings.keys.resize_left) do
			vim.keymap.set({ "n", "v", "i", "t" }, key, function()
				resize_modal_split(-0.03)
			end, opts)
		end
		for _, key in ipairs(config.settings.keys.resize_right) do
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

return M
