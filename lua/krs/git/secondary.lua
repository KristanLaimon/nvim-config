-- ============================================================================
-- krs.git.secondary -- Decoupled Secondary Git Repositories (Dotfiles pattern).
-- ============================================================================
-- WHAT IT DOES
--   1. Manages secondary decoupled Git repositories that share the current work tree
--      but store their history in an independent bare .git directory.
--   2. Reads and writes project configuration in `.krsnvim/secondary_repos.json`.
--   3. Generates shell aliases (PowerShell & Bash/Zsh) for use in terminal sessions.
--   4. Injects terminal aliases into Neovim's built-in terminal buffers upon launch.
--   5. Provides sync and async command execution over secondary git repos.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local git = lazy_req("krs.git.cmd")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path_util = lazy_req("krs.core.path")

local M = {}

M.config_filename = "secondary_repos.json"

-- ---------------------------------------------------------------------------
-- Path & Config Resolution
-- ---------------------------------------------------------------------------

--- Path to project's `secondary_repos.json` configuration file.
--- @param cwd string|nil
--- @return string path
function M.get_config_path(cwd)
	cwd = cwd or vim.fn.getcwd()
	return project.config_path(M.config_filename, cwd)
end

--- Normalizes a relative git_dir path to dotfile format (e.g. `./git-krs` -> `./.git-krs`).
--- @param git_dir string|nil
--- @return string normalized_dir
function M.normalize_git_dir(git_dir)
	if not git_dir or git_dir == "" then return git_dir end
	local is_abs = git_dir:match("^/") or git_dir:match("^%a:") or git_dir:match("^%~") or git_dir:match("^%$HOME") or git_dir:match("^%%USERPROFILE%%")
	if not is_abs then
		local clean = git_dir:gsub("\\", "/")
		if clean:sub(1, 2) == "./" then
			clean = clean:sub(3)
		end
		if not clean:match("^%.") then
			clean = "." .. clean
		end
		return "./" .. clean
	end
	return git_dir
end

--- Normalizes a path, expanding `$HOME`, `~`, `%USERPROFILE%` and relative paths.
--- @param path string|nil
--- @param cwd string|nil
--- @return string resolved_path
function M.resolve_path(path, cwd)
	cwd = cwd or vim.fn.getcwd()
	if not path or path == "" or path == "." then
		return path_util.normalize(cwd)
	end

	local clean = path:gsub("\\", "/")
	local home = (vim.env.HOME or vim.env.USERPROFILE or "~"):gsub("\\", "/")

	if clean:sub(1, 2) == "~/" or clean == "~" then
		clean = home .. clean:sub(2)
	elseif clean:find("%$HOME") then
		clean = clean:gsub("%$HOME", home)
	elseif clean:find("%%USERPROFILE%%") then
		clean = clean:gsub("%%USERPROFILE%%", home)
	end

	if not clean:match("^/") and not clean:match("^%a:") and not clean:match("^//") then
		clean = cwd .. "/" .. clean
	end

	clean = clean:gsub("/%./", "/")
	return path_util.normalize(clean)
end

--- Loads secondary repositories configuration for the project.
--- @param cwd string|nil
--- @return table config `{ version = 1, repositories = { ... } }`
function M.load(cwd)
	cwd = cwd or vim.fn.getcwd()
	local file_path = M.get_config_path(cwd)
	local data = store.load(file_path, { version = 1, repositories = {} })

	if not data or type(data) ~= "table" then
		return { version = 1, repositories = {} }
	end

	if not data.repositories or type(data.repositories) ~= "table" then
		data.repositories = {}
	end

	-- Auto-migrate non-dotted relative git_dir paths (e.g. ./git-krs -> ./.git-krs)
	local modified = false
	for _, repo in ipairs(data.repositories) do
		if repo.git_dir then
			local norm = M.normalize_git_dir(repo.git_dir)
			if norm ~= repo.git_dir then
				local old_p = M.resolve_path(repo.git_dir, cwd)
				local new_p = M.resolve_path(norm, cwd)
				if vim.fn.isdirectory(old_p) == 1 and vim.fn.isdirectory(new_p) == 0 then
					pcall(vim.fn.rename, old_p, new_p)
				end
				repo.git_dir = norm
				modified = true
			end
		end
	end

	if modified then
		store.save(file_path, data)
	end

	return data
