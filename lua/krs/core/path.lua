-- ============================================================================
-- krs.core.path -- Cross-platform path helpers shared by every KRS module.
-- ============================================================================
-- WHY THIS EXISTS
--   Windows is a first-class target for this config, so paths arrive with mixed
--   separators: `C:\Users\me` from `vim.fn.expand`, `C:/Users/me` from LSP roots.
--   Every plugin used to repeat `p:gsub("\\", "/")` inline, so comparisons broke
--   whenever one call site forgot to normalize.
--
-- RULE OF THUMB
--   Normalize once, where a path enters your module. Then compare and join freely.
--
-- USAGE
--   local path = require("krs.core.path")
--   path.normalize([[C:\Users\me\project\]])  --> "C:/Users/me/project"
--   path.join(root, ".krsnvim", "tasks.json") --> "<root>/.krsnvim/tasks.json"
--   path.equals("C:/Proj", "c:\\proj")        --> true (Windows only)
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

--- True when running on Windows. Drives case-insensitive path comparison.
M.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Converts backslashes to forward slashes and strips a single trailing slash.
--- Root paths (`/`, `C:/`) keep their trailing slash so they stay valid.
---
--- @param p string|nil Path to normalize.
--- @return string normalized Normalized path, or "" when `p` is nil/empty.
function M.normalize(p)
	if not p or p == "" then
		return ""
	end
	local clean = p:gsub("\\", "/")
	if #clean > 1 and not clean:match("^%a:/$") then
		clean = clean:gsub("/$", "")
	end
	return clean
end

--- Joins path segments with `/`, normalizing the result.
--- Nil and empty segments are skipped so optional parts need no guard.
---
--- @param ... string|nil Path segments.
--- @return string path Joined, normalized path.
function M.join(...)
	local parts = {}
	-- `select` rather than `ipairs`, so a nil in the middle does not end the loop.
	for i = 1, select("#", ...) do
		local seg = select(i, ...)
		if seg and seg ~= "" then
			local piece = M.normalize(seg)
			-- Only the first segment may keep a leading slash (absolute POSIX path).
			if #parts > 0 then
				piece = piece:gsub("^/+", "")
			end
			table.insert(parts, piece)
		end
	end
	return M.normalize(table.concat(parts, "/"))
end

--- Compares two paths for equality, case-insensitively on Windows.
---
--- @param a string|nil First path.
--- @param b string|nil Second path.
--- @return boolean equal
function M.equals(a, b)
	local na, nb = M.normalize(a), M.normalize(b)
	if M.is_windows then
		return na:lower() == nb:lower()
	end
	return na == nb
end

--- Returns `path` relative to `root`, or nil when `path` is outside `root`.
--- Comparison follows the platform rules from `M.equals`.
---
--- @param path string Absolute path.
--- @param root string Absolute root directory.
--- @return string|nil relative Relative path without a leading slash.
function M.relative_to(path, root)
	local np, nr = M.normalize(path), M.normalize(root)
	local cmp_p, cmp_r = np, nr
	if M.is_windows then
		cmp_p, cmp_r = np:lower(), nr:lower()
	end
	if cmp_p == cmp_r then
		return ""
	end
	local prefix = cmp_r:gsub("/$", "") .. "/"
	if cmp_p:sub(1, #prefix) == prefix then
		return np:sub(#prefix + 1)
	end
	return nil
end

--- Alias for relative_to.
M.relative = M.relative_to

--- Directory of the buffer's file, falling back to the current working directory.
--- Used by every module that needs "where am I" before resolving a project root.
---
--- @param bufnr integer|nil Buffer handle. Defaults to the current buffer.
--- @return string dir Normalized directory path.
function M.buffer_dir(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr or vim.api.nvim_get_current_buf())
	if name == "" then
		return M.normalize(vim.fn.getcwd())
	end
	return M.normalize(vim.fs.dirname(name))
end

--- Creates a directory (and parents) when missing.
---
--- @param dir string Directory path.
--- @return string dir The same path, for chaining.
function M.ensure_dir(dir)
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir
end

--- True when the path exists as a readable file.
--- @param p string
--- @return boolean
function M.is_file(p)
	return vim.fn.filereadable(p) == 1
end

--- True when the path exists as a directory.
--- @param p string
--- @return boolean
function M.is_dir(p)
	return vim.fn.isdirectory(p) == 1
end

--- True when the path is an absolute filesystem path.
--- @param p string|nil
--- @return boolean
function M.is_absolute(p)
	if not p or p == "" then
		return false
	end
	local norm = M.normalize(p)
	return norm:sub(1, 1) == "/" or norm:match("^%a:") ~= nil
end

--- Returns the trailing file or directory name from a path.
--- @param p string|nil
--- @return string
function M.filename(p)
	if not p or p == "" then
		return ""
	end
	local norm = M.normalize(p)
	return vim.fs.basename(norm) or norm:match("[^/\\]+$") or norm
end
M.basename = M.filename

return M
