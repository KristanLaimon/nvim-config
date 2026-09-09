-- ============================================================================
-- krs.git.conflicts -- Detection, marker parsing, and conflict resolution.
-- ============================================================================
-- WHY THIS MODULE EXISTS
--   Git merge conflicts leave raw conflict markers (<<<<<<<, =======, >>>>>>>)
--   in files and record unmerged stages in the index (stage 1=base, 2=ours, 3=theirs).
--   This module provides pure, testable functions for:
--     1. Discovering which files have conflicts in a repository.
--     2. Parsing conflict markers from file contents / buffer lines.
--     3. Extracting clean "Current" and "Incoming" full versions.
--     4. Applying resolutions (accept current, accept incoming, accept both).
--     5. Staging resolved files (`git add`).
-- ============================================================================

local git = require("krs.git.cmd")
local path_util = require("krs.core.path")

local M = {}

-- ---------------------------------------------------------------------------
-- Conflict Marker Detection & Parsing
-- ---------------------------------------------------------------------------

--- Parses conflict markers from an array of lines.
--- Supports standard two-way markers (<<<<<<<, =======, >>>>>>>) and
--- three-way diff3 markers (<<<<<<<, |||||||, =======, >>>>>>>).
---
--- @param lines string[] Buffer lines (1-indexed)
--- @return table[] conflicts Array of conflict descriptors
function M.parse_markers(lines)
	local conflicts = {}
	local i = 1
	local total = #lines

	while i <= total do
		local line = lines[i]
		if type(line) == "string" and line:match("^<<<<<<<") then
			local start_line = i
			local current_label = line:gsub("^<<<<<<<%s*", "")
			local base_sep_line = nil
			local sep_line = nil
			local end_line = nil
			local incoming_label = ""

			local current_lines = {}
			local base_lines = {}
			local incoming_lines = {}

			local stage = "current"
			local j = i + 1

			while j <= total do
				local cur = lines[j]
				if type(cur) == "string" then
					if cur:match("^|||||||") and stage == "current" then
						stage = "base"
						base_sep_line = j
					elseif cur:match("^=======") and (stage == "current" or stage == "base") then
						stage = "incoming"
						sep_line = j
					elseif cur:match("^>>>>>>>") and stage == "incoming" then
						end_line = j
						incoming_label = cur:gsub("^>>>>>>>%s*", "")
						break
					else
						if stage == "current" then
							table.insert(current_lines, cur)
						elseif stage == "base" then
							table.insert(base_lines, cur)
						elseif stage == "incoming" then
							table.insert(incoming_lines, cur)
						end
					end
				end
				j = j + 1
			end

			if sep_line and end_line then
				table.insert(conflicts, {
					id = #conflicts + 1,
					start_line = start_line,
					base_sep_line = base_sep_line,
					sep_line = sep_line,
					end_line = end_line,
					current_label = current_label,
					incoming_label = incoming_label,
					current_lines = current_lines,
					base_lines = base_lines,
					incoming_lines = incoming_lines,
				})
				i = end_line
			end
		end
		i = i + 1
	end

	return conflicts
end

--- Extracts clean Current (ours) and Incoming (theirs) versions of a file
--- from its lines containing conflict markers.
---
--- @param lines string[] Lines containing conflict markers
--- @return string[] current_lines Version with all Current changes chosen
--- @return string[] incoming_lines Version with all Incoming changes chosen
--- @return string[] base_lines Version with base changes if diff3, else current
function M.extract_clean_versions(lines)
	local conflicts = M.parse_markers(lines)
	if #conflicts == 0 then
		local copy = {}
		for _, l in ipairs(lines) do
			table.insert(copy, l)
		end
		return copy, copy, copy
	end

	local current_out = {}
	local incoming_out = {}
	local base_out = {}

	local line_idx = 1
	local total = #lines

	for _, c in ipairs(conflicts) do
		-- Add common lines before conflict
		while line_idx < c.start_line do
			table.insert(current_out, lines[line_idx])
			table.insert(incoming_out, lines[line_idx])
			table.insert(base_out, lines[line_idx])
			line_idx = line_idx + 1
		end

		-- Add current chunk
		for _, l in ipairs(c.current_lines) do
			table.insert(current_out, l)
		end

		-- Add incoming chunk
		for _, l in ipairs(c.incoming_lines) do
			table.insert(incoming_out, l)
		end

		-- Add base chunk (or current if no diff3 base recorded)
		local base_chunk = #c.base_lines > 0 and c.base_lines or c.current_lines
		for _, l in ipairs(base_chunk) do
			table.insert(base_out, l)
		end

		line_idx = c.end_line + 1
	end

	-- Add trailing common lines
	while line_idx <= total do
		table.insert(current_out, lines[line_idx])
		table.insert(incoming_out, lines[line_idx])
		table.insert(base_out, lines[line_idx])
		line_idx = line_idx + 1
	end

	return current_out, incoming_out, base_out
