-- ============================================================================
-- KRS PLUGIN: Secondary Git Repositories Manager & Switcher
-- ============================================================================
-- WHAT IT DOES
--   1. Provides CRUD commands (Create, Read, Rename, Update, Delete) for secondary
--      decoupled Git repositories in the current project (`.krsnvim/secondary_repos.json`).
--   2. Injects aliases into Neovim terminal sessions (Git Bash, PowerShell, Zsh).
--   3. Provides `:SecondaryGitSwitch` to switch Git Control Center (`<C-S-g>`) focus:
--      - Defaults to the secondary repo if only one exists.
--      - Opens a Telescope picker menu if more than one secondary repo exists.
--
-- EX COMMANDS
--   :SecondaryGit <alias> <args...>    Run a git command on a secondary repo
--   :SecondaryGitInit                  Initialize a new secondary bare git repo
--   :SecondaryGitManager               Interactive floating UI manager (CRUD)
--   :SecondaryGitRename                Rename an existing secondary repo alias
--   :SecondaryGitDelete                Delete a secondary repo definition
--   :SecondaryGitSwitch                Switch active secondary repo in Git Center / Telescope
--   :SecondaryGitSyncTerminal          Inject shell aliases to active terminals
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local sec_git = lazy_req("krs.git.secondary")
local ui = lazy_req("krs.core.ui")

local M = {}

M.settings = {
	width = 0.82,
	height = 0.70,
}

-- ---------------------------------------------------------------------------
-- Output Float Helper
-- ---------------------------------------------------------------------------

local function show_output_float(title, lines)
	local buf, win = ui.float({
		lines = lines,
		title = " " .. title .. " ",
		width = 0.82,
		height = 0.70,
		modifiable = false,
	})
	ui.close_on_keys(buf, win)
	return buf, win
end

-- ---------------------------------------------------------------------------
-- CRUD Ex Commands Implementation
-- ---------------------------------------------------------------------------

--- Runs git command for a secondary repository and shows output.
--- @param args string
function M.cmd_run(args)
	if not args or args == "" then
		M.open_manager()
		return
	end

	local parts = {}
	for w in args:gmatch("%S+") do
		table.insert(parts, w)
	end

	local alias_name = parts[1]
	table.remove(parts, 1)

	if #parts == 0 then
		table.insert(parts, "status")
	end

	local repo = sec_git.find_repo(alias_name)
	if not repo then
		vim.notify(
			"Secondary repository alias '" .. alias_name .. "' not found.",
			vim.log.levels.WARN,
			{ title = "Secondary Git" }
		)
		return
	end

	sec_git.run(alias_name, parts, function(ok, output)
		local lines = vim.split(output or "", "\n")
		if #lines == 0 or (#lines == 1 and lines[1] == "") then
			lines = { "(Command returned no output)" }
		end

		local title = "Git [" .. alias_name .. "]: " .. table.concat(parts, " ")
		show_output_float(title, lines)
	end)
end

--- Prompts for missing fields and initializes a secondary repo.
--- @param alias_arg string|nil
--- @param git_dir_arg string|nil
--- @param remote_arg string|nil
function M.cmd_init(alias_arg, git_dir_arg, remote_arg)
	local function do_init(alias, git_dir, remote)
		if not alias or alias == "" or not git_dir or git_dir == "" then
			vim.notify(
				"Initialization cancelled: Alias and Git Directory are required.",
				vim.log.levels.WARN,
				{ title = "Secondary Git" }
			)
			return
		end

		sec_git.init_repo({
			alias = alias,
			git_dir = git_dir,
			remote = remote or "",
			show_untracked = false,
		}, function(ok, msg)
			if ok then
				vim.notify("✅ " .. msg, vim.log.levels.INFO, { title = "Secondary Git" })
				if M.manager_win and vim.api.nvim_win_is_valid(M.manager_win) then
					M.refresh_manager()
				end
			else
				vim.notify("❌ " .. msg, vim.log.levels.ERROR, { title = "Secondary Git" })
			end
		end)
	end

	if alias_arg and alias_arg ~= "" and git_dir_arg and git_dir_arg ~= "" then
		do_init(alias_arg, git_dir_arg, remote_arg)
		return
	end

	vim.ui.input({ prompt = "Secondary Repo Alias (e.g. krsgit): ", default = alias_arg or "krsgit" }, function(alias)
		if not alias or alias == "" then
			return
		end
		vim.ui.input({
			prompt = "Bare Git Directory (e.g. ./.git-krs or $HOME/.secrets-repo.git): ",
			default = git_dir_arg or ("./.git-" .. alias),
		}, function(git_dir)
			if not git_dir or git_dir == "" then
				return
			end
			vim.ui.input(
				{ prompt = "Optional Remote URL (e.g. git@github.com:user/repo.git): ", default = remote_arg or "" },
				function(remote)
					do_init(alias, git_dir, remote)
				end
			)
		end)
	end)
