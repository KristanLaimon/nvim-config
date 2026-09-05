-- ============================================================================
-- KRS PLUGIN: Git Center -- Repository Queries & Actions
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local git = lazy_req("krs.git.cmd")
local status = lazy_req("krs.git.status")
local path_util = lazy_req("krs.core.path")
local config = require("plugins.krs.git.git_center.config")

local M = {}

local env_ok, env_mod = pcall(require, "krs.core.environment")
local env = env_ok and env_mod.detect() or {}
local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

--- Runs git synchronously in the active repository target.
--- @param args string[] Arguments after `git`.
--- @param cwd string|nil
--- @return string[] output
function M.git_lines(args, cwd)
	local target = config.get_active_target()
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
function M.git_run(args, on_done, cwd)
	local target = config.get_active_target()
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

--- Snapshot of the repository at `cwd` (defaults to active submodule/root).
--- @param cwd string|nil Target repository directory.
--- @return table|nil info nil when the working directory is not a repository.
function M.get_git_info(cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	if target and target.is_secondary and target.repo_alias then
		return status.info(cwd, target.repo_alias)
	end
	return status.info(cwd)
end

--- Raw diff lines for one file, or its contents when it is untracked.
--- @param file string Path relative to the repository.
--- @param file_type string "staged" | "unstaged" | "untracked" | "commit".
--- @param cwd string|nil Repository directory.
--- @param commit_hash string|nil Optional commit hash for commit diffs.
--- @return string[] lines
--- @return boolean is_untracked
function M.raw_diff_for(file, file_type, cwd, commit_hash)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()

	if commit_hash or file_type == "commit" then
		local hash = commit_hash or (file_type ~= "commit" and file_type or nil)
		if hash then
			return git.lines({ "show", "--color=never", hash, "--", file }, cwd), false
		end
	end

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

--- Stages every unstaged and untracked change, reporting how many files moved.
--- Retries once after clearing a stale `index.lock`.
--- @param cwd string|nil Repository directory.
function M.stage_all_with_modal(cwd)
	cwd = cwd or (config.get_active_target() and config.get_active_target().full_path) or vim.fn.getcwd()
	git.clean_stale_lock(cwd)

	local info = M.get_git_info(cwd)
	if not info then
		config.notify("❌ Not inside a valid Git repository.", vim.log.levels.ERROR, config.settings.control_title)
		return
	end

	local pending = #info.unstaged + #info.untracked
	if pending == 0 then
		config.notify(
			"ℹ️ Nothing to stage: no unstaged or untracked changes found.",
			vim.log.levels.WARN,
			config.settings.control_title
		)
		return
	end

	local target = config.get_active_target()
	local args = { "add", "-A" }
	if target and target.is_secondary then
		args = { "add", "-u" }
	end

	local function execute(is_retry)
		local run_fn = git.run
		if target and target.is_secondary and target.repo_alias then
			local sec_ok, sec = pcall(require, "krs.git.secondary")
			if sec_ok and sec then
				run_fn = function(cmd_args, cb, dir)
					sec.run(target.repo_alias, cmd_args, cb, dir)
				end
			end
		end

		run_fn(args, function(ok, output)
			if ok then
				config.notify(
					string.format(
						"✅ Successfully staged %d file%s in %s!",
						pending,
						pending == 1 and "" or "s",
						target.name or "repository"
					),
					vim.log.levels.INFO,
					config.settings.control_title
				)
			elseif output:match("index%.lock") and not is_retry and git.clean_stale_lock(cwd) then
				execute(true)
				return
			else
				config.notify(
					"❌ Failed to stage changes:\n" .. (output ~= "" and output or "Error executing git add"),
					vim.log.levels.ERROR,
					config.settings.control_title
				)
			end

			local gc = package.loaded["plugins.krs.git.git_center"]
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
			end
		end, cwd)
	end

	execute(false)
end

return M