end

--- Saves secondary repositories configuration for the project.
--- @param config table
--- @param cwd string|nil
--- @return boolean success
function M.save(config, cwd)
	cwd = cwd or vim.fn.getcwd()
	local file_path = M.get_config_path(cwd)
	config = config or { version = 1, repositories = {} }
	config.version = config.version or 1
	config.repositories = config.repositories or {}
	local ok, _ = store.save(file_path, config)
	return ok
end

--- Finds a secondary repo entry by alias or name.
--- @param alias_or_name string
--- @param cwd string|nil
--- @return table|nil repo
--- @return integer|nil index
function M.find_repo(alias_or_name, cwd)
	if not alias_or_name or alias_or_name == "" then
		return nil, nil
	end
	local config = M.load(cwd)
	for idx, repo in ipairs(config.repositories) do
		if repo.alias == alias_or_name or repo.name == alias_or_name then
			return repo, idx
		end
	end
	return nil, nil
end

--- Adds or updates a secondary repository definition.
--- @param repo_def table `{ alias, git_dir, work_tree?, name?, show_untracked?, remote?, description? }`
--- @param cwd string|nil
--- @return boolean success
function M.add_repo(repo_def, cwd)
	if not repo_def or not repo_def.alias or not repo_def.git_dir then
		return false
	end
	cwd = cwd or vim.fn.getcwd()
	local config = M.load(cwd)

	local new_entry = {
		name = repo_def.name or repo_def.alias,
		alias = repo_def.alias,
		git_dir = M.normalize_git_dir(repo_def.git_dir),
		work_tree = repo_def.work_tree or ".",
		show_untracked = repo_def.show_untracked == true or (repo_def.show_untracked == nil and false),
		remote = repo_def.remote or "",
		description = repo_def.description or "",
	}

	local existing, idx = M.find_repo(repo_def.alias, cwd)
	if existing and idx then
		config.repositories[idx] = new_entry
	else
		table.insert(config.repositories, new_entry)
	end

	local ok = M.save(config, cwd)
	if ok then
		M.generate_scripts(cwd)
	end
	return ok
end

--- Removes a secondary repository definition by alias or name.
--- @param alias_or_name string
--- @param cwd string|nil
--- @return boolean success
function M.remove_repo(alias_or_name, cwd)
	cwd = cwd or vim.fn.getcwd()
	local config = M.load(cwd)
	local _, idx = M.find_repo(alias_or_name, cwd)
	if not idx then
		return false
	end

	table.remove(config.repositories, idx)
	local ok = M.save(config, cwd)
	if ok then
		M.generate_scripts(cwd)
	end
	return ok
end

-- ---------------------------------------------------------------------------
-- Command Construction & Execution
-- ---------------------------------------------------------------------------

--- Removes stray bare Git repository files (HEAD, config, description, etc.) if they were created directly in the project root.
--- @param cwd string|nil
--- @return boolean cleaned
function M.cleanup_stray_bare_files(cwd)
	cwd = cwd or vim.fn.getcwd()
	local norm_cwd = path_util.normalize(cwd)
	if vim.fn.isdirectory(norm_cwd .. "/.git") == 1 then
		return false -- Standard repository, do not touch
	end

	local has_head = vim.fn.filereadable(norm_cwd .. "/HEAD") == 1
	local has_config = vim.fn.filereadable(norm_cwd .. "/config") == 1
	local has_objects = vim.fn.isdirectory(norm_cwd .. "/objects") == 1

	if has_head and has_config and has_objects then
		pcall(vim.fn.delete, norm_cwd .. "/HEAD")
		pcall(vim.fn.delete, norm_cwd .. "/config")
		pcall(vim.fn.delete, norm_cwd .. "/description")
		pcall(vim.fn.delete, norm_cwd .. "/hooks", "rf")
		pcall(vim.fn.delete, norm_cwd .. "/info", "rf")
		pcall(vim.fn.delete, norm_cwd .. "/objects", "rf")
		return true
	end
	return false