end

--- Renames an existing secondary repository alias.
--- @param old_alias string|nil
--- @param new_alias string|nil
function M.cmd_rename(old_alias, new_alias)
	local function do_rename(old_name, new_name)
		if not old_name or old_name == "" or not new_name or new_name == "" then
			return
		end
		local repo = sec_git.find_repo(old_name)
		if not repo then
			vim.notify(
				"Secondary repository alias '" .. old_name .. "' not found.",
				vim.log.levels.WARN,
				{ title = "Secondary Git" }
			)
			return
		end

		local updated = vim.deepcopy(repo)
		updated.alias = new_name
		updated.name = new_name

		local ok_add = sec_git.add_repo(updated)
		if ok_add and old_name ~= new_name then
			sec_git.remove_repo(old_name)
		end

		sec_git.inject_terminal_aliases()
		vim.notify(
			"Renamed secondary repository '" .. old_name .. "' -> '" .. new_name .. "'",
			vim.log.levels.INFO,
			{ title = "Secondary Git" }
		)
		if M.manager_win and vim.api.nvim_win_is_valid(M.manager_win) then
			M.refresh_manager()
		end
	end

	if old_alias and old_alias ~= "" and new_alias and new_alias ~= "" then
		do_rename(old_alias, new_alias)
		return
	end

	vim.ui.input({ prompt = "Current Repo Alias to Rename: ", default = old_alias or "" }, function(old_name)
		if not old_name or old_name == "" then
			return
		end
		vim.ui.input({ prompt = "New Alias Name: ", default = new_alias or old_name }, function(new_name)
			do_rename(old_name, new_name)
		end)
	end)
end

--- Deletes a secondary repository from configuration.
--- @param alias string|nil
function M.cmd_delete(alias)
	local function do_delete(alias_name)
		if not alias_name or alias_name == "" then
			return
		end
		local ok = sec_git.remove_repo(alias_name)
		if ok then
			sec_git.inject_terminal_aliases()
			vim.notify(
				"Removed secondary repository '" .. alias_name .. "' from configuration.",
				vim.log.levels.INFO,
				{ title = "Secondary Git" }
			)
			if M.manager_win and vim.api.nvim_win_is_valid(M.manager_win) then
				M.refresh_manager()
			end
		else
			vim.notify(
				"Secondary repository '" .. alias_name .. "' not found.",
				vim.log.levels.WARN,
				{ title = "Secondary Git" }
			)
		end
	end

	if alias and alias ~= "" then
		do_delete(alias)
		return
	end

	vim.ui.input({ prompt = "Alias of Secondary Repo to Delete: " }, function(alias_name)
		do_delete(alias_name)
	end)
end

