-- ============================================================================
-- krs.git.submodules -- Submodule discovery, listing and sorting.
-- ============================================================================
-- WHAT IT PRODUCES
--   A list of repository targets for Git Center:
--     [1] Root git repository (cwd / project root)
--     [2..n] Submodule repositories in alphabetical order
--
-- WHY THIS LIVES IN LAYER 2 (krs.git)
--   Pure Lua parsing and resolution with no UI or keymap dependencies, so it
--   can be unit-tested without floating windows or Neovim UI state.
-- ============================================================================

local git = require("krs.git.cmd")
local path_util = require("krs.core.path")
local store = require("krs.core.store")
local project = require("krs.core.project")

local M = {}

--- Config file (shared with Git Center's own settings) where the discovered
--- submodule list is cached, keyed by a fingerprint of `.gitmodules`.
M.cache_filename = "git-center.json"

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

--- Parses `git submodule status` lines into relative submodule paths.
--- Output lines look like:
---   ` 68b5a03bf18274a2b130e9d57a91176b91176b91 path/to/submodule (heads/main)`
---   `-68b5a03bf18274a2b130e9d57a91176b91176b91 path/to/submodule`
---   `+68b5a03bf18274a2b130e9d57a91176b91176b91 path/to/submodule`
---   `U68b5a03bf18274a2b130e9d57a91176b91176b91 path/to/submodule`
---
--- @param lines string[] Output lines from `git submodule status`.
--- @return string[] paths Clean list of relative submodule paths.
function M.parse_submodules(lines)
	local paths = {}
	local seen = {}

	for _, line in ipairs(lines or {}) do
		local clean_line = vim.trim(line)
		if clean_line ~= "" then
			-- Format: optional indicator [ + - U], commit hash, space, path
			local rel_path = clean_line:match("^[%+%-U%s]?%x+%s+(%S+)")
			if not rel_path then
				-- Fallback for lines like "submodule.<name>.path <path>" from git config
				rel_path = clean_line:match("^submodule%..*%.path%s+(.+)$")
			end

			if rel_path and rel_path ~= "" then
				rel_path = path_util.normalize(rel_path)
				if not seen[rel_path] then
					seen[rel_path] = true
					table.insert(paths, rel_path)
				end
			end
		end
	end

	return paths
end

-- ---------------------------------------------------------------------------
-- Discovery & Resolution
-- ---------------------------------------------------------------------------

--- Cheap identity for the current `.gitmodules`: mtime + size. Changes
--- whenever git (or the user, or Git Center) adds, removes or edits a
--- submodule entry -- from ANY tool, not just this plugin -- which is what
--- invalidates the cache below without needing to watch for writes.
--- @param root_cwd string
--- @return string|nil fingerprint nil when there is no `.gitmodules`.
local function gitmodules_fingerprint(root_cwd)
	local stat = (vim.uv or vim.loop).fs_stat(root_cwd .. "/.gitmodules")
	if not stat then
		return nil
	end
	return string.format("%d:%d:%d", stat.mtime.sec, stat.mtime.nsec, stat.size)
end

--- Runs the two possible git queries and parses their result. Blocking.
--- @param root_cwd string
--- @param status_lines string[] Output of `git submodule status`.
--- @return string[] paths Alphabetically sorted relative submodule paths.
local function finish_discovery(root_cwd, status_lines)
	local lines = status_lines
	if #lines == 0 then
		-- Fallback check for .gitmodules config if status returned nothing.
		lines = git.lines({ "config", "--file", ".gitmodules", "--get-regexp", "^submodule\\..*\\.path$" }, root_cwd)
	end

	local paths = M.parse_submodules(lines)
	table.sort(paths, function(a, b)
		return a:lower() < b:lower()
	end)
	return paths
end

--- Starts submodule discovery for `root_cwd`.
---
--- Returns the path list immediately -- no git call at all -- when there is
--- no `.gitmodules`, or when a previous discovery already cached this exact
--- `.gitmodules` fingerprint. Otherwise starts (but does not wait for) the
--- `git submodule status` process and returns a finisher to call once other
--- work has been started too, so the two round trips overlap instead of
--- happening one after another.
---
--- @param root_cwd string|nil Repository root directory.
--- @return string[]|nil paths Immediate result, or nil when a finisher follows.
--- @return (fun(): string[])|nil finish Call once to collect and cache the result.
function M.discover_start(root_cwd)
	root_cwd = root_cwd or vim.fn.getcwd()
	if not git.is_repository(root_cwd) then
		return {}, nil
	end

	local fingerprint = gitmodules_fingerprint(root_cwd)
	if not fingerprint then
		return {}, nil
	end

	local cfg_path = project.config_path(M.cache_filename, root_cwd)
	local cached = store.load(cfg_path, {})
	if cached.submodules_fingerprint == fingerprint and type(cached.submodule_paths) == "table" then
		return cached.submodule_paths, nil
	end

	local proc = git.spawn({ "submodule", "status" }, root_cwd)

	return nil,
		function()
			local paths = finish_discovery(root_cwd, git.collect(proc))

			local data = store.load(cfg_path, {})
			data.submodules_fingerprint = fingerprint
			data.submodule_paths = paths
			store.save(cfg_path, data)

			return paths
		end
end

--- Discovers submodules inside `root_cwd`. Blocking convenience wrapper
--- around `discover_start` for callers that have no other work to overlap it
--- with (tests, one-off scripts).
---
--- @param root_cwd string|nil Repository root directory.
--- @return string[] paths Alphabetically sorted relative submodule paths.
function M.discover(root_cwd)
	local immediate, finish = M.discover_start(root_cwd)
	if immediate then
		return immediate
	end
	return finish()
end

--- Builds repository tabs from an already-discovered submodule path list.
--- @param root_cwd string Root repository directory (already normalized).
--- @param submodule_paths string[]
--- @return table[] targets Array of `{ name, path, is_root, full_path }`
local function build_targets(root_cwd, submodule_paths)
	local root_name = vim.fs.basename(root_cwd) or "Root"
	if root_name == "" then
		root_name = "Root"
	end

	local targets = {
		{
			name = string.format("📦 %s (Root)", root_name),
			path = ".",
			is_root = true,
			full_path = root_cwd,
		},
	}

	local has_sec_config = (vim.uv or vim.loop).fs_stat(root_cwd .. "/.krsnvim/secondary_repos.json")
	if has_sec_config then
		local sec_ok, sec_git = pcall(require, "krs.git.secondary")
		if sec_ok and sec_git then
			local config = sec_git.load(root_cwd)
			for _, repo in ipairs(config.repositories or {}) do
				table.insert(targets, {
					name = string.format("🐙 %s", repo.alias),
					path = repo.alias,
					is_root = false,
					is_secondary = true,
					repo_alias = repo.alias,
					full_path = root_cwd,
				})
			end
		end
	end

	for _, sub_path in ipairs(submodule_paths) do
		table.insert(targets, {
			name = string.format("📁 %s", sub_path),
			path = sub_path,
			is_root = false,
			full_path = path_util.join(root_cwd, sub_path),
		})
	end

	return targets
end

--- Starts building the complete list of repository tabs for Git Center. Same
--- immediate-or-finisher shape as `discover_start`.
--- @param root_cwd string|nil Root repository directory.
--- @return table[]|nil targets
--- @return (fun(): table[])|nil finish
function M.list_start(root_cwd)
	root_cwd = path_util.normalize(root_cwd or vim.fn.getcwd())

	local immediate, finish = M.discover_start(root_cwd)
	if immediate then
		return build_targets(root_cwd, immediate), nil
	end

	return nil, function()
		return build_targets(root_cwd, finish())
	end
end

--- Builds the complete list of repository tabs for Git Center. Blocking
--- convenience wrapper around `list_start`.
---
--- @param root_cwd string|nil Root repository directory.
--- @return table[] targets Array of `{ name, path, is_root, full_path }`
function M.list(root_cwd)
	local immediate, finish = M.list_start(root_cwd)
	if immediate then
		return immediate
	end
	return finish()
end

return M
