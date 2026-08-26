-- ============================================================================
-- KRS PLUGIN: Line Endings Manager (LF vs CRLF).
-- ============================================================================
-- WHAT IT DOES
--   1. Ensures Neovim auto-detects and preserves line endings (LF vs CRLF).
--   2. Provides `:ChangeLineEndings` / `:KrsChangeLineEndings` with an interactive
--      UI selection menu to set line endings for the CURRENT file buffer.
--   3. Provides `:ChangeRepoLineEndings` / `:KrsChangeRepoLineEndings` with an
--      interactive UI selection menu to batch-convert line endings across the
--      WHOLE REPOSITORY, updating active open buffers in memory as well.
-- ============================================================================

local M = {}

M.settings = {
	title = "Line Endings Manager",
}

--- Format options mapping.
local FORMAT_SPECS = {
	unix = { label = "Unix (LF - \\n)", fmt = "unix" },
	dos = { label = "Windows (CRLF - \\r\\n)", fmt = "dos" },
	mac = { label = "Classic Mac (CR - \\r)", fmt = "mac" },
}

--- Checks if a file path is likely a binary file.
--- @param filepath string
--- @return boolean is_binary
local function is_binary_file(filepath)
	local f = io.open(filepath, "rb")
	if not f then
		return true
	end
	local chunk = f:read(1024)
	f:close()
	if not chunk then
		return false
	end
	if chunk:find("\0", 1, true) then
		return true
	end
	return false
end

