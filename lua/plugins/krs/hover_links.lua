-- ============================================================================
-- KRS PLUGIN: Hover Doc Links -- navigate file:/// and web links in hover popups
-- ============================================================================
-- WHAT IT DOES
--   * Triggers or focuses LSP hover documentation when `K` or `Shift+K` is pressed.
--   * When inside the hover float, caret movement + `<CR>` (Enter), `gx` or `K`
--     follows markdown links `[label](target)` and raw URLs (`file://...`, `https://...`).
--   * Local file links (`file:///...#line,col` or `:line:col`) jump directly to that
--     file and position in the main editor window.
--   * Web links (`http://...` or `https://...`) open in the system default web browser.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local path = lazy_req("krs.core.path")

local M = {}

M.settings = {
	border = "rounded",
}

--- Checks if a window handle is a floating window.
--- @param winid integer|nil Window handle.
--- @return boolean
local function is_float_win(winid)
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return false
	end
	local cfg = vim.api.nvim_win_get_config(winid)
	return cfg.relative ~= nil and cfg.relative ~= ""
end

--- Finds an active floating window associated with the current buffer or hover preview.
--- @return integer|nil winid
local function find_hover_float_win()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if is_float_win(win) then
			local b = vim.api.nvim_win_get_buf(win)
			local ft = vim.bo[b].filetype
			if ft == "markdown" or ft == "lspinfo" or ft == "" then
				return win
			end
		end
	end
	return nil
end

--- Extracts and resolves links from string lines (markdown, URLs, file paths in comments).
local function resolve_file_target(target, buf_dir)
	local raw_path = target:gsub("^file:///", ""):gsub("^file://", "")
	-- On Windows file:///C:/... becomes /C:/...; strip leading slash for drive letters
	raw_path = raw_path:gsub("^/(%a:)", "%1")

	local clean_path = raw_path
	local target_line, target_col = 1, 1

	-- Try matching patterns: #2575,6 or #2575 or #L2575,6 or :2575:6 or :2575
	local p1, l1, c1 = raw_path:match("^(.-)#L?(%d+),?(%d*)$")
	if p1 then
		clean_path = p1
		target_line = tonumber(l1) or 1
		target_col = tonumber(c1) or 1
	else
		local p2, l2, c2 = raw_path:match("^(.-)#L?(%d+):?(%d*)$")
		if p2 then
			clean_path = p2
			target_line = tonumber(l2) or 1
			target_col = tonumber(c2) or 1
		else
			local p3, l3, c3 = raw_path:match("^(.-):(%d+):?(%d*)$")
			if p3 then
				clean_path = p3
				target_line = tonumber(l3) or 1
				target_col = tonumber(c3) or 1
			end
		end
	end

	clean_path = path.normalize(clean_path)
	local is_abs = (path.is_absolute and path.is_absolute(clean_path))
		or (clean_path:sub(1, 1) == "/" or clean_path:match("^%a:") ~= nil)

	local candidate = clean_path
	if not is_abs then
		if buf_dir and buf_dir ~= "" then
			local buf_rel = path.join(buf_dir, clean_path)
			if vim.fn.filereadable(buf_rel) == 1 or vim.fn.isdirectory(buf_rel) == 1 then
				candidate = buf_rel
			else
				candidate = path.join(vim.fn.getcwd(), clean_path)
			end
		else
			candidate = path.join(vim.fn.getcwd(), clean_path)
		end
	end

	local exists = (vim.fn.filereadable(candidate) == 1) or (vim.fn.isdirectory(candidate) == 1)
	return candidate, target_line, target_col, exists
end

