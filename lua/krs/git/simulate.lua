-- ============================================================================
-- krs.git.simulate -- Dry-run merge & rebase conflict simulation without touching CWD.
-- ============================================================================
-- WHAT IT DOES
--   Performs an in-memory 3-way merge or rebase dry-run using git merge-tree.
--   Zero changes to the working tree, index, or HEAD.
--   Predicts cleanly whether merging/rebasing branch A into branch B will cause
--   conflicts, lists every conflicting file and reason, and reports common ancestors.
-- ============================================================================

local git = require("krs.git.cmd")

local M = {}

--- Resolves full branch / ref name or HEAD fallback.
--- @param ref string|nil
--- @param cwd string|nil
--- @return string
local function resolve_ref(ref, cwd)
	if not ref or ref == "" or ref == "HEAD" then
		local current = git.lines({ "branch", "--show-current" }, cwd)[1]
		if current and current ~= "" then
			return current
		end
		return "HEAD"
	end
	return ref
end

--- Simulates merging incoming_branch into target_branch (target_branch <- incoming_branch).
--- Does NOT alter the working directory, index, or active branch.
---
--- @param target_branch string|nil Destination branch (defaults to current branch/HEAD).
--- @param incoming_branch string Source branch with changes to merge.
--- @param cwd string|nil Repository directory.
--- @return table result Simulation analysis.
function M.simulate_merge(target_branch, incoming_branch, cwd)
	cwd = cwd or vim.fn.getcwd()
	target_branch = resolve_ref(target_branch, cwd)
	incoming_branch = resolve_ref(incoming_branch, cwd)

	local result = {
		mode = "merge",
		target = target_branch,
		incoming = incoming_branch,
		cwd = cwd,
		is_clean = false,
		conflicts = {},
		conflicted_files = {},
		auto_merged = {},
		commits_ahead = 0,
		commits_behind = 0,
		merge_base = nil,
		merge_base_info = nil,
		changed_files = {},
		incoming_commits = {},
		error = nil,
	}

	if target_branch == incoming_branch then
		result.error = "Target and incoming branches are identical: " .. target_branch
		return result
	end

	-- 1. Find common merge-base ancestor
	local base_lines = git.lines({ "merge-base", target_branch, incoming_branch }, cwd)
	if not base_lines or #base_lines == 0 or base_lines[1] == "" then
		result.error =
			string.format("No common ancestor between '%s' and '%s' (unrelated histories)", target_branch, incoming_branch)
		return result
	end
	result.merge_base = base_lines[1]:gsub("%s+$", "")

	-- 2. Retrieve ancestor commit details
	local base_info_raw = git.lines({ "log", "-1", "--format=%h%x1f%s%x1f%an%x1f%cr", result.merge_base }, cwd)
	if base_info_raw and #base_info_raw > 0 then
		local h, s, an, cr = base_info_raw[1]:match("([^\31]+)\31([^\31]*)\31([^\31]*)\31(.*)")
		if h then
			result.merge_base_info = { hash = h, subject = s, author = an, date = cr }
		end
	end

	-- 3. Calculate ahead / behind commit counts
	local ahead_raw = git.lines({ "rev-list", "--count", target_branch .. ".." .. incoming_branch }, cwd)
	result.commits_ahead = tonumber(ahead_raw[1]) or 0

	local behind_raw = git.lines({ "rev-list", "--count", incoming_branch .. ".." .. target_branch }, cwd)
	result.commits_behind = tonumber(behind_raw[1]) or 0

	-- 4. Check for Fast-Forward eligibility
	if result.merge_base == git.lines({ "rev-parse", target_branch }, cwd)[1] then
		result.is_fast_forward = true
	end

	-- 5. Retrieve incoming commits list (up to 30)
	local commit_lines = git.lines({
		"log",
		"--pretty=format:%h%x1f%s%x1f%an%x1f%cr",
		"-n",
		"30",
		target_branch .. ".." .. incoming_branch,
	}, cwd)
	for _, line in ipairs(commit_lines) do
		local ch, cs, can, ccr = line:match("([^\31]+)\31([^\31]*)\31([^\31]*)\31(.*)")
		if ch then
			table.insert(result.incoming_commits, { hash = ch, subject = cs, author = can, date = ccr })
		end
	end

	-- 6. Retrieve changed files in incoming branch compared to base
	local diff_name_status = git.lines({ "diff", "--name-status", result.merge_base, incoming_branch }, cwd)
	for _, line in ipairs(diff_name_status) do
		local st, file = line:match("^([A-Z%d]+)%s+(.+)$")
		if st and file then
			table.insert(result.changed_files, { status = st:sub(1, 1), file = file })
		end
	end

	-- 7. Execute in-memory dry-run merge via git merge-tree --write-tree
	local cmd = git.build({ "merge-tree", "--write-tree", "--messages", target_branch, incoming_branch }, cwd)
	local run_res = vim.system(cmd):wait()

	if not run_res then
		result.error = "Failed to spawn git merge-tree process"
		return result
	end

	if run_res.code == 0 then
		result.is_clean = true
	else
		result.is_clean = false
	end

	-- Parse output for conflicts and auto-merges
	local stdout = (run_res.stdout or "") .. "\n" .. (run_res.stderr or "")
	local seen_conflicts = {}

	for line in stdout:gmatch("[^\r\n]+") do
		local conflict_file = line:match("CONFLICT%s*%([^%)]*%):%s*Merge conflict in%s*(.+)")
			or line:match("CONFLICT%s*%([^%)]*%):%s*(.+)")
		if conflict_file then
			conflict_file = conflict_file:gsub("%s+$", ""):gsub("^%s+", "")
			if not seen_conflicts[conflict_file] then
				seen_conflicts[conflict_file] = true
				table.insert(result.conflicted_files, conflict_file)
				table.insert(result.conflicts, {
					file = conflict_file,
					reason = line:match("CONFLICT%s*(%b())") or "(content conflict)",
					raw = line,
				})
			end
		end

		local auto_file = line:match("Auto%-merging%s*(.+)")
		if auto_file then
			auto_file = auto_file:gsub("%s+$", ""):gsub("^%s+", "")
			if not seen_conflicts[auto_file] then
				table.insert(result.auto_merged, auto_file)
			end
		end
	end

	-- Fallback check for conflict markers stage format: "100644 ... <stage>\t<file>"
	if not result.is_clean and #result.conflicted_files == 0 then
		for line in stdout:gmatch("[^\r\n]+") do
			local stage_file = line:match("%d%d%d%d%d%d%s+%x+%s+[123]\t(.+)")
			if stage_file and not seen_conflicts[stage_file] then
				seen_conflicts[stage_file] = true
				table.insert(result.conflicted_files, stage_file)
				table.insert(result.conflicts, { file = stage_file, reason = "(content/stage conflict)" })
			end
		end
	end

	return result