end

--- Builds git argv for a secondary repository.
--- @param repo_or_alias table|string Repo table or alias string.
--- @param git_args string|string[] Arguments after git (e.g. `{"status"}`).
--- @param cwd string|nil
--- @return string[]|nil argv
function M.build_cmd_args(repo_or_alias, git_args, cwd)
	cwd = cwd or vim.fn.getcwd()
	local repo = type(repo_or_alias) == "table" and repo_or_alias or M.find_repo(repo_or_alias, cwd)
	if not repo then
		return nil
	end

	local resolved_git_dir = M.resolve_path(repo.git_dir, cwd)
	local resolved_work_tree = M.resolve_path(repo.work_tree, cwd)

	local prefix_args = {
		"--git-dir=" .. resolved_git_dir,
		"--work-tree=" .. resolved_work_tree,
	}

	local parsed_args = {}
	if type(git_args) == "string" then
		for word in git_args:gmatch("%S+") do
			table.insert(parsed_args, word)
		end
	elseif type(git_args) == "table" then
		vim.list_extend(parsed_args, git_args)
	end

	-- If subcommand is "add", insert "-f" so files ignored by the main repository's .gitignore can be added
	if parsed_args[1] == "add" then
		local has_force = false
		for i = 2, #parsed_args do
			if parsed_args[i] == "-f" or parsed_args[i] == "--force" then
				has_force = true
				break
			end
		end
		if not has_force then
			table.insert(parsed_args, 2, "-f")
		end
	end

	vim.list_extend(prefix_args, parsed_args)
	return git.build(prefix_args, cwd)
end

--- Runs git synchronously on a secondary repository and returns stdout lines.
--- @param repo_or_alias table|string
--- @param git_args string|string[]
--- @param cwd string|nil
--- @return string[] lines
function M.lines(repo_or_alias, git_args, cwd)
	cwd = cwd or vim.fn.getcwd()
	local argv = M.build_cmd_args(repo_or_alias, git_args, cwd)
	if not argv then
		return {}
	end

	local res = vim.system(argv, { text = true }):wait()
	local stdout = res.stdout or ""
	if stdout == "" then
		return {}
	end
	return vim.split(stdout, "[\r\n]+", { trimempty = true })
end

--- Runs git asynchronously on a secondary repository.
--- @param repo_or_alias table|string
--- @param git_args string|string[]
--- @param on_done fun(ok: boolean, output: string)
--- @param cwd string|nil
function M.run(repo_or_alias, git_args, on_done, cwd)
	cwd = cwd or vim.fn.getcwd()
	local argv = M.build_cmd_args(repo_or_alias, git_args, cwd)
	if not argv then
		if on_done then
			on_done(false, "Secondary repository not found: " .. tostring(repo_or_alias))
		end
		return
	end

	vim.system(
		argv,
		{ text = true },
		vim.schedule_wrap(function(result)
			local output = ((result.stderr or "") .. (result.stdout or "")):gsub("%s+$", "")
			if on_done then
				on_done(result.code == 0, output)
			end
		end)
	)
end

-- ---------------------------------------------------------------------------
-- Repository Initialization (Dotfiles Pattern)
-- ---------------------------------------------------------------------------