--- Checks if `path` resides inside `root_dir`.
--- @param root_dir string
--- @param path string
--- @return boolean
local function is_subpath(root_dir, path)
	local norm_root = vim.fs.normalize(root_dir):lower()
	local norm_path = vim.fs.normalize(path):lower()
	return norm_path:sub(1, #norm_root) == norm_root
end

--- Interactively changes line endings for the CURRENT file buffer.
--- @param target_fmt string|nil Optional target format ("unix", "dos", "mac").
function M.change_current_file(target_fmt)
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local function apply_format(fmt)
		if not fmt or (fmt ~= "unix" and fmt ~= "dos" and fmt ~= "mac") then
			return
		end
		local old_fmt = vim.bo[buf].fileformat
		vim.bo[buf].fileformat = fmt
		if old_fmt ~= fmt then
			vim.bo[buf].modified = true
		end
		local label = (FORMAT_SPECS[fmt] and FORMAT_SPECS[fmt].label) or fmt
		vim.notify("📄 Line endings for current file set to " .. label, vim.log.levels.INFO, {
			title = M.settings.title,
		})
	end

	if target_fmt then
		apply_format(target_fmt)
		return
	end

	local items = {
		{ label = "Unix (LF - \\n)", fmt = "unix" },
		{ label = "Windows (CRLF - \\r\\n)", fmt = "dos" },
		{ label = "Classic Mac (CR - \\r)", fmt = "mac" },
	}

	local current_fmt = vim.bo[buf].fileformat
	local prompt_title = "Select Line Ending for Current File (Current: " .. current_fmt:upper() .. "):"

	vim.ui.select(items, {
		prompt = prompt_title,
		format_item = function(item)
			local mark = (item.fmt == current_fmt) and " (Active)" or ""
			return item.label .. mark
		end,
	}, function(choice)
		if choice then
			apply_format(choice.fmt)
		end
	end)
end

--- Interactively converts line endings for the WHOLE REPOSITORY / WORKSPACE.
--- @param target_fmt string|nil Optional target format ("unix" or "dos").
--- @param root_dir string|nil Optional root directory path.
function M.change_repo(target_fmt, root_dir)
	local project_mod_ok, project_mod = pcall(require, "krs.core.project")
	root_dir = root_dir or (project_mod_ok and project_mod.root() or vim.fn.getcwd())

	local function process_conversion(fmt)
		if not fmt or (fmt ~= "unix" and fmt ~= "dos") then
			return
		end

		local ignore_dirs = {
			[".git"] = true,
			["node_modules"] = true,
			["vendor"] = true,
			[".krsnvim"] = true,
			[".DS_Store"] = true,
			[".idea"] = true,
			[".vscode"] = true,
			["dist"] = true,
			["build"] = true,
			["target"] = true,
			["bin"] = true,
			["obj"] = true,
		}

		local uv = vim.uv or vim.loop
		local files = {}

		local function scan_dir(dir)
			local handle = uv.fs_scandir(dir)
			if not handle then
				return
			end
			while true do
				local name, type_name = uv.fs_scandir_next(handle)
				if not name then
					break
				end
				if not ignore_dirs[name] then
					local fullpath = dir .. "/" .. name
					if type_name == "directory" then
						scan_dir(fullpath)
					elseif type_name == "file" then
						table.insert(files, fullpath)
					elseif not type_name then
						local stat = uv.fs_stat(fullpath)
						if stat then
							if stat.type == "directory" then
								scan_dir(fullpath)
							elseif stat.type == "file" then
								table.insert(files, fullpath)
							end
						end
					end
				end
			end
		end

		scan_dir(root_dir)

		local converted_count = 0

		for _, filepath in ipairs(files) do
			if not is_binary_file(filepath) then
				local rf = io.open(filepath, "rb")
				if rf then
					local content = rf:read("*a")
					rf:close()

					if content then
						local new_content = content
						if fmt == "unix" then
							new_content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
						elseif fmt == "dos" then
							new_content = content:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n", "\r\n")
						end

						if new_content ~= content then
							local wf = io.open(filepath, "wb")
							if wf then
								wf:write(new_content)
								wf:close()
								converted_count = converted_count + 1
							end
						end
					end
				end
			end
		end

		-- Sync open Neovim buffers in memory
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
				local name = vim.api.nvim_buf_get_name(buf)
				if name and name ~= "" and is_subpath(root_dir, name) then
					vim.bo[buf].fileformat = fmt
					pcall(vim.cmd, "silent! checktime " .. buf)
				end
			end
		end

		local fmt_label = fmt == "unix" and "LF (unix)" or "CRLF (windows/dos)"
		vim.notify(
			string.format("🌐 Converted %d file(s) to %s across the repository.", converted_count, fmt_label),
			vim.log.levels.INFO,
			{ title = M.settings.title }
		)
	end

	if target_fmt then
		process_conversion(target_fmt)
		return
	end

	local items = {
		{ label = "Unix (LF - \\n) [Whole Repository]", fmt = "unix" },
		{ label = "Windows (CRLF - \\r\\n) [Whole Repository]", fmt = "dos" },
	}

	vim.ui.select(items, {
		prompt = "Convert Whole Repository Line Endings:",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if choice then
			process_conversion(choice.fmt)
		end
	end)
end

--- Binds user commands and sets up line endings manager.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local user_commands = {
		ChangeLineEndings = {
			fn = function(opts)
				local arg = opts.args ~= "" and opts.args:lower() or nil
				M.change_current_file(arg)
			end,
			desc = "Change line endings for current file buffer (LF / CRLF / CR)",
		},
		ChangeRepoLineEndings = {
			fn = function(opts)
				local arg = opts.args ~= "" and opts.args:lower() or nil
				M.change_repo(arg)
			end,
			desc = "Change line endings for the entire repository (LF / CRLF)",
		},
	}

	for cmd_name, spec in pairs(user_commands) do
		if vim.fn.exists(":" .. cmd_name) == 0 then
			vim.api.nvim_create_user_command(cmd_name, spec.fn, {
				nargs = "?",
				complete = function()
					return { "unix", "dos", "mac" }
				end,
				desc = spec.desc,
			})
		end
	end
end

return setmetatable({
	name = "krs_line_endings",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "ChangeLineEndings", "ChangeRepoLineEndings" },
	config = M.setup,
}, { __index = M })
