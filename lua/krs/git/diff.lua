-- ============================================================================
-- krs.git.diff -- Turning `git diff` output into a readable, coloured buffer.
-- ============================================================================
-- WHAT IT DOES
--   Strips the machine noise from a diff (`diff --git`, `index abc..def`, the
--   `---`/`+++` pair) and keeps the hunks, each under a labelled separator. The
--   second return value tags every line so the caller can highlight it.
--
-- WHY LINES ARE SPLIT DEFENSIVELY
--   `nvim_buf_set_lines` rejects any entry containing a newline, and git can
--   smuggle one in through binary or CRLF-mangled content. Every line funnels
--   through `push`, which splits before appending.
--
-- USAGE
--   local diff = require("krs.git.diff")
--   diff.setup_highlights()
--   local lines, kinds = diff.format(raw_lines, false)
--   diff.apply_highlights(bufnr, kinds)
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration -- colours and layout of the rendered diff
-- ---------------------------------------------------------------------------

--- Namespace owning the diff lines highlights and backgrounds.
M.namespace = vim.api.nvim_create_namespace("git_center_diff_hl")

--- Namespace owning the Tree-Sitter language token highlights.
M.ts_namespace = vim.api.nvim_create_namespace("git_center_diff_ts_hl")

--- Highlight group per line kind, in VSCode-ish colours.
--- `default = true` so a colorscheme can override any of them.
M.highlights = {
	add = { name = "GitCenterDiffAdd", opts = { bg = "#1c3427", default = true } },
	add_prefix = { name = "GitCenterDiffAddPrefix", opts = { fg = "#a6e3a1", bold = true, default = true } },
	delete = { name = "GitCenterDiffDelete", opts = { bg = "#3b1d22", default = true } },
	delete_prefix = { name = "GitCenterDiffDeletePrefix", opts = { fg = "#f38ba8", bold = true, default = true } },
	header = { name = "GitCenterDiffHeader", opts = { bg = "#1e293b", fg = "#89dceb", bold = true, default = true } },
	context = { name = "GitCenterDiffContext", opts = { fg = "#cdd6f4", default = true } },
	filler = { name = "GitCenterDiffFiller", opts = { bg = "#181825", fg = "#45475a", default = true } },
}

--- Diff lines that carry no information for a reader.
M.noise_patterns = {
	"^diff %--git",
	"^index %x+%.%.%x+",
	"^%-%-%- a/",
	"^%+%+%+ b/",
	"^new file mode",
	"^deleted file mode",
}

--- Matches a hunk header, e.g. `@@ -1,7 +1,9 @@ function foo()`.
M.hunk_pattern = "^@@ %-%d+,?%d* %+%d+,?%d* @@"

--- Width a hunk separator is padded to.
M.separator_width = 65

--- Banner shown above the contents of a new, untracked file.
M.untracked_banner =
	" ─── 📄 New Untracked File ──────────────────────────────────────────"

--- Shown when a file has no visible changes (mode change, whitespace only).
M.empty_message = " (no visible changes in this file)"

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Defines the diff highlight groups. Safe to call repeatedly.
function M.setup_highlights()
	for _, highlight in pairs(M.highlights) do
		vim.api.nvim_set_hl(0, highlight.name, highlight.opts)
	end
end

--- True when a diff line is header noise rather than content.
--- @param line string
--- @return boolean
local function is_noise(line)
	for _, pattern in ipairs(M.noise_patterns) do
		if line:match(pattern) then
			return true
		end
	end
	return false
end

--- Extracts a filename from a diff line if present (e.g. diff --git, --- a/, +++ b/).
--- @param line string
--- @return string|nil filename
local function extract_diff_filename(line)
	local b_path = line:match("^diff %-%-git%s+a/.+%s+b/(.+)$")
	if b_path then
		return b_path
	end
	local plus_path = line:match("^%+%+%+%s+b/(.+)$")
	if plus_path and plus_path ~= "/dev/null" then
		return plus_path
	end
	local minus_path = line:match("^%-%-%-%s+a/(.+)$")
	if minus_path and minus_path ~= "/dev/null" then
		return minus_path
	end
	return nil