end

--- Simulates rebasing topic_branch onto upstream_branch (topic_branch -> upstream_branch).
--- Checks commit-by-commit to pinpoint which commit first causes conflicts.
---
--- @param upstream_branch string Target base to rebase onto.
--- @param topic_branch string|nil Branch being rebased (defaults to current/HEAD).
--- @param cwd string|nil
--- @return table result
function M.simulate_rebase(upstream_branch, topic_branch, cwd)
	cwd = cwd or vim.fn.getcwd()
	upstream_branch = resolve_ref(upstream_branch, cwd)
	topic_branch = resolve_ref(topic_branch, cwd)

	-- First run merge simulation between upstream and topic
	local merge_sim = M.simulate_merge(upstream_branch, topic_branch, cwd)
	merge_sim.mode = "rebase"

	if merge_sim.error then
		return merge_sim
	end

	-- Retrieve commits to replay in chronological order
	local commit_shas = git.lines({ "rev-list", "--reverse", upstream_branch .. ".." .. topic_branch }, cwd)
	merge_sim.rebase_total_commits = #commit_shas
	merge_sim.rebase_steps = {}

	if #commit_shas == 0 then
		merge_sim.is_clean = true
		merge_sim.rebase_notes = "Already up to date: 0 commits to replay."
		return merge_sim
	end

	-- If the overall tree is clean, every commit cleanly replays
	if merge_sim.is_clean then
		merge_sim.rebase_notes =
			string.format("All %d commit(s) can be cleanly replayed onto '%s'.", #commit_shas, upstream_branch)
		return merge_sim
	end

	-- Otherwise, step through commits to pinpoint the first conflicting commit
	local current_base = upstream_branch
	for i, sha in ipairs(commit_shas) do
		local check = git.lines({ "merge-tree", "--write-tree", current_base, sha }, cwd)
		local check_res = vim.system(git.build({ "merge-tree", "--write-tree", current_base, sha }, cwd)):wait()

		local commit_info = git.lines({ "log", "-1", "--format=%h%x1f%s%x1f%an", sha }, cwd)[1] or ""
		local ch, cs, can = commit_info:match("([^\31]+)\31([^\31]*)\31(.*)")

		if check_res and check_res.code ~= 0 then
			merge_sim.first_conflicting_commit = {
				index = i,
				total = #commit_shas,
				hash = ch or sha:sub(1, 7),
				subject = cs or "(no subject)",
				author = can or "unknown",
			}
			break
		elseif check_res and check_res.code == 0 then
			local new_tree = (check_res.stdout or ""):match("^(%x+)")
			if new_tree then
				current_base = new_tree
			end
		end
	end

	return merge_sim
end

return M