--- Extracts all links (markdown, URLs, comment file paths) from a line.
--- @param line string
--- @param buf_dir string|nil
--- @return table[] links List of { start_col, end_col, label, target }
local function parse_links_in_line(line, buf_dir)
	local links = {}

	-- 1. Markdown links: [label](target)
	local s_pos = 1
	while true do
		local m_start, m_end, label, target = line:find("(%[[^%]]+%]%(([^%)]+)%))", s_pos)
		if not m_start then
			break
		end
		table.insert(links, {
			start_col = m_start,
			end_col = m_end,
			label = label,
			target = target,
		})
		s_pos = m_end + 1
	end

	-- 2. Raw URLs: http(s):// or file://
	local patterns = { "https?://%S+", "file://%S+" }
	for _, pat in ipairs(patterns) do
		s_pos = 1
		while true do
			local u_start, u_end, target = line:find("(" .. pat .. ")", s_pos)
			if not u_start then
				break
			end

			-- Strip trailing punctuation (like trailing paren, period, quotes)
			target = target:gsub("[%s%),.\"'`]+$", "")

			local inside = false
			for _, l in ipairs(links) do
				if u_start >= l.start_col and u_end <= l.end_col then
					inside = true
					break
				end
			end
			if not inside then
				table.insert(links, {
					start_col = u_start,
					end_col = u_end,
					label = target,
					target = target,
				})
			end
			s_pos = u_end + 1
		end
	end

	-- 3. Bare file path references in comments or prose (e.g. docs/keybinds.md:30 or notes.txt#L10)
	s_pos = 1
	while true do
		local f_start, f_end, target = line:find("([%w_%-./\\]+%.%w+[:#]?%d*[:#]?%d*)", s_pos)
		if not f_start then
			break
		end

		target = target:gsub("[%s%),.\"'`]+$", "")

		local inside = false
		for _, l in ipairs(links) do
			if f_start >= l.start_col and f_end <= l.end_col then
				inside = true
				break
			end
		end

		if not inside and #target > 3 then
			local _, _, _, exists = resolve_file_target(target, buf_dir)
			if exists then
				table.insert(links, {
					start_col = f_start,
					end_col = f_end,
					label = target,
					target = target,
				})
			end
		end
		s_pos = f_end + 1
	end

	return links
end

--- Opens a web URL in the system browser.
--- @param url string
local function open_web_url(url)
	local ok = pcall(vim.ui.open, url)
	if not ok then
		if vim.fn.has("win32") == 1 then
			vim.fn.jobstart({ "cmd", "/c", "start", "", url })
		elseif vim.fn.has("mac") == 1 then
			vim.fn.jobstart({ "open", url })
		else
			vim.fn.jobstart({ "xdg-open", url })
		end
	end
	vim.notify("🌐 Opening web link: " .. url, vim.log.levels.INFO, { title = "Link Navigator" })
end

--- Opens a local file URL or file path at the given line/column.
--- @param target string file:/// path or relative path with optional #line,col or :line:col
--- @param current_win integer Window handle.
--- @param buf_dir string|nil Buffer directory.
--- @return boolean success
local function open_local_file_link(target, current_win, buf_dir)
	local clean_path, target_line, target_col, exists = resolve_file_target(target, buf_dir)

	-- Close float window if called from float/hover window
	if current_win and is_float_win(current_win) then
		pcall(vim.api.nvim_win_close, current_win, true)
	end

	if not exists then
		vim.notify("File not found: " .. clean_path, vim.log.levels.WARN, { title = "Link Navigator" })
		return false
	end

	-- Open in current main window
	vim.cmd("edit " .. vim.fn.fnameescape(clean_path))
	pcall(vim.api.nvim_win_set_cursor, 0, { target_line, math.max(0, target_col - 1) })
	vim.notify(
		"📂 Jumped to " .. vim.fn.fnamemodify(clean_path, ":t") .. ":" .. target_line .. ":" .. target_col,
		vim.log.levels.INFO,
		{ title = "Link Navigator" }
	)
	return true
end

--- Parses link at cursor inside current window and executes jump.
--- @return boolean handled True if a link was found and followed.
function M.follow_link_at_cursor()
	local winid = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local cursor = vim.api.nvim_win_get_cursor(winid)
	local row, col = cursor[1], cursor[2] + 1

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	local buf_dir = buf_name ~= "" and vim.fn.fnamemodify(buf_name, ":h") or ""

	local lines = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)
	local line = lines[1] or ""

	local links = parse_links_in_line(line, buf_dir)

	-- If no links on current line, and buffer is markdown or text file, search whole buffer
	local ft = vim.bo[bufnr].filetype
	if #links == 0 and (ft == "markdown" or ft == "text" or ft == "krsdocindex") then
		local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		for _, l in ipairs(all_lines) do
			local l_links = parse_links_in_line(l, buf_dir)
			if #l_links > 0 then
				links = l_links
				break
			end
		end
	end

	if #links == 0 then
		return false
	end

	-- Select best link relative to cursor col
	local chosen = nil
	for _, link in ipairs(links) do
		if col >= link.start_col and col <= link.end_col then
			chosen = link
			break
		end
	end

	if not chosen then
		chosen = links[1]
	end

	local target = chosen.target
	if target:match("^https?://") or target:match("^www%.") then
		open_web_url(target)
		return true
	else
		return open_local_file_link(target, winid, buf_dir)
	end
end