end

--- Formats raw diff output for display.
---
--- @param raw_lines string[] Output of `git diff --color=never`, or the file's
---   own contents when `is_untracked` is true.
--- @param is_untracked boolean|nil Render every line as an addition.
--- @return string[] lines Buffer-ready lines.
--- @return string[] kinds Line kind per line: "add" | "delete" | "header" | "context".
function M.format(raw_lines, is_untracked)
	local lines, kinds = {}, {}

	--- Appends one logical line, splitting any embedded newlines.
	local function push(text, kind)
		for _, part in ipairs(vim.split(text, "\n", { plain = true })) do
			table.insert(lines, part)
			table.insert(kinds, kind)
		end
	end

	if is_untracked then
		push(M.untracked_banner, "header")
		for _, line in ipairs(raw_lines) do
			push("+ " .. line, "add")
		end
		return lines, kinds
	end

	-- Everything before the first hunk header is preamble and gets dropped.
	local in_header = true
	local hunk_count = 0
	local current_file = nil

	for _, line in ipairs(raw_lines) do
		local fname = extract_diff_filename(line)
		if fname and fname ~= current_file then
			current_file = fname
			hunk_count = 0
			in_header = true
			local file_banner = string.format(" ─── 📄 File: %s ", current_file)
			if #file_banner < M.separator_width then
				file_banner = file_banner .. string.rep("─", M.separator_width - #file_banner)
			end
			push(file_banner, "header")
		end

		if is_noise(line) then -- skip
		elseif line:match(M.hunk_pattern) then
			in_header = false
			hunk_count = hunk_count + 1

			local context = line:match("@@ %-%d+,?%d* %+%d+,?%d* @@(.*)") or ""
			local range = line:match("(@@ %-%d+,?%d* %+%d+,?%d* @@)") or line
			local header = string.format(
				" ─── Hunk %d %s %s",
				hunk_count,
				range,
				context ~= "" and ("(" .. context:gsub("^%s*", "") .. ") ") or ""
			)
			if #header < M.separator_width then
				header = header .. string.rep("─", M.separator_width - #header)
			end
			push(header, "header")
		elseif not in_header then
			local first = line:sub(1, 1)
			push(line, first == "+" and "add" or (first == "-" and "delete" or "context"))
		end
	end

	local has_content = false
	for _, k in ipairs(kinds) do
		if k ~= "header" then
			has_content = true
			break
		end
	end

	if not has_content then
		push(M.empty_message, "context")
	end
	return lines, kinds
end

--- Resolves tree-sitter language for a given filename.
--- @param filename string|nil
--- @return string|nil lang
function M.get_file_language(filename)
	if not filename or filename == "" then
		return nil
	end
	local ft = vim.filetype.match({ filename = filename })
	if not ft then
		return nil
	end
	return (vim.treesitter.language.get_lang(ft)) or ft
end

--- Applies Treesitter highlighting to parsed code text mapped to buffer lines.
--- @param bufnr integer
--- @param code_lines string[]
--- @param line_map table<integer, integer> 0-based code line -> 0-based buffer line
--- @param lang string
--- @param prefix_offset integer Number of prefix columns in buffer line (e.g. 1 for "+", 2 for "+ ")
--- @param filter_kind string|nil If provided, only apply highlight when kinds[buf_line + 1] == filter_kind
--- @param kinds string[]
local function apply_ts_captures(bufnr, code_lines, line_map, lang, prefix_offset, filter_kind, kinds)
	if #code_lines == 0 then
		return
	end
	local code_str = table.concat(code_lines, "\n")
	local ok_parser, parser = pcall(vim.treesitter.get_string_parser, code_str, lang)
	if not (ok_parser and parser) then
		return
	end

	local ok_tree, tree = pcall(function()
		return parser:parse()[1]
	end)
	if not (ok_tree and tree) then
		return
	end

	local ok_query, query = pcall(vim.treesitter.query.get, lang, "highlights")
	if not (ok_query and query) then
		return
	end

	for id, node in query:iter_captures(tree:root(), code_str) do
		local cname = query.captures[id]
		if cname then
			local srow, scol, erow, ecol = node:range()
			for row = srow, erow do
				local buf_row = line_map[row]
				if buf_row then
					if not filter_kind or (kinds and kinds[buf_row + 1] == filter_kind) then
						local buf_lines = vim.api.nvim_buf_get_lines(bufnr, buf_row, buf_row + 1, false)
						local line_len = buf_lines[1] and #buf_lines[1] or 0
						local start_c = math.min(line_len, (row == srow and scol or 0) + prefix_offset)
						local end_c = (row == erow and ecol ~= -1) and math.min(line_len, ecol + prefix_offset) or line_len
						if start_c < end_c then
							vim.api.nvim_buf_add_highlight(bufnr, M.ts_namespace, "@" .. cname, buf_row, start_c, end_c)
						end
					end
				end
			end
		end
	end
end

--- Applies diff colours and Treesitter language highlighting to a buffer.
--- @param bufnr integer Buffer holding the formatted lines.
--- @param kinds string[] Second return value of `M.format`.
--- @param filename string|nil Optional filename to enable Tree-sitter syntax highlighting.
function M.apply_highlights(bufnr, kinds, filename)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
	vim.api.nvim_buf_clear_namespace(bufnr, M.ts_namespace, 0, -1)

	local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local is_untracked = #kinds > 0 and kinds[1] == "header" and buf_lines[1] and buf_lines[1]:match("New Untracked File")

	for index, kind in ipairs(kinds) do
		local row = index - 1
		local line_text = buf_lines[index] or ""
		if kind == "header" then
			vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffHeader", row, 0, -1)
		elseif kind == "add" then
			vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row, 0, {
				line_hl_group = "GitCenterDiffAdd",
				priority = 50,
			})
			local prefix_len = line_text:sub(1, 2) == "+ " and 2 or (line_text:sub(1, 1) == "+" and 1 or 0)
			if prefix_len > 0 then
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffAddPrefix", row, 0, prefix_len)
			end
		elseif kind == "delete" then
			vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row, 0, {
				line_hl_group = "GitCenterDiffDelete",
				priority = 50,
			})
			local prefix_len = line_text:sub(1, 2) == "- " and 2 or (line_text:sub(1, 1) == "-" and 1 or 0)
			if prefix_len > 0 then
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffDeletePrefix", row, 0, prefix_len)
			end
		elseif kind == "context" then
			-- Context line uses default terminal foreground / syntax highlights
		end
	end

	local lang = M.get_file_language(filename)
	if not lang then
		return
	end

	pcall(function()
		if is_untracked then
			-- Untracked file: rows 1..N have prefix "+ "
			local code_lines = {}
			local line_map = {}
			for idx = 2, #buf_lines do
				local line_text = buf_lines[idx] or ""
				local code = line_text:sub(1, 2) == "+ " and line_text:sub(3) or line_text
				table.insert(code_lines, code)
				line_map[#code_lines - 1] = idx - 1 -- 0-indexed buffer line
			end
			apply_ts_captures(bufnr, code_lines, line_map, lang, 2, nil, kinds)
		else
			-- Hunk-based diff:
			-- 1. New version code (context + addition lines)
			local new_code_lines = {}
			local new_line_map = {}
			for idx, kind in ipairs(kinds) do
				if kind == "context" or kind == "add" then
					local line_text = buf_lines[idx] or ""
					local code = line_text:sub(2) -- strip leading ' ' or '+'
					table.insert(new_code_lines, code)
					new_line_map[#new_code_lines - 1] = idx - 1
				end
			end
			apply_ts_captures(bufnr, new_code_lines, new_line_map, lang, 1, nil, kinds)

			-- 2. Old version code (context + deletion lines) -> applied only to deletion lines
			local old_code_lines = {}
			local old_line_map = {}
			for idx, kind in ipairs(kinds) do
				if kind == "context" or kind == "delete" then
					local line_text = buf_lines[idx] or ""
					local code = line_text:sub(2) -- strip leading ' ' or '-'
					table.insert(old_code_lines, code)
					old_line_map[#old_code_lines - 1] = idx - 1
				end
			end
			apply_ts_captures(bufnr, old_code_lines, old_line_map, lang, 1, "delete", kinds)
		end
	end)
end

--- Formats raw diff output into side-by-side dual buffer structures (Left = Before, Right = After).
--- @param raw_lines string[] Output of `git diff --color=never` or untracked file lines.
--- @param is_untracked boolean|nil
--- @return string[] left_lines
--- @return string[] left_kinds ("delete" | "context" | "header" | "filler")
--- @return string[] right_lines
--- @return string[] right_kinds ("add" | "context" | "header" | "filler")
function M.format_side_by_side_dual(raw_lines, is_untracked)
	local left_lines, left_kinds = {}, {}
	local right_lines, right_kinds = {}, {}

	local function push(l_text, l_kind, r_text, r_kind)
		table.insert(left_lines, l_text)
		table.insert(left_kinds, l_kind)
		table.insert(right_lines, r_text)
		table.insert(right_kinds, r_kind)
	end

	if is_untracked then
		push(
			" ─── 📄 Before (Empty File) ─────────────────────────",
			"header",
			" ─── 📄 After (New Untracked File) ──────────────────",
			"header"
		)
		for _, line in ipairs(raw_lines) do
			push("", "filler", "+ " .. line, "add")
		end
		return left_lines, left_kinds, right_lines, right_kinds
	end

	local in_header = true
	local hunk_count = 0
	local current_file = nil
	local idx = 1
	local total = #raw_lines

	while idx <= total do
		local line = raw_lines[idx]
		local fname = extract_diff_filename(line)
		if fname and fname ~= current_file then
			current_file = fname
			hunk_count = 0
			in_header = true
			local file_banner = string.format(" ─── 📄 File: %s ", current_file)
			if #file_banner < M.separator_width then
				file_banner = file_banner .. string.rep("─", M.separator_width - #file_banner)
			end
			push(file_banner, "header", file_banner, "header")
		end

		if is_noise(line) then
			idx = idx + 1
		elseif line:match(M.hunk_pattern) then
			in_header = false
			hunk_count = hunk_count + 1
			local context = line:match("@@ %-%d+,?%d* %+%d+,?%d* @@(.*)") or ""
			local range = line:match("(@@ %-%d+,?%d* %+%d+,?%d* @@)") or line
			local header = string.format(
				" ─── Hunk %d %s %s",
				hunk_count,
				range,
				context ~= "" and ("(" .. context:gsub("^%s*", "") .. ") ") or ""
			)
			if #header < M.separator_width then
				header = header .. string.rep("─", M.separator_width - #header)
			end
			push(header, "header", header, "header")
			idx = idx + 1
		elseif not in_header then
			local first = line:sub(1, 1)
			if first == "-" or first == "+" then
				local dels, adds = {}, {}
				while idx <= total do
					local l = raw_lines[idx]
					if l:match("^diff %-%-git") or l:match("^@@") or l:match("^%-%-%-%s+a/") or l:match("^%+%+%+%s+b/") then
						break
					elseif is_noise(l) then
						idx = idx + 1
					elseif l:sub(1, 1) == "-" then
						table.insert(dels, l)
						idx = idx + 1
					else
						break
					end
				end
				while idx <= total do
					local l = raw_lines[idx]
					if l:match("^diff %-%-git") or l:match("^@@") or l:match("^%-%-%-%s+a/") or l:match("^%+%+%+%s+b/") then
						break
					elseif is_noise(l) then
						idx = idx + 1
					elseif l:sub(1, 1) == "+" then
						table.insert(adds, l)
						idx = idx + 1
					else
						break
					end
				end

				local max_count = math.max(#dels, #adds)
				for i = 1, max_count do
					local l_txt = dels[i] or ""
					local l_k = dels[i] and "delete" or "filler"
					local r_txt = adds[i] or ""
					local r_k = adds[i] and "add" or "filler"
					push(l_txt, l_k, r_txt, r_k)
				end
			else
				push(line, "context", line, "context")
				idx = idx + 1
			end
		else
			idx = idx + 1
		end
	end

	if #left_lines == 0 then
		push(M.empty_message, "context", M.empty_message, "context")
	end

	return left_lines, left_kinds, right_lines, right_kinds
end

--- Formats side-by-side lines into a single buffer line array with dual columns separated by `│`.
--- @param raw_lines string[]
--- @param is_untracked boolean|nil
--- @param width integer Total available width in characters.
--- @return string[] lines
--- @return string[] left_kinds
--- @return string[] right_kinds
--- @return integer col_w Left column width.
function M.format_side_by_side_single(raw_lines, is_untracked, width)
	width = math.max(40, width or 80)
	local col_w = math.floor((width - 3) / 2)
	local left_lines, left_kinds, right_lines, right_kinds = M.format_side_by_side_dual(raw_lines, is_untracked)

	local combined = {}
	for i = 1, #left_lines do
		local l_raw = left_lines[i] or ""
		local r_raw = right_lines[i] or ""

		if left_kinds[i] == "header" or right_kinds[i] == "header" then
			local hdr = l_raw
			if #hdr > width then
				hdr = hdr:sub(1, width)
			elseif #hdr < width then
				hdr = hdr .. string.rep("─", width - #hdr)
			end
			table.insert(combined, hdr)
		else
			local l_padded = l_raw
			if #l_padded > col_w then
				l_padded = l_padded:sub(1, col_w)
			else
				l_padded = l_padded .. string.rep(" ", col_w - #l_padded)
			end

			local r_padded = r_raw
			if #r_padded > col_w then
				r_padded = r_padded:sub(1, col_w)
			else
				r_padded = r_padded .. string.rep(" ", col_w - #r_padded)
			end

			table.insert(combined, l_padded .. " │ " .. r_padded)
		end
	end

	return combined, left_kinds, right_kinds, col_w
end

--- Applies highlights to side-by-side dual buffers (Left = Before, Right = After).
--- @param left_buf integer
--- @param left_kinds string[]
--- @param right_buf integer
--- @param right_kinds string[]
--- @param filename string|nil
function M.apply_highlights_side_by_side_dual(left_buf, left_kinds, right_buf, right_kinds, filename)
	if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
		vim.api.nvim_buf_clear_namespace(left_buf, M.namespace, 0, -1)
		vim.api.nvim_buf_clear_namespace(left_buf, M.ts_namespace, 0, -1)
		local lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
		for idx, kind in ipairs(left_kinds) do
			local row = idx - 1
			local line_text = lines[idx] or ""
			if kind == "header" then
				vim.api.nvim_buf_add_highlight(left_buf, M.namespace, "GitCenterDiffHeader", row, 0, -1)
			elseif kind == "delete" then
				vim.api.nvim_buf_set_extmark(left_buf, M.namespace, row, 0, {
					line_hl_group = "GitCenterDiffDelete",
					priority = 50,
				})
				local prefix_len = line_text:sub(1, 2) == "- " and 2 or (line_text:sub(1, 1) == "-" and 1 or 0)
				if prefix_len > 0 then
					vim.api.nvim_buf_add_highlight(left_buf, M.namespace, "GitCenterDiffDeletePrefix", row, 0, prefix_len)
				end
			elseif kind == "filler" then
				vim.api.nvim_buf_set_extmark(left_buf, M.namespace, row, 0, {
					line_hl_group = "GitCenterDiffFiller",
					priority = 40,
				})
			end
		end
	end

	if right_buf and vim.api.nvim_buf_is_valid(right_buf) then
		vim.api.nvim_buf_clear_namespace(right_buf, M.namespace, 0, -1)
		vim.api.nvim_buf_clear_namespace(right_buf, M.ts_namespace, 0, -1)
		local lines = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)
		for idx, kind in ipairs(right_kinds) do
			local row = idx - 1
			local line_text = lines[idx] or ""
			if kind == "header" then
				vim.api.nvim_buf_add_highlight(right_buf, M.namespace, "GitCenterDiffHeader", row, 0, -1)
			elseif kind == "add" then
				vim.api.nvim_buf_set_extmark(right_buf, M.namespace, row, 0, {
					line_hl_group = "GitCenterDiffAdd",
					priority = 50,
				})
				local prefix_len = line_text:sub(1, 2) == "+ " and 2 or (line_text:sub(1, 1) == "+" and 1 or 0)
				if prefix_len > 0 then
					vim.api.nvim_buf_add_highlight(right_buf, M.namespace, "GitCenterDiffAddPrefix", row, 0, prefix_len)
				end
			elseif kind == "filler" then
				vim.api.nvim_buf_set_extmark(right_buf, M.namespace, row, 0, {
					line_hl_group = "GitCenterDiffFiller",
					priority = 40,
				})
			end
		end
	end

	local lang = M.get_file_language(filename)
	if not lang then
		return
	end

	pcall(function()
		if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
			local buf_lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
			local code_lines, line_map = {}, {}
			for idx, kind in ipairs(left_kinds) do
				if kind == "context" or kind == "delete" then
					local text = buf_lines[idx] or ""
					local code = text:sub(1, 1) == "-" and text:sub(2) or text
					table.insert(code_lines, code)
					line_map[#code_lines - 1] = idx - 1
				end
			end
			apply_ts_captures(left_buf, code_lines, line_map, lang, 1, nil, left_kinds)
		end

		if right_buf and vim.api.nvim_buf_is_valid(right_buf) then
			local buf_lines = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)
			local code_lines, line_map = {}, {}
			for idx, kind in ipairs(right_kinds) do
				if kind == "context" or kind == "add" then
					local text = buf_lines[idx] or ""
					local code = text:sub(1, 1) == "+" and text:sub(2) or text
					table.insert(code_lines, code)
					line_map[#code_lines - 1] = idx - 1
				end
			end
			apply_ts_captures(right_buf, code_lines, line_map, lang, 1, nil, right_kinds)
		end
	end)
end

--- Applies highlights to a single-buffer dual-column side-by-side diff.
--- @param bufnr integer
--- @param left_kinds string[]
--- @param right_kinds string[]
--- @param col_w integer
--- @param start_row_offset integer|nil Line offset for headers (default 0).
function M.apply_highlights_side_by_side_single(bufnr, left_kinds, right_kinds, col_w, start_row_offset)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	start_row_offset = start_row_offset or 0

	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
	vim.api.nvim_buf_clear_namespace(bufnr, M.ts_namespace, 0, -1)

	local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	for idx = 1, #left_kinds do
		local row = start_row_offset + (idx - 1)
		local l_kind = left_kinds[idx]
		local r_kind = right_kinds[idx]
		local line_text = buf_lines[idx] or ""

		if l_kind == "header" or r_kind == "header" then
			vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffHeader", row, 0, -1)
		else
			if l_kind == "delete" then
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffDelete", row, 0, col_w)
			elseif l_kind == "filler" then
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffFiller", row, 0, col_w)
			end

			local sep_start = col_w
			local sep_end = math.min(#line_text, col_w + 3)
			vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffContext", row, sep_start, sep_end)

			if r_kind == "add" then
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffAdd", row, sep_end, -1)
			elseif r_kind == "filler" then
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, "GitCenterDiffFiller", row, sep_end, -1)
			end
		end
	end
end

return M
