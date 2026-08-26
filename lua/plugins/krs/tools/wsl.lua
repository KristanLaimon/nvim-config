-- ============================================================================
-- KRS PLUGIN: WSL bridge -- detection, distro list, path translation.
-- ============================================================================
-- WHAT IT DOES
--   1. Detects whether WSL exists on this Windows host.
--   2. Lists installed distros (`wsl.exe -l -q`, UTF-16 output decoded here).
--   3. Understands `\\wsl.localhost\<Distro>\...` and `\\wsl$\<Distro>\...` UNC
--      paths, so a project opened over the network share is recognized as Linux.
--   4. Builds `wsl.exe -d <Distro> --cd <linux-path>` so the integrated terminal
--      starts inside the right distro and directory.
--   5. Keeps its own recent-projects list, because project.nvim's history does
--      not survive UNC paths well.
--
-- PURE MODULE
--   No commands, no keymaps, no autocmds -- other plugins call into it:
--   terminal.lua (shell command), file_explorer.lua (browse a distro),
--   dashboard.lua (recent WSL projects).
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Where WSL projects opened from the explorer are remembered.
	recent_projects_file = vim.fn.stdpath("data") .. "/wsl_recent_projects.json",

	--- How many recent projects to keep.
	max_recent_projects = 50,

	--- UNC prefixes that address a distro's filesystem, lowercased for matching.
	unc_prefixes = { "^//wsl%.localhost/", "^//wsl%$/" },

	--- Prefix used when building a browsable root path for a distro.
	unc_root = "//wsl.localhost/",
}

-- ============================================================================
-- DETECTION
-- ============================================================================

--- True on a Windows host.
--- @return boolean
function M.is_windows()
	return vim.fn.has("win32") == 1
end

--- True when WSL can be invoked on this machine.
--- @return boolean
function M.available()
	if vim.g.krs_testing or _G.krs_testing then
		return false
	end
	if not M.is_windows() then
		return false
	end
	return vim.fn.executable("wsl.exe") == 1 or vim.fn.executable("wsl") == 1
end

--- Installed distro names.
--- `wsl.exe -l -q` prints UTF-16LE, which Lua sees as ASCII interleaved with NUL
--- bytes, so every second byte is dropped before parsing.
---
--- @return string[] distros
function M.list_distros()
	if vim.g.krs_testing or _G.krs_testing then
		return {}
	end
	if not M.available() then
		return {}
	end

	local out = vim.fn.system({ "wsl.exe", "-l", "-q" })
	if vim.v.shell_error ~= 0 then
		return {}
	end

	local chars = {}
	for i = 1, #out, 2 do
		local byte = out:byte(i)
		if byte then
			table.insert(chars, string.char(byte))
		end
	end

	local distros = {}
	for line in table.concat(chars):gmatch("[^\r\n]+") do
		local trimmed = vim.trim(line)
		if trimmed ~= "" then
			table.insert(distros, trimmed)
		end
	end
	return distros
end

-- ============================================================================
-- PATH TRANSLATION
-- ============================================================================

--- Splits a WSL UNC path into its distro and Linux path.
--- @param p string|nil Windows path.
--- @return string|nil distro nil when `p` is not a WSL path.
--- @return string|nil linux_path Always starts with `/` when a distro was found.
function M.parse_wsl_path(p)
	if not p or p == "" then
		return nil
	end

	local normalized = p:gsub("\\", "/")
	local lowered = normalized:lower()

	local is_wsl_unc = false
	for _, prefix in ipairs(M.settings.unc_prefixes) do
		if lowered:match(prefix) then
			is_wsl_unc = true
			break
		end
	end
	if not is_wsl_unc then
		return nil
	end

	local distro, rest = normalized:match("^//[^/]+/([^/]+)(/.*)$")
	if not distro then
		-- Bare `\\wsl.localhost\Distro` with no trailing path.
		distro, rest = normalized:match("^//[^/]+/([^/]+)$"), "/"
	end
	if not distro then
		return nil
	end

	return distro, (rest and rest ~= "") and rest or "/"
end

--- True when the path points inside a WSL distro.
--- @param p string|nil
--- @return boolean
function M.is_wsl_path(p)
	return M.parse_wsl_path(p) ~= nil
end

--- Browsable UNC root of a distro's filesystem.
--- @param distro string Distro name.
--- @return string root
function M.distro_root(distro)
	return M.settings.unc_root .. distro
end

--- Command that opens a shell inside the distro owning `cwd`.
--- @param cwd string Windows working directory.
--- @return string|nil cmd nil when `cwd` is not a WSL path.
function M.shell_command_for_cwd(cwd)
	local distro, linux_path = M.parse_wsl_path(cwd)
	if not distro then
		return nil
	end

	distro = vim.trim(distro)
	if M.available() then
		for _, d in ipairs(M.list_distros()) do
			if d:lower() == distro:lower() then
				distro = d
				break
			end
		end
	end

	linux_path = linux_path:gsub("\\", "/"):gsub("/+$", "")
	if linux_path == "" then
		linux_path = "/"
	end

	if M.is_windows() then
		vim.env.MSYS_NO_PATHCONV = "1"
	end

	return string.format('wsl.exe -d %s --cd "%s"', distro, linux_path:gsub('"', '\\"'))
end

-- ============================================================================
-- RECENT PROJECTS
-- ============================================================================

--- Comparison form of a stored path.
--- @param p string|nil
--- @return string
local function recent_key(p)
	return (p or ""):gsub("\\", "/"):gsub("/$", ""):lower()
end

--- Stored list, newest first.
--- @return string[]
local function load_recent()
	return store.load(M.settings.recent_projects_file, {})
end

--- Records a WSL folder as recently opened. No-op for non-WSL paths.
--- @param p string Folder path.
function M.add_recent_project(p)
	if not M.is_wsl_path(p) then
		return
	end

	local target = (p:gsub("\\", "/"):gsub("/$", ""))
	local list = { target }
	for _, existing in ipairs(load_recent()) do
		if recent_key(existing) ~= recent_key(target) then
			table.insert(list, existing)
		end
	end

	if #list > M.settings.max_recent_projects then
		list = vim.list_slice(list, 1, M.settings.max_recent_projects)
	end
	store.save(M.settings.recent_projects_file, list)
end

--- Drops a folder from the recent list.
--- @param p string Folder path.
function M.remove_recent_project(p)
	local list = {}
	for _, existing in ipairs(load_recent()) do
		if recent_key(existing) ~= recent_key(p) then
			table.insert(list, existing)
		end
	end
	store.save(M.settings.recent_projects_file, list)
end

--- Recent WSL projects.
--- @param check_exists boolean|nil Filter out missing directories. Off by default:
---   probing a WSL path boots the distro, which would stall the dashboard.
--- @return string[] projects
function M.get_recent_projects(check_exists)
	local raw = load_recent()
	if check_exists ~= true then
		return raw
	end

	local list = {}
	for _, p in ipairs(raw) do
		if vim.fn.isdirectory(p) == 1 then
			table.insert(list, p)
		end
	end
	return list
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.Wsl = M

-- ============================================================================
-- LAZY.NVIM SPEC -- no config(): this module only reacts to direct calls.
-- ============================================================================

return setmetatable({
	name = "krs_wsl",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = true,
}, { __index = M })