--- Closes hover float window.
function M.close_hover()
	local winid = vim.api.nvim_get_current_win()
	if is_float_win(winid) then
		pcall(vim.api.nvim_win_close, winid, true)
	end
end

--- Handles Shift+Click inside hover float or buffer to position cursor at mouse and follow link.
local function follow_link_at_mouse()
	local mouse_pos = vim.fn.getmousepos()
	if mouse_pos and mouse_pos.winid > 0 and vim.api.nvim_win_is_valid(mouse_pos.winid) then
		vim.api.nvim_set_current_win(mouse_pos.winid)
		pcall(vim.api.nvim_win_set_cursor, mouse_pos.winid, { mouse_pos.line, math.max(0, mouse_pos.column - 1) })
	end
	return M.follow_link_at_cursor()
end

--- Attaches keymaps to a hover float buffer.
--- @param bufnr integer
--- @param winid integer
function M.attach_hover_keymaps(bufnr, winid)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local function make_opts(desc)
		return { buffer = bufnr, noremap = true, silent = true, nowait = true, desc = desc }
	end

	vim.keymap.set("n", "<CR>", M.follow_link_at_cursor, make_opts("Follow hover link"))
	vim.keymap.set("n", "<C-k>", M.follow_link_at_cursor, make_opts("Follow hover link"))
	vim.keymap.set("n", "gx", M.follow_link_at_cursor, make_opts("Follow hover link"))
	vim.keymap.set("n", "K", M.follow_link_at_cursor, make_opts("Follow hover link"))
	vim.keymap.set({ "n", "v" }, "<S-LeftMouse>", follow_link_at_mouse, make_opts("Follow hover link at mouse click"))
	vim.keymap.set("n", "q", M.close_hover, make_opts("Close hover float"))
	vim.keymap.set("n", "<Esc>", M.close_hover, make_opts("Close hover float"))
end

--- Shows hover or focuses floating window if already open.
function M.show_or_focus_hover()
	local current_win = vim.api.nvim_get_current_win()

	-- If already in a float window
	if is_float_win(current_win) then
		M.follow_link_at_cursor()
		return
	end

	-- If a hover float is open, move cursor into it
	local float_win = find_hover_float_win()
	if float_win then
		vim.api.nvim_set_current_win(float_win)
		return
	end

	-- Otherwise trigger hover
	pcall(function()
		vim.lsp.buf.hover({ border = M.settings.border, focusable = true })
	end)
end

--- Initializes link handler wrapper for markdown, text files, code comments, and LSP hovers.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local augroup = vim.api.nvim_create_augroup("KrsHoverLinks", { clear = true })

	-- Attach keymaps for markdown and text files (skip scratch/nofile/modal buffers)
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = { "markdown", "text", "gitcommit" },
		callback = function(ev)
			if vim.bo[ev.buf].buftype ~= "" or vim.b[ev.buf].krs_wiki_modal then
				return
			end
			local function make_opts(desc)
				return { buffer = ev.buf, noremap = true, silent = true, desc = desc }
			end
			vim.keymap.set("n", "<CR>", function()
				if not M.follow_link_at_cursor() then
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
				end
			end, make_opts("Follow link under cursor"))
			vim.keymap.set("n", "gx", M.follow_link_at_cursor, make_opts("Follow link under cursor"))
			vim.keymap.set("n", "<C-k>", M.follow_link_at_cursor, make_opts("Follow link under cursor"))
		end,
	})

	-- Global gx keymap for code files / language comments
	vim.keymap.set("n", "gx", function()
		local handled = M.follow_link_at_cursor()
		if not handled then
			local word = vim.fn.expand("<cfile>")
			if word and word ~= "" then
				pcall(vim.ui.open, word)
			end
		end
	end, { noremap = true, silent = true, desc = "Follow link under cursor" })

	local orig_hover = vim.lsp.handlers["textDocument/hover"]
	if orig_hover then
		vim.lsp.handlers["textDocument/hover"] = function(err, result, ctx, config)
			config = config or {}
			config.border = config.border or M.settings.border
			config.focusable = true
			local bufnr, winid = orig_hover(err, result, ctx, config)
			if winid and vim.api.nvim_win_is_valid(winid) then
				local buf = vim.api.nvim_win_get_buf(winid)
				M.attach_hover_keymaps(buf, winid)
			end
			return bufnr, winid
		end
	end
end

return setmetatable({
	name = "krs_hover_links",
	dir = require("krs.core.lazyspec").for_module(),
	event = { "BufReadPost", "BufNewFile" },
	config = M.setup,
}, { __index = M })
