-- ============================================================================
-- krs.git.status -- Repository snapshot: branch, files, line counts.
-- ============================================================================
-- WHAT IT PRODUCES
--   One table describing the repository right now:
--     { branch, upstream, added, deleted, staged[], unstaged[], untracked[] }
--
-- WHY THE PARSING LIVES HERE
--   Porcelain v1 status is a fixed, testable format, and separating it from the
--   Git Center's windows means the panel can be rebuilt without touching parsing
--   (and the parsing can be tested without opening a window).
--
-- SPEED
--   The three git calls are started in PARALLEL and collected afterwards, which
--   keeps a full refresh under ~30ms on a large repository.
-- ============================================================================

local git = require("krs.git.cmd")

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

--- Shown when HEAD points at no branch.
M.detached_label = "HEAD (Detached)"

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

--- Reads the `## branch...upstream` header line of porcelain status.
--- @param header string Header line, including the leading `##`.
--- @return string branch
--- @return string|nil upstream
--- @return integer ahead
--- @return integer behind
function M.parse_branch(header)
	if header:sub(1, 2) ~= "##" then
		return M.detached_label, nil, 0, 0
	end

	local info = header:sub(4)
	local branch, upstream = info:match("^([^%.]+)%.%.%.(%S+)")
	local ahead = tonumber(header:match("%[.*ahead%s+(%d+)")) or 0
	local behind = tonumber(header:match("%[.*behind%s+(%d+)")) or 0

	if branch then
		return branch, upstream, ahead, behind
	end
	return (info:match("^([^%s]+)") or info), nil, ahead, behind
end

--- Sorts porcelain status entries into staged, unstaged and untracked.
--- Each line is `XY path`, where X is the index state and Y the work tree state,
--- so one file can legitimately appear in BOTH staged and unstaged.
---
--- @param lines string[] Status lines, header included.
--- @return table files `{ staged = {...}, unstaged = {...}, untracked = {...} }`
function M.parse_files(lines)
	local files = { staged = {}, unstaged = {}, untracked = {} }

	for index = 2, #lines do
		local line = lines[index]
		if #line >= 4 then
			local index_state = line:sub(1, 1)
			local worktree_state = line:sub(2, 2)
			local name = line:sub(4):gsub('^"', ""):gsub('"$', "")

			if index_state == "?" and worktree_state == "?" then
				table.insert(files.untracked, name)
			else
				if index_state ~= " " and index_state ~= "?" then
					table.insert(files.staged, name)
				end
				if worktree_state ~= " " and worktree_state ~= "?" then
					table.insert(files.unstaged, name)
				end
			end
		end
	end

	return files
end

--- Sums the added and deleted columns of `git diff --numstat` output.
--- Binary files report `-` instead of numbers and are skipped.
---
--- @param ... string[] One or more numstat outputs.
--- @return integer added
--- @return integer deleted
function M.sum_numstat(...)
	local added, deleted = 0, 0

	for _, lines in ipairs({ ... }) do
		for _, line in ipairs(lines) do
			local plus, minus = line:match("^(%d+)%s+(%d+)")
			if plus and minus then
				added = added + tonumber(plus)
				deleted = deleted + tonumber(minus)
			end
		end
	end
	return added, deleted
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Starts the three git calls a snapshot needs, without waiting for them.
--- @param cwd string|nil Repository directory. Defaults to the working directory.
--- @param secondary_alias string|nil Optional secondary repository alias.
--- @return table|nil handle nil when `cwd` is not a git repository.
function M.info_start(cwd, secondary_alias)
	cwd = cwd or vim.fn.getcwd()
	if secondary_alias then
		local ok_sec, sec = pcall(require, "krs.git.secondary")
		if ok_sec and sec then
			local argv_status = sec.build_cmd_args(secondary_alias, { "status", "--porcelain=v1", "-b" }, cwd)
			local argv_numstat = sec.build_cmd_args(secondary_alias, { "diff", "--numstat" }, cwd)
			local argv_numstat_cached = sec.build_cmd_args(secondary_alias, { "diff", "--cached", "--numstat" }, cwd)
			if argv_status then
				return {
					status_proc = vim.system(argv_status, { text = true }),
					numstat_proc = vim.system(argv_numstat, { text = true }),
					numstat_cached_proc = vim.system(argv_numstat_cached, { text = true }),
				}
			end
		end
	end

	if not git.is_repository(cwd) then
		return nil
	end

	return {
		status_proc = git.spawn({ "status", "--porcelain=v1", "-b" }, cwd),
		numstat_proc = git.spawn({ "diff", "--numstat" }, cwd),
		numstat_cached_proc = git.spawn({ "diff", "--cached", "--numstat" }, cwd),
	}
end

--- Waits for and parses the calls started by `info_start`.
--- @param handle table|nil Result of `info_start`.
--- @return table|nil info nil when `handle` is nil.
function M.info_finish(handle)
	if not handle then
		return nil
	end

	local status_lines = git.collect(handle.status_proc)
	local branch, upstream, ahead, behind = M.detached_label, nil, 0, 0
	local files = { staged = {}, unstaged = {}, untracked = {} }

	if #status_lines > 0 then
		branch, upstream, ahead, behind = M.parse_branch(status_lines[1])
		files = M.parse_files(status_lines)
	end

	local added, deleted = 0, 0
	if #files.staged > 0 or #files.unstaged > 0 then
		added, deleted = M.sum_numstat(git.collect(handle.numstat_proc), git.collect(handle.numstat_cached_proc))
	end
	local has_changes = (#files.staged + #files.unstaged + #files.untracked > 0)

	return {
		branch = branch,
		upstream = upstream,
		ahead = ahead,
		behind = behind,
		added = added,
		deleted = deleted,
		staged = files.staged,
		unstaged = files.unstaged,
		untracked = files.untracked,
		has_changes = has_changes,
	}
end

--- Snapshot of the repository at `cwd`. Blocking convenience wrapper around
--- `info_start` + `info_finish` for callers with no other work to overlap.
--- @param cwd string|nil Repository directory. Defaults to the working directory.
--- @param secondary_alias string|nil Optional secondary repository alias.
--- @return table|nil info nil when `cwd` is not a git repository.
function M.info(cwd, secondary_alias)
	return M.info_finish(M.info_start(cwd, secondary_alias))
end

return M