--- Updates fields of an existing secondary repository entry.
--- @param repo table
function M.update_repo_fields(repo)
	if not repo or not repo.alias then
		return
	end

	vim.ui.input({ prompt = "Alias: ", default = repo.alias }, function(alias)
		if not alias or alias == "" then
			return
		end
		vim.ui.input({ prompt = "Bare Git Directory: ", default = repo.git_dir }, function(git_dir)
			if not git_dir or git_dir == "" then
				return
			end
			vim.ui.input({ prompt = "Remote URL: ", default = repo.remote or "" }, function(remote)
				vim.ui.input({ prompt = "Description: ", default = repo.description or "" }, function(desc)
					local old_alias = repo.alias
					local updated = {
						alias = alias,
						name = alias,
						git_dir = git_dir,
						work_tree = repo.work_tree or ".",
						show_untracked = repo.show_untracked,
						remote = remote or "",
						description = desc or "",
					}
					sec_git.add_repo(updated)
					if old_alias ~= alias then
						sec_git.remove_repo(old_alias)
					end
					sec_git.inject_terminal_aliases()
					vim.notify("Updated secondary repository '" .. alias .. "'", vim.log.levels.INFO, { title = "Secondary Git" })
					if M.manager_win and vim.api.nvim_win_is_valid(M.manager_win) then
						M.refresh_manager()
					end
				end)
			end)
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Telescope Selector & Git Control Center Integration
-- ---------------------------------------------------------------------------

--- Switches active repository target in Git Control Center (`<C-S-g>`).
--- If 0 secondary repos: notifies user.
--- If 1 secondary repo: defaults to it directly.
--- If >1 secondary repos: launches Telescope menu selector.
function M.switch_secondary_repo()
	local cwd = vim.fn.getcwd()
	local config = sec_git.load(cwd)
	local repos = config.repositories or {}

	if #repos == 0 then
		vim.notify(
			"No secondary git repositories configured. Run :SecondaryGitInit to create one.",
			vim.log.levels.WARN,
			{ title = "Secondary Git" }
		)
		return
	end

	local function activate_target_in_git_center(repo_alias)
		local ok_gc, gc = pcall(require, "plugins.krs.git_center")
		if not ok_gc or not gc then
			return
		end

		local function find_and_select()
			local found_idx = nil
			for idx, target in ipairs(gc.submodules or {}) do
				if target.repo_alias == repo_alias or (repo_alias == "root" and target.is_root) then
					found_idx = idx
					break
				end
			end
			if found_idx then
				gc.active_submodule_idx = found_idx
				if gc.refresh then
					gc.refresh()
				end
				vim.notify(
					"Switched Git Center to repository: " .. repo_alias,
					vim.log.levels.INFO,
					{ title = "Secondary Git" }
				)
			end
		end

		if gc.is_open() then
			find_and_select()
		else
			gc.toggle_git_center()
			vim.schedule(function()
				find_and_select()
			end)
		end
	end

	-- If only 1 secondary repository exists, default directly to it
	if #repos == 1 then
		activate_target_in_git_center(repos[1].alias)
		return
	end

	-- Multiple secondary repositories -> launch Telescope selector
	local has_telescope, pickers = pcall(require, "telescope.pickers")
	local has_finders, finders = pcall(require, "telescope.finders")
	local has_conf, conf = pcall(require, "telescope.config")
	local has_actions, actions = pcall(require, "telescope.actions")
	local has_action_state, action_state = pcall(require, "telescope.actions.state")

	if not (has_telescope and has_finders and has_conf and has_actions and has_action_state) then
		-- Fallback to vim.ui.select if Telescope is unavailable
		local items = { "📦 Main Root Repository" }
		for _, r in ipairs(repos) do
			table.insert(items, "🐙 " .. r.alias .. " (" .. r.git_dir .. ")")
		end
		vim.ui.select(items, { prompt = "Select Secondary Git Repository:" }, function(choice, idx)
			if not choice or not idx then
				return
			end
			if idx == 1 then
				activate_target_in_git_center("root")
			else
				activate_target_in_git_center(repos[idx - 1].alias)
			end
		end)
		return
	end

	local entries = {
		{ alias = "root", display = "📦 Main Root Repository", dir = cwd, description = "Primary git repository" },
	}
	for _, r in ipairs(repos) do
		table.insert(entries, {
			alias = r.alias,
			display = string.format(
				"🐙 %-12s | Bare: %-28s | Remote: %s",
				r.alias,
				r.git_dir,
				(r.remote and r.remote ~= "") and r.remote or "None"
			),
			dir = r.git_dir,
			description = r.description or "",
		})
	end

	pickers
		.new({}, {
			prompt_title = " 🐙 Select Active Secondary Git Repository ",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.alias .. " " .. entry.dir .. " " .. entry.description,
					}
				end,
			}),
			sorter = conf.values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection and selection.value then
						activate_target_in_git_center(selection.value.alias)
					end
				end)
				return true
			end,
		})
		:find()
end

-- ---------------------------------------------------------------------------
-- Interactive Manager Float UI (CRUD)
-- ---------------------------------------------------------------------------