end

--- Resolves a single conflict inside an array of lines.
---
--- @param lines string[] The working file lines
--- @param conflict table A conflict descriptor from `M.parse_markers`
--- @param choice string "current" | "incoming" | "both_current_first" | "both_incoming_first"
--- @return string[] new_lines New array of lines after replacement
function M.resolve_conflict_in_lines(lines, conflict, choice)
	local replacement = {}
	if choice == "current" or choice == "ours" then
		replacement = conflict.current_lines
	elseif choice == "incoming" or choice == "theirs" then
		replacement = conflict.incoming_lines
	elseif choice == "both_current_first" or choice == "both" then
		for _, l in ipairs(conflict.current_lines) do
			table.insert(replacement, l)
		end
		for _, l in ipairs(conflict.incoming_lines) do
			table.insert(replacement, l)
		end
	elseif choice == "both_incoming_first" then
		for _, l in ipairs(conflict.incoming_lines) do
			table.insert(replacement, l)
		end
		for _, l in ipairs(conflict.current_lines) do
			table.insert(replacement, l)
		end
	end

	local out = {}
	for idx = 1, conflict.start_line - 1 do
		table.insert(out, lines[idx])
	end
	for _, l in ipairs(replacement) do
		table.insert(out, l)
	end
	for idx = conflict.end_line + 1, #lines do
		table.insert(out, lines[idx])
	end
	return out
end

