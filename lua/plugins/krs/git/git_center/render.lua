-- ============================================================================
-- KRS PLUGIN: Git Center -- Render & Layout Engine
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local status = lazy_req("krs.git.status")
local icons = lazy_req("krs.core.icons")
local config = require("plugins.krs.git.git_center.config")

local M = {}

local env_ok, env_mod = pcall(require, "krs.core.environment")
local env = env_ok and env_mod.detect() or {}
local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

M.submodule_statuses = {}
M.fetching_submodules = {}

--- Asynchronously fetches submodule status for non-active tab indicators in background.
--- @param target table
function M.fetch_target_status_async(target)
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
			local gc = package.loaded["plugins.krs.git.git_center"]
			if
				M.render_tab_bar
				and gc
				and gc.is_open
				and gc.is_open()
				and config.tab_buf
				and vim.api.nvim_buf_is_valid(config.tab_buf)
				and config.main_win
				and vim.api.nvim_win_is_valid(config.main_win)
			then
				M.render_tab_bar(math.floor(vim.o.columns * config.settings.width_ratio))
			end
		end
	end)
end

--- Returns submodule status info from cache or triggers background fetch.
--- Never blocks the UI thread.
--- @param target table
--- @return table
function M.get_target_status(target)
	if not target or not target.full_path then
		return { has_changes = false, behind = 0, ahead = 0 }
	end
	if M.submodule_statuses[target.path] then
		return M.submodule_statuses[target.path]
	end
	if not is_mobile_or_proot then
		M.fetch_target_status_async(target)
	end
	return { has_changes = false, behind = 0, ahead = 0 }
end

--- Sets up highlight groups for the submodule tab bar attached to Git Center.
function M.setup_tab_highlights()
	local function get_hl(name)
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
		if ok and hl and next(hl) then
			return hl
		end
		return nil
	end

	local sel_hl = get_hl("BufferLineBufferSelected")
		or get_hl("TabLineSel")
		or get_hl("Title")
		or { fg = 16777215, bg = 3883602, bold = true }
	local bg_hl = get_hl("BufferLineBackground")
		or get_hl("TabLine")
		or get_hl("Comment")
		or { fg = 10066329, bg = 1973790 }
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
function M.toggle_colored_tab_indicators()
	config.settings.tab_colored_indicators = not config.settings.tab_colored_indicators
	if config.root_dir then
		config.save_git_center_config(config.root_dir, { tab_colored_indicators = config.settings.tab_colored_indicators })
	else
		config.save_git_center_config(nil, { tab_colored_indicators = config.settings.tab_colored_indicators })
	end

	local label = config.settings.tab_colored_indicators and "ENABLED (Colored)" or "DISABLED (Plain Text)"
	config.notify("🐙 Git Center: Tab Indicator Colors " .. label)

	local gc = package.loaded["plugins.krs.git.git_center"]
	if gc and gc.is_open and gc.is_open() and gc.refresh then
		gc.refresh()
	end
end

--- Renders bufferline-style submodule tabs into config.tab_buf, directly overlaying top border.
--- @param left_w integer Inner width of left panel.
function M.render_tab_bar(left_w)
	if not config.tab_buf or not vim.api.nvim_buf_is_valid(config.tab_buf) then
		return
	end

	M.setup_tab_highlights()

	vim.bo[config.tab_buf].modifiable = true
	vim.api.nvim_buf_clear_namespace(config.tab_buf, config.ns_tabs, 0, -1)

	local targets = config.submodules
	if not targets or #targets == 0 then
		targets = { config.get_active_target() }
	end

	M.tab_click_ranges = {}
	local chunks = {}

	table.insert(chunks, { text = "╭", hl = "KRSGitTabBorder" })
	table.insert(chunks, { text = " ", hl = "KRSGitTabFill" })

	for idx, item in ipairs(targets) do
		local st = M.get_target_status(item)
		local is_active = (idx == config.active_submodule_idx)
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

		if config.settings.tab_colored_indicators then
			dot_hl = is_active and (st.has_changes and "KRSGitTabDotChangedActive" or "KRSGitTabDotCleanActive")
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

	vim.api.nvim_buf_set_lines(config.tab_buf, 0, -1, false, { full_text })
	vim.bo[config.tab_buf].modifiable = false

	for _, h in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(config.tab_buf, config.ns_tabs, 0, h.start_col, {
			end_col = h.end_col,
			hl_group = h.hl,
		})
	end

	if config.tab_win and vim.api.nvim_win_is_valid(config.tab_win) then
		local active_range = nil
		for _, range in ipairs(M.tab_click_ranges) do
			if range.idx == config.active_submodule_idx then
				active_range = range
				break
			end
		end

		if active_range then
			local win_width = vim.api.nvim_win_get_width(config.tab_win)
			vim.api.nvim_win_call(config.tab_win, function()
				local view = vim.fn.winsaveview()
				local current_leftcol = view.leftcol
				local tab_start = active_range.start_col
				local tab_end = active_range.end_col
				local needs_scroll = false

				if tab_end > current_leftcol + win_width then
					view.leftcol = tab_end - win_width + 1
					needs_scroll = true
				elseif tab_start < current_leftcol then
					view.leftcol = math.max(0, tab_start - 1)
					needs_scroll = true
				end

				if needs_scroll then
					vim.fn.winrestview(view)
				end
			end)
		end
	end
end

--- @param info table Repository snapshot.
--- @param width integer Panel width, used for the separators.
--- @return string[] lines Panel text.
--- @return table line_map Line number -> `{ type, file }` for file rows.
--- @return table section_lines Section number (1-4) -> line number.
function M.build_panel_content(info, width)
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
	local title_display = config.commit_data.title ~= "" and config.commit_data.title or "<Press c to edit in Vim>"
	add("   [c] Title:       " .. title_display)

	if config.commit_data.description ~= "" then
		local desc_lines = vim.split(config.commit_data.description:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
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

	local tag_display = config.commit_data.tag ~= "" and config.commit_data.tag or "<Optional - Press t>"
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

return M