function M.refresh_manager()
	if not M.manager_buf or not vim.api.nvim_buf_is_valid(M.manager_buf) then
		return
	end

	local config = sec_git.load()
	local repos = config.repositories or {}
	local lines = {}

	table.insert(lines, "  🐙 SECONDARY GIT REPOSITORIES (Dotfiles Pattern)")
	table.insert(lines, "  " .. string.rep("─", 74))
	table.insert(lines, string.format("  %-12s %-16s %-30s %-10s", "ALIAS", "NAME", "GIT DIR", "UNTRACKED"))
	table.insert(lines, "  " .. string.rep("─", 74))

	if #repos == 0 then
		table.insert(lines, "  (No secondary repositories configured. Press 'c' or 'i' to initialize one)")
	else
		for _, repo in ipairs(repos) do
			local untracked_str = repo.show_untracked and "Show" or "Hide"
			local line = string.format(
				"  %-12s %-16s %-30s %-10s",
				repo.alias,
				repo.name:sub(1, 16),
				repo.git_dir:sub(1, 30),
				untracked_str
			)
			table.insert(lines, line)
		end
	end

	table.insert(lines, "  " .. string.rep("─", 74))
	table.insert(lines, "  [c/i] Create   [r] Rename   [u] Edit   [x/d] Delete   [w] Switch Repo")
	table.insert(lines, "  [s] Status     [p] Push     [l] Log    [t] Sync Term  [e] Edit JSON")
	table.insert(lines, "  [q/Esc] Close")

	vim.bo[M.manager_buf].modifiable = true
	vim.api.nvim_buf_set_lines(M.manager_buf, 0, -1, false, lines)
	vim.bo[M.manager_buf].modifiable = false
end

function M.open_manager()
	if M.manager_win and vim.api.nvim_win_is_valid(M.manager_win) then
		vim.api.nvim_set_current_win(M.manager_win)
		return
	end

	local buf, win = ui.float({
		title = " 🐙 Secondary Git Repositories Manager ",
		width = M.settings.width,
		height = M.settings.height,
		modifiable = false,
	})

	M.manager_buf = buf
	M.manager_win = win

	M.refresh_manager()

	local function get_selected_repo()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_idx = cursor[1]
		local config = sec_git.load()
		local repos = config.repositories or {}
		-- Header takes 5 lines
		local repo_idx = line_idx - 4
		if repo_idx >= 1 and repo_idx <= #repos then
			return repos[repo_idx], repo_idx
		end
		return nil, nil
	end

	local opts = { buffer = buf, noremap = true, silent = true }

	vim.keymap.set("n", "c", function()
		M.cmd_init()
	end, opts)
	vim.keymap.set("n", "i", function()
		M.cmd_init()
	end, opts)
	vim.keymap.set("n", "a", function()
		M.cmd_init()
	end, opts)

	vim.keymap.set("n", "r", function()
		local repo = get_selected_repo()
		if repo then
			M.cmd_rename(repo.alias)
		end
	end, opts)

	vim.keymap.set("n", "u", function()
		local repo = get_selected_repo()
		if repo then
			M.update_repo_fields(repo)
		end
	end, opts)

	vim.keymap.set("n", "w", function()
		pcall(vim.api.nvim_win_close, win, true)
		M.switch_secondary_repo()
	end, opts)

	vim.keymap.set("n", "s", function()
		local repo = get_selected_repo()
		if repo then
			M.cmd_run(repo.alias .. " status")
		end
	end, opts)

	vim.keymap.set("n", "p", function()
		local repo = get_selected_repo()
		if repo then
			sec_git.run(repo.alias, { "push" }, function(ok, output)
				vim.notify(
					(ok and "✅ Push successful:\n" or "❌ Push failed:\n") .. output,
					ok and vim.log.levels.INFO or vim.log.levels.ERROR,
					{ title = "Secondary Git Push" }
				)
			end)
		end
	end, opts)

	vim.keymap.set("n", "l", function()
		local repo = get_selected_repo()
		if repo then
			M.cmd_run(repo.alias .. " log -n 10 --oneline")
		end
	end, opts)

	vim.keymap.set("n", "t", function()
		sec_git.inject_terminal_aliases()
		vim.notify(
			"🖥️ Secondary Git aliases injected into active terminals.",
			vim.log.levels.INFO,
			{ title = "Secondary Git" }
		)
	end, opts)

	vim.keymap.set("n", "e", function()
		pcall(vim.api.nvim_win_close, win, true)
		local config_path = sec_git.get_config_path()
		vim.cmd("edit " .. vim.fn.fnameescape(config_path))
	end, opts)

	vim.keymap.set("n", "x", function()
		local repo = get_selected_repo()
		if repo then
			M.cmd_delete(repo.alias)
		end
	end, opts)

	vim.keymap.set("n", "d", function()
		local repo = get_selected_repo()
		if repo then
			M.cmd_delete(repo.alias)
		end
	end, opts)

	ui.close_on_keys(buf, win)