--- Builds clean resolved lines from lines containing conflict markers.
--- Replaces each conflict block with the specified choice (default: "current").
---
--- @param lines string[] Buffer lines with conflict markers
--- @param markers table[]|nil Output of M.parse_markers
--- @param default_choice string|nil "current" (default), "incoming", or "both"
--- @return string[] clean_lines
--- @return table[] spans Array of conflict span descriptors
function M.build_resolved_lines(lines, markers, default_choice)
	markers = markers or M.parse_markers(lines)
	default_choice = default_choice or "current"

	if #markers == 0 then
		local copy = {}
		for _, l in ipairs(lines) do
			table.insert(copy, l)
		end
		return copy, {}
	end

	local clean = {}
	local spans = {}
	local src_idx = 1
	local total = #lines

	for idx, m in ipairs(markers) do
		while src_idx < m.start_line do
			table.insert(clean, lines[src_idx])
			src_idx = src_idx + 1
		end

		local chosen_chunk = {}
		if default_choice == "incoming" then
			chosen_chunk = m.incoming_lines
		elseif default_choice == "both" then
			for _, l in ipairs(m.current_lines) do
				table.insert(chosen_chunk, l)
			end
			for _, l in ipairs(m.incoming_lines) do
				table.insert(chosen_chunk, l)
			end
		else
			chosen_chunk = m.current_lines
		end

		local span_start = #clean + 1
		for _, l in ipairs(chosen_chunk) do
			table.insert(clean, l)
		end
		local span_end = math.max(span_start, #clean)

		table.insert(spans, {
			id = idx,
			start_line = span_start,
			end_line = span_end,
			choice = default_choice,
			current_lines = m.current_lines,
			incoming_lines = m.incoming_lines,
			base_lines = m.base_lines,
			current_label = m.current_label,
			incoming_label = m.incoming_label,
		})

		src_idx = m.end_line + 1
	end

	while src_idx <= total do
		table.insert(clean, lines[src_idx])
		src_idx = src_idx + 1
	end

	return clean, spans
end

-- ---------------------------------------------------------------------------
-- Git Repository Inspection
-- ---------------------------------------------------------------------------

--- Reads git index stage content for a file (1=base, 2=ours/current, 3=theirs/incoming).
--- @param file string Path relative to repo
--- @param stage integer 1, 2, or 3
--- @param cwd string|nil Repository directory
--- @return string[]|nil lines Content lines if found
function M.get_stage_content(file, stage, cwd)
	cwd = cwd or vim.fn.getcwd()
	local proc = git.spawn({ "show", string.format(":%d:%s", stage, file) }, cwd)
	if not proc then
		return nil
	end
	local res = proc:wait()
	if res.code == 0 and res.stdout then
		local stdout = res.stdout:gsub("\r\n", "\n"):gsub("\r", "\n")
		return vim.split(stdout, "\n", { plain = true })
	end
	return nil
end

--- Reads the working tree content of a conflicted file.
--- @param full_path string Absolute path to file
--- @return string[] lines
function M.read_file_lines(full_path)
	if vim.fn.filereadable(full_path) == 1 then
		local ok, content = pcall(vim.fn.readfile, full_path)
		if ok and content then
			return content
		end
	end
	return {}
end

--- Scans repository for all files that have merge conflicts.
---
--- @param cwd string|nil Repository directory
--- @return table[] conflicted Array of { file = "rel/path", full_path = "...", conflict_count = n }
function M.get_conflicted_files(cwd)
	cwd = cwd or vim.fn.getcwd()
	if not git.is_repository(cwd) then
		return {}
	end

	local found_set = {}
	local conflicted = {}

	-- Method 1: git diff --name-only --diff-filter=U
	local diff_unmerged = git.lines({ "diff", "--name-only", "--diff-filter=U" }, cwd)
	for _, rel_path in ipairs(diff_unmerged) do
		local clean = rel_path:gsub('^"', ""):gsub('"$', ""):gsub("^%s*", ""):gsub("%s*$", "")
		if clean ~= "" and not found_set[clean] then
			found_set[clean] = true
		end
	end

	-- Method 2: git status --porcelain=v1 for unmerged XY codes
	local status_lines = git.lines({ "status", "--porcelain=v1" }, cwd)
	for _, line in ipairs(status_lines) do
		if #line >= 4 then
			local xy = line:sub(1, 2)
			local name = line:sub(4):gsub('^"', ""):gsub('"$', "")
			if
				xy == "UU"
				or xy == "AA"
				or xy == "DD"
				or xy == "AU"
				or xy == "UD"
				or xy == "UA"
				or xy == "DU"
				or xy:find("U")
			then
				if not found_set[name] then
					found_set[name] = true
				end
			end
		end
	end

	-- For each file in found_set, compute full path and count markers
	for rel_path, _ in pairs(found_set) do
		local full_path = path_util.is_absolute(rel_path) and rel_path or path_util.join(cwd, rel_path)
		local lines = M.read_file_lines(full_path)
		local count = #M.parse_markers(lines)
		table.insert(conflicted, {
			file = rel_path,
			full_path = full_path,
			conflict_count = count,
			has_markers = count > 0,
		})
	end

	-- Sort alphabetically by file name
	table.sort(conflicted, function(a, b)
		return a.file < b.file
	end)

	return conflicted
end

--- Checks if repository at `cwd` has any merge conflicts.
--- @param cwd string|nil
--- @return boolean has_conflicts
--- @return integer count
function M.has_conflicts(cwd)
	local files = M.get_conflicted_files(cwd)
	return #files > 0, #files
end

--- Returns readable branch / ref names for current HEAD and incoming merge ref.
--- @param cwd string|nil
--- @return string current_name
--- @return string incoming_name
function M.get_conflict_branch_names(cwd)
	cwd = cwd or vim.fn.getcwd()
	local head_branch = "HEAD (Current)"
	local incoming_branch = "Incoming"

	local b_lines = git.lines({ "rev-parse", "--abbrev-ref", "HEAD" }, cwd)
	if #b_lines > 0 and b_lines[1] ~= "HEAD" and b_lines[1] ~= "" then
		head_branch = b_lines[1]
	end

	-- Check MERGE_HEAD
	local merge_head_proc = git.spawn({ "rev-parse", "--short", "MERGE_HEAD" }, cwd)
	if merge_head_proc then
		local res = merge_head_proc:wait()
		if res.code == 0 and res.stdout and res.stdout:gsub("%s+", "") ~= "" then
			local short_hash = res.stdout:gsub("%s+", "")
			-- Try to get branch name from MERGE_MSG
			local merge_msg_file = path_util.join(cwd, ".git", "MERGE_MSG")
			if vim.fn.filereadable(merge_msg_file) == 1 then
				local msg_lines = vim.fn.readfile(merge_msg_file)
				if #msg_lines > 0 then
					local b = msg_lines[1]:match("Merge branch '([^']+)'")
						or msg_lines[1]:match("Merge remote%-tracking branch '([^']+)'")
						or msg_lines[1]:match("Merge tag '([^']+)'")
					if b then
						incoming_branch = b
					else
						incoming_branch = "MERGE_HEAD (" .. short_hash .. ")"
					end
				else
					incoming_branch = "MERGE_HEAD (" .. short_hash .. ")"
				end
			else
				incoming_branch = "MERGE_HEAD (" .. short_hash .. ")"
			end
		end
	end

	return head_branch, incoming_branch
end

--- Stages a file in git after conflicts have been resolved (`git add`).
--- @param file string Path relative to repo
--- @param cwd string|nil
--- @return boolean ok
--- @return string output
function M.stage_file(file, cwd)
	cwd = cwd or vim.fn.getcwd()
	local proc = git.spawn({ "add", file }, cwd)
	if not proc then
		return false, "Failed to spawn git add"
	end
	local res = proc:wait()
	if res.code == 0 then
		return true, res.stdout or ""
	end
	return false, res.stderr or "git add failed"
end

return M