--- Initializes a secondary decoupled Git repository.
--- Creates the bare repository directory if missing, configures `status.showUntrackedFiles no`
--- if untracked files should be hidden by default, creates dedicated `.gitignore.<alias>`, adds optional remote, updates config and scripts.
---
--- @param opts table `{ alias, git_dir, name?, work_tree?, show_untracked?, remote?, description? }`
--- @param on_done fun(ok: boolean, msg: string)|nil
--- @param cwd string|nil
function M.init_repo(opts, on_done, cwd)
	cwd = cwd or vim.fn.getcwd()
	if not opts or not opts.alias or not opts.git_dir then
		if on_done then
			on_done(false, "Error: alias and git_dir are required")
		end
		return
	end

	local resolved_git_dir = M.resolve_path(opts.git_dir, cwd)
	local resolved_work_tree = M.resolve_path(opts.work_tree or ".", cwd)

	if resolved_git_dir == resolved_work_tree then
		if on_done then
			on_done(false, "Error: git_dir cannot be the same as project root directory. Use a subfolder like './git-krs' or '$HOME/.secrets-repo.git'")
		end
		return
	end

	-- Clean any stray bare files created in project root by accident
	M.cleanup_stray_bare_files(cwd)

	-- Ensure target bare repo directory exists
	vim.fn.mkdir(resolved_git_dir, "p")

	-- Ensure dedicated .gitignore.<alias> exists in work tree
	local custom_gitignore_path = resolved_work_tree .. "/.gitignore." .. opts.alias
	if vim.fn.filereadable(custom_gitignore_path) == 0 then
		store.write_file(custom_gitignore_path, "# Custom .gitignore for secondary repository: " .. opts.alias .. "\n# Add patterns to ignore specifically for this repository\nnode_modules/\n")
	end

	-- 1. Run git init --bare
	local init_argv = git.build({ "init", "--bare", resolved_git_dir }, cwd)
	vim.system(init_argv, { text = true }, vim.schedule_wrap(function(res_init)
		if res_init.code ~= 0 then
			if on_done then
				on_done(false, "Failed to initialize bare repository at " .. resolved_git_dir .. ": " .. (res_init.stderr or ""))
			end
			return
		end

		-- Function to configure untracked, custom excludes file and remote
		local function finish_setup()
			local steps = {}

			-- Hide untracked files by default if requested (dotfiles pattern standard)
			if opts.show_untracked == false or opts.show_untracked == nil then
				table.insert(steps, {
					"--git-dir=" .. resolved_git_dir,
					"--work-tree=" .. resolved_work_tree,
					"config",
					"status.showUntrackedFiles",
					"no",
				})
			end

			-- Configure custom excludes file (.gitignore.<alias>)
			table.insert(steps, {
				"--git-dir=" .. resolved_git_dir,
				"--work-tree=" .. resolved_work_tree,
				"config",
				"core.excludesFile",
				custom_gitignore_path,
			})

			-- Disable advice about addIgnoredFile
			table.insert(steps, {
				"--git-dir=" .. resolved_git_dir,
				"--work-tree=" .. resolved_work_tree,
				"config",
				"advice.addIgnoredFile",
				"false",
			})

			-- Add remote if provided
			if opts.remote and opts.remote ~= "" then
				table.insert(steps, {
					"--git-dir=" .. resolved_git_dir,
					"--work-tree=" .. resolved_work_tree,
					"remote",
					"add",
					"origin",
					opts.remote,
				})
			end

			local function run_next(step_idx)
				if step_idx > #steps then
					-- Register in config
					local ok_save = M.add_repo(opts, cwd)
					M.inject_terminal_aliases(nil, cwd)

					if on_done then
						if ok_save then
							on_done(true, "Successfully initialized secondary repository '" .. opts.alias .. "' at " .. resolved_git_dir)
						else
							on_done(false, "Initialized bare repo but failed to save configuration.")
						end
					end
					return
				end

				local argv = git.build(steps[step_idx], cwd)
				vim.system(argv, { text = true }, vim.schedule_wrap(function()
					run_next(step_idx + 1)
				end))
			end

			run_next(1)
		end

		finish_setup()
	end))
end

-- ---------------------------------------------------------------------------
-- Shell Alias Generator & Injection
-- ---------------------------------------------------------------------------