end

-- ---------------------------------------------------------------------------
-- Setup Hooks & Ex Commands
-- ---------------------------------------------------------------------------

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("SecondaryGit", function(opts)
		M.cmd_run(opts.args)
	end, { nargs = "*", desc = "Run git command on secondary repo (e.g. :SecondaryGit secgit status)" })

	vim.api.nvim_create_user_command("SecondaryGitInit", function(opts)
		local parts = {}
		for w in opts.args:gmatch("%S+") do
			table.insert(parts, w)
		end
		M.cmd_init(parts[1], parts[2], parts[3])
	end, { nargs = "*", desc = "Initialize secondary decoupled git repo (Dotfiles pattern)" })

	vim.api.nvim_create_user_command("SecondaryGitRename", function(opts)
		local parts = {}
		for w in opts.args:gmatch("%S+") do
			table.insert(parts, w)
		end
		M.cmd_rename(parts[1], parts[2])
	end, { nargs = "*", desc = "Rename a secondary repository alias" })

	vim.api.nvim_create_user_command("SecondaryGitDelete", function(opts)
		M.cmd_delete(opts.args)
	end, { nargs = "?", desc = "Delete a secondary repository definition" })

	vim.api.nvim_create_user_command("SecondaryGitSwitch", function()
		M.switch_secondary_repo()
	end, { desc = "Switch active repository in Git Control Center (Telescope selector)" })

	vim.api.nvim_create_user_command("GitCenterSwitchSecondary", function()
		M.switch_secondary_repo()
	end, { desc = "Switch active repository in Git Control Center" })

	vim.api.nvim_create_user_command("SecondaryGitManager", function()
		M.open_manager()
	end, { desc = "Open Secondary Git Repositories Manager" })

	vim.api.nvim_create_user_command("KrsSecondaryGit", function()
		M.open_manager()
	end, { desc = "Open Secondary Git Repositories Manager" })

	vim.api.nvim_create_user_command("SecondaryGitSyncTerminal", function()
		sec_git.inject_terminal_aliases()
		vim.notify("🖥️ Secondary Git aliases synced to terminals.", vim.log.levels.INFO, { title = "Secondary Git" })
	end, { desc = "Sync secondary git aliases into active terminal buffers" })

	-- Register command palette commands if palette module exists
	local ok_cp, cp = pcall(require, "plugins.krs.command_palette")
	if ok_cp and cp and cp.add_command then
		cp.add_command({
			name = "🐙 Secondary Git Repositories Manager (Create / Rename / Delete)",
			cmd = "SecondaryGitManager",
			category = "Git",
		})
		cp.add_command({
			name = "🐙 Switch Active Secondary Git Repository (Telescope / Git Center)",
			cmd = "SecondaryGitSwitch",
			category = "Git",
		})
		cp.add_command({
			name = "🐙 Initialize Secondary Git Repository (Dotfiles)",
			cmd = "SecondaryGitInit",
			category = "Git",
		})
		cp.add_command({ name = "🐙 Rename Secondary Git Repository", cmd = "SecondaryGitRename", category = "Git" })
		cp.add_command({ name = "🐙 Delete Secondary Git Repository", cmd = "SecondaryGitDelete", category = "Git" })
		cp.add_command({
			name = "🐙 Sync Secondary Git Aliases to Terminals",
			cmd = "SecondaryGitSyncTerminal",
			category = "Git",
		})
	end
end

return setmetatable({
	name = "krs_secondary_git",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = {
		"SecondaryGit",
		"SecondaryGitInit",
		"SecondaryGitRename",
		"SecondaryGitDelete",
		"SecondaryGitSwitch",
		"GitCenterSwitchSecondary",
		"SecondaryGitManager",
		"KrsSecondaryGit",
		"SecondaryGitSyncTerminal",
	},
	config = M.setup,
}, { __index = M })
