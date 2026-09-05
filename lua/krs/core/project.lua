-- ============================================================================
-- krs.core.project -- Project root detection and `.krsnvim/` config resolution.
-- ============================================================================
-- WHY THIS EXISTS
--   Four modules (tasks, launch_profiles, dap_breakpoints, type_injector) each
--   re-implemented "walk up until a project marker, then look for my JSON file in
--   .krsnvim / .krslocal / .nvimkrs". The lookup order is a user-visible contract:
--   getting it wrong silently reads the wrong project's settings.
--
-- THE CONTRACT
--   * Root = nearest ancestor directory containing a marker from `M.root_markers`.
--   * A per-project config file is searched in `M.config_dirs`, in order.
--   * When nothing exists yet, the FIRST candidate is returned so writers create
--     `.krsnvim/<name>` by default.
--
-- USAGE
--   local project = require("krs.core.project")
--   local root = project.root()                          -- cwd-based fallback
--   local file = project.config_path("tasks.json", root)  -- <root>/.krsnvim/tasks.json
-- ============================================================================

local path = require("krs.core.path")

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration -- tweak these two lists to change project detection globally
-- ---------------------------------------------------------------------------

--- Files/directories that mark a project root, searched upward from the buffer.
--- Order matters only for readability; `vim.fs.find` returns the nearest match.
M.root_markers = {
	".krsnvim",
	".vscode",
	".nvimkrs",
	"Makefile",
	"package.json",
	"Cargo.toml",
	".git",
	"go.mod",
	"pyproject.toml",
}

--- Directories that may hold per-project KRS config, in lookup order.
--- The first entry is also the write target when no config exists yet.
M.config_dirs = { ".krsnvim", ".vscode", ".krslocal", ".nvimkrs" }

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Resolves the project root for a buffer by walking up to the nearest marker.
--- Falls back to the current working directory when no marker is found.
---
--- @param bufnr integer|nil Buffer handle. Defaults to the current buffer.
--- @return string root Project root directory (not normalized, matches `vim.fs`).
function M.root(bufnr)
	local current = bufnr and path.buffer_dir(bufnr) or vim.fn.expand("%:p:h")
	if current == "" then
		return path.normalize(vim.fn.getcwd())
	end

	current = path.normalize(current)
	local cwd = path.normalize(vim.fn.getcwd())

	-- If current is inside cwd, search for root markers up to cwd first
	local rel = path.relative_to(current, cwd)
	if rel then
		local match = vim.fs.find(M.root_markers, { upward = true, path = current, stop = cwd })
		if match and #match > 0 then
			local found_dir = path.normalize(vim.fs.dirname(match[1]))
			if found_dir ~= cwd then
				-- Check if cwd itself has a project root marker (.git, .krsnvim, go.mod, package.json, etc.)
				local cwd_match = vim.fs.find(M.root_markers, { upward = false, path = cwd, limit = 1 })
				if cwd_match and #cwd_match > 0 then
					-- If found_dir is a git repository/submodule of its own, respect found_dir.
					-- Otherwise, the main project workspace root (cwd) wins over subfolder markers.
					local is_git_repo = path.is_dir(path.join(found_dir, ".git")) or path.is_file(path.join(found_dir, ".git"))
					if not is_git_repo then
						return cwd
					end
				end
			end
			return found_dir
		end
		return cwd
	end

	-- If current is outside cwd, search upward freely
	local match = vim.fs.find(M.root_markers, { upward = true, path = current })
	if match and #match > 0 then
		return path.normalize(vim.fs.dirname(match[1]))
	end
	return cwd
end

--- Resolves a per-project config file, e.g. `tasks.json` or `launch.json`.
--- Returns the first existing candidate; when none exist, returns the path under
--- the first entry of `M.config_dirs` so callers can create it.
---
--- @param name string File name, such as "launch.json".
--- @param root string|nil Project root. Defaults to `M.root()`.
--- @return string filepath Absolute, normalized path.
--- @return boolean exists True when the returned file is already on disk.
function M.config_path(name, root)
	root = path.normalize(root or M.root())
	for _, dir in ipairs(M.config_dirs) do
		local candidate = path.join(root, dir, name)
		if path.is_file(candidate) then
			return candidate, true
		end
	end
	return path.join(root, M.config_dirs[1], name), false
end

--- Directory a new config file should be written to (`<root>/.krsnvim`),
--- created if missing.
---
--- @param root string|nil Project root. Defaults to `M.root()`.
--- @return string dir Normalized, existing directory.
function M.config_dir(root)
	return path.ensure_dir(path.join(path.normalize(root or M.root()), M.config_dirs[1]))
end

return M