--- Generates alias/function string for terminal execution.
--- @param repo table Secondary repo definition
--- @param shell_type string "ps1" or "sh"
--- @param cwd string|nil
--- @return string alias_code
function M.generate_alias(repo, shell_type, cwd)
	cwd = cwd or vim.fn.getcwd()
	local alias_name = repo.alias
	local resolved_git_dir = M.resolve_path(repo.git_dir, cwd)
	local resolved_work_tree = M.resolve_path(repo.work_tree, cwd)

	if shell_type == "ps1" then
		return string.format(
			'function %s { if ($args.Count -gt 0 -and $args[0] -eq "add") { git --git-dir="%s" --work-tree="%s" add -f $args[1..($args.Count-1)] } else { git --git-dir="%s" --work-tree="%s" $args } }',
			alias_name,
			resolved_git_dir,
			resolved_work_tree,
			resolved_git_dir,
			resolved_work_tree
		)
	else
		return string.format(
			'%s() { if [ "$1" = "add" ]; then shift; git --git-dir="%s" --work-tree="%s" add -f "$@"; else git --git-dir="%s" --work-tree="%s" "$@"; fi; }',
			alias_name,
			resolved_git_dir,
			resolved_work_tree,
			resolved_git_dir,
			resolved_work_tree
		)
	end
end

--- Generates helper script files (`.krsnvim/secondary_aliases.sh` and `.krsnvim/secondary_aliases.ps1`).
--- @param cwd string|nil
function M.generate_scripts(cwd)
	cwd = cwd or vim.fn.getcwd()
	local config = M.load(cwd)
	local project_dir = project.config_dir(cwd)

	local sh_lines = { "#!/usr/bin/env bash", "# Auto-generated secondary git aliases for KRS" }
	local ps1_lines = { "# Auto-generated secondary git aliases for KRS (PowerShell)" }

	for _, repo in ipairs(config.repositories) do
		table.insert(sh_lines, M.generate_alias(repo, "sh", cwd))
		table.insert(ps1_lines, M.generate_alias(repo, "ps1", cwd))
	end

	store.write_file(project_dir .. "/secondary_aliases.sh", table.concat(sh_lines, "\n") .. "\n")
	store.write_file(project_dir .. "/secondary_aliases.ps1", table.concat(ps1_lines, "\n") .. "\n")
end

--- Detects whether a terminal buffer is running PowerShell ("ps1") or POSIX shell ("sh").
--- @param buf integer Buffer handle
--- @return string shell_type "ps1" or "sh"
local function detect_shell_type(buf)
	if vim.b[buf] and vim.b[buf].krs_is_wsl then
		return "sh"
	end

	local bufname = (vim.api.nvim_buf_get_name(buf) or ""):lower()
	if bufname:find("bash") or bufname:find("zsh") or bufname:find("msys") or bufname:find("mingw") or bufname:find("git") then
		return "sh"
	end
	if bufname:find("powershell") or bufname:find("pwsh") or bufname:find("cmd.exe") then
		return "ps1"
	end

	local shell = (vim.o.shell or ""):lower()
	if shell:find("bash") or shell:find("zsh") or shell:find("sh") or shell:find("msys") or shell:find("mingw") or shell:find("git") then
		return "sh"
	end
	if shell:find("powershell") or shell:find("pwsh") or shell:find("cmd") then
		return "ps1"
	end

	if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
		return "ps1"
	end

	return "sh"
end

--- Injects alias definitions into Neovim terminal buffer(s).
--- @param bufnr integer|nil Specific terminal buffer, or nil for all active terminals.
--- @param cwd string|nil
function M.inject_terminal_aliases(bufnr, cwd)
	cwd = cwd or vim.fn.getcwd()
	local config = M.load(cwd)
	if #config.repositories == 0 then
		return
	end

	local bufs = bufnr and { bufnr } or vim.api.nvim_list_bufs()

	for _, buf in ipairs(bufs) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
			local job_id = vim.b[buf].terminal_job_id
			if job_id and job_id > 0 then
				local shell_type = detect_shell_type(buf)
				local eol = (shell_type == "ps1") and "\r\n" or "\n"

				for _, repo in ipairs(config.repositories) do
					local cmd = M.generate_alias(repo, shell_type, cwd)
					pcall(vim.api.nvim_chan_send, job_id, cmd .. eol)
				end
			end
		end
	end
end

return M
