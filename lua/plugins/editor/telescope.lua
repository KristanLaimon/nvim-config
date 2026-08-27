-- ============================================================================
-- PLUGIN: telescope.nvim -- the fuzzy finder, plus a folder-opening picker.
-- ============================================================================
-- WHAT THIS FILE ADDS ON TOP OF TELESCOPE
--   1. Two file finders with a sensible search strategy per project:
--        <C-k>           respect .gitignore (git ls-files inside a repo)
--        <C-A-k> / <C-?> ignore it entirely (everything, including hidden)
--      Both are also exported as `_G.FindFilesGitignore` / `_G.FindFilesNoIgnore`,
--      which is what the keymaps in lua/keymaps/search.lua call.
--   2. `:TelescopeOpenFolder` -- browse directories and ADOPT one as the project:
--      close splits, drop the old buffers, cd, record it, reopen the tree.
--   3. `:TelescopeFindFilesSplit{Left,Below,Above,Right}` -- find a file and open
--      it in a split.
--
-- KEY OWNERSHIP
--   The <C-S-h/j/k/l> split keys are bound in lua/keymaps/search.lua, not
--   here, because <C-S-j> has to fall through to the DAP repl during a debug
--   session. This file only provides the commands they drive.
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Find files, honouring .gitignore.
	find_keys = { "<C-k>", "<C-K>" },

	--- Find files, ignoring .gitignore. Several aliases: Alt/Meta combinations
	--- arrive differently depending on terminal and GUI.
	find_all_keys = {
		"<C-A-k>",
		"<C-A-K>",
		"<C-M-k>",
		"<C-M-K>",
		"<A-C-k>",
		"<A-C-K>",
		"<M-C-k>",
		"<M-C-K>",
		"<C-S-/>",
		"<C-?>",
	},
	live_grep_key = "<C-f>",
	help_tags_key = nil,
	open_folder_key = "<C-S-y>",
	desktop_explorer_key = "<C-/>",
	wsl_explorer_key = nil,

	--- Directory scan depth for the folder picker, and what it never descends into.
	folder_scan_depth = 3,
	folder_excludes = { ".git", "node_modules", ".cache" },

	--- Direction -> Ex command and label, for the split finders.
	splits = {
		h = { command = "leftabove vsplit", label = "Left (←)" },
		j = { command = "rightbelow split", label = "Down (↓)" },
		k = { command = "leftabove split", label = "Up (↑)" },
		l = { command = "rightbelow vsplit", label = "Right (→)" },
	},
}

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return {
	"nvim-telescope/telescope.nvim",
	branch = "master",
	cmd = {
		"Telescope",
		"TelescopeOpenFolder",
		"TelescopeFileBrowserDesktop",
		"TelescopeFindFilesSplitLeft",
		"TelescopeFindFilesSplitBelow",
		"TelescopeFindFilesSplitAbove",
		"TelescopeFindFilesSplitRight",
		"TelescopeFindFilesGitignore",
		"TelescopeFindFilesNoIgnore",
	},
	keys = {
		{
			"<C-k>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					require("telescope.builtin").git_files({ recurse_submodules = true })
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-K>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					require("telescope.builtin").git_files({ recurse_submodules = true })
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-/>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					require("telescope.builtin").git_files({ recurse_submodules = true })
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-_>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					require("telescope.builtin").git_files({ recurse_submodules = true })
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-A-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<C-A-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<C-M-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<C-M-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<A-C-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<A-C-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<M-C-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<M-C-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{ "<C-f>", "<cmd>Telescope live_grep<CR>", mode = { "n", "i" }, desc = "Telescope live grep" },
		{ "<C-S-y>", "<cmd>TelescopeOpenFolder<CR>", mode = { "n", "i" }, desc = "Telescope open folder" },
		{ "<C-/>", "<cmd>TelescopeFileBrowserDesktop<CR>", mode = { "n", "i", "v" }, desc = "Open Desktop File Explorer" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"ahmedkhalf/project.nvim",
		"nvim-telescope/telescope-file-browser.nvim",
	},
	config = function()
		local telescope = require("telescope")
		local builtin = require("telescope.builtin")
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")
		local themes = require("telescope.themes")

		telescope.setup({
			defaults = {
				mappings = {
					n = {
						-- `?` shows the context help for whatever picker is open.
						["?"] = function()
							require("plugins.krs.context_help").show_help()
						end,
					},
				},
			},
		})

		-- ------------------------------------------------------------------
		-- File finders
		-- ------------------------------------------------------------------

		--- True when the working directory is inside a git repository.
		--- @return boolean
		local function in_git_repo()
			local cwd = vim.fn.getcwd()
			if vim.fn.isdirectory(cwd .. "/.git") == 1 then
				return true
			end

			local result = vim.system({ "git", "-C", cwd, "rev-parse", "--is-inside-work-tree" }, { text = true }):wait()
			return result and result.code == 0 and result.stdout ~= nil and result.stdout:match("true") ~= nil
		end

		--- Ensures focus is in a main code buffer window before launching a picker,
		--- preventing files from accidentally opening inside Neo-tree or terminal splits.
		local function ensure_code_window()
			local ok, dock = pcall(require, "krs.core.dock")
			if not ok then
				return
			end
			local cur_win = vim.api.nvim_get_current_win()
			if not dock.is_code_win(cur_win) then
				local target = dock.find_code_win()
				if target and vim.api.nvim_win_is_valid(target) then
					vim.api.nvim_set_current_win(target)
				else
					pcall(vim.cmd, "wincmd l")
					local new_win = vim.api.nvim_get_current_win()
					if not dock.is_code_win(new_win) then
						pcall(vim.cmd, "vsplit")
						pcall(vim.cmd, "enew")
					end
				end
			end
		end

		--- Finds files, respecting .gitignore.
		--- Inside a repository `git files` is both the fastest and the most correct
		--- source; outside one, rg/fd apply the ignore rules themselves.
		local function find_files_gitignore()
			ensure_code_window()
			if in_git_repo() then
				if not pcall(builtin.git_files, { recurse_submodules = true }) then
					if not pcall(builtin.git_files, { show_untracked = true }) then
						builtin.find_files({ no_ignore = false, hidden = true })
					end
				end
			elseif vim.fn.executable("rg") == 1 then
				builtin.find_files({
					find_command = { "rg", "--files", "--color=never", "--hidden", "--glob", "!.git/*" },
				})
			elseif vim.fn.executable("fd") == 1 then
				builtin.find_files({ find_command = { "fd", "--type", "f", "--hidden", "--exclude", ".git" } })
			else
				builtin.find_files({ no_ignore = false, hidden = true })
			end
		end

		--- Finds every file, ignore rules included -- for build output and vendored
		--- code you deliberately want to open.
		local function find_files_no_ignore()
			ensure_code_window()
			if vim.fn.executable("rg") == 1 then
				builtin.find_files({
					find_command = { "rg", "--files", "--color=never", "--no-ignore", "--hidden", "--glob", "!.git/*" },
				})
			elseif vim.fn.executable("fd") == 1 then
				builtin.find_files({
					find_command = { "fd", "--type", "f", "--no-ignore", "--hidden", "--exclude", ".git" },
				})
			else
				builtin.find_files({ no_ignore = true, hidden = true })
			end
		end

		-- Exported for lua/keymaps/search.lua, which binds these before
		-- telescope has loaded.
		_G.FindFilesGitignore = find_files_gitignore
		_G.FindFilesNoIgnore = find_files_no_ignore

		vim.api.nvim_create_user_command("TelescopeFindFilesGitignore", find_files_gitignore, {
			desc = "Find files respecting .gitignore",
		})

		vim.api.nvim_create_user_command("TelescopeFindFilesNoIgnore", find_files_no_ignore, {
			desc = "Find files ignoring .gitignore",
		})

		for _, key in ipairs(settings.find_keys) do
			vim.keymap.set({ "n", "i" }, key, find_files_gitignore, {
				noremap = true,
				silent = true,
				desc = "Telescope find files (excludes .gitignore)",
			})
		end
		for _, key in ipairs(settings.find_all_keys) do
			vim.keymap.set({ "n", "i" }, key, find_files_no_ignore, {
				noremap = true,
				silent = true,
				desc = "Telescope find files (ignoring .gitignore)",
			})
		end

		if settings.live_grep_key then
			vim.keymap.set({ "n", "i" }, settings.live_grep_key, builtin.live_grep, { desc = "Telescope live grep" })
		end
		if settings.help_tags_key then
			vim.keymap.set("n", settings.help_tags_key, builtin.help_tags, { desc = "Telescope help tags" })
		end

		-- ------------------------------------------------------------------
		-- Folder picker
		-- ------------------------------------------------------------------

		--- Absolute directory path with no trailing separator, except at a root
		--- (`C:/`, `/`), where the separator is part of the path.
		--- @param p string|nil
		--- @return string
		local function normalize_dir(p)
			if not p or p == "" then
				return ""
			end
			local full = vim.fn.fnamemodify(p, ":p")
			if full:match("^[A-Za-z]:[/\\]$") or full == "/" then
				return full
			end
			return (full:gsub("[/\\]$", ""))
		end

		--- Subdirectories of `dir`, at most `folder_scan_depth` levels deep.
		--- `fd` when available; plenary's scanner otherwise.
		--- @param dir string Root directory.
		--- @return string[] directories Including `dir` itself, first.
		local function scan_directories(dir)
			local dirs = { dir }

			if vim.fn.executable("fd") == 1 then
				local cmd = { "fd", ".", dir, "--type", "d", "--hidden" }
				for _, exclude in ipairs(settings.folder_excludes) do
					vim.list_extend(cmd, { "--exclude", exclude })
				end
				vim.list_extend(cmd, { "--max-depth", tostring(settings.folder_scan_depth) })

				local output = vim.fn.systemlist(cmd)
				if vim.v.shell_error == 0 then
					for _, line in ipairs(output) do
						if line ~= "" then
							table.insert(dirs, (line:gsub("\\", "/"):gsub("/$", "")))
						end
					end
				end
				return dirs
			end

			local ok, scandir = pcall(require, "plenary.scandir")
			if ok then
				for _, found in
					ipairs(scandir.scan_dir(dir, {
						only_dirs = true,
						depth = settings.folder_scan_depth,
						hidden = false,
					}))
				do
					table.insert(dirs, (found:gsub("\\", "/"):gsub("/$", "")))
				end
			end
			return dirs
		end

		--- Records a directory as the most recent project, in both project.nvim's
		--- lists and the WSL one.
		--- @param dir string Directory path.
		local function remember_project(dir)
			if not dir or dir == "" then
				return
			end

			local favorites = require("krs.projects.favorites")
			local key = favorites.key(dir)

			local ok, history = pcall(require, "project_nvim.utils.history")
			if ok then
				for _, field in ipairs({ "session_projects", "recent_projects" }) do
					if history[field] ~= nil then
						local kept = {}
						for _, project in ipairs(history[field]) do
							if favorites.key(project):lower() ~= key:lower() then
								table.insert(kept, project)
							end
						end
						table.insert(kept, key)
						history[field] = kept
					end
				end
				history.write_projects_to_history()
			end

			pcall(function()
				require("plugins.krs.tools.wsl").add_recent_project(key)
			end)
		end

		--- Adopts a directory as the active project.
		--- @param dir string Directory path.
		local function open_directory(dir)
			dir = normalize_dir(dir)
			if vim.fn.isdirectory(dir) == 0 then
				vim.notify("Directory does not exist: " .. dir, vim.log.levels.ERROR)
				return
			end

			pcall(vim.cmd, "Neotree close")
			vim.cmd("silent! only")

			vim.cmd("enew")
			local new_buf = vim.api.nvim_get_current_buf()
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if buf ~= new_buf and vim.api.nvim_buf_is_valid(buf) then
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
			end

			pcall(vim.api.nvim_set_current_dir, dir)
			local pinned_tabs = require("plugins.krs.ui.pinned_tabs")
			local has_pins = #pinned_tabs.load_pins() > 0
			if not has_pins then
				vim.cmd("Alpha")
			end
			remember_project(dir)
			if _G.AddOpenedFolder then
				_G.AddOpenedFolder(dir)
			end

			pcall(vim.cmd, "Neotree focus dir=" .. vim.fn.fnameescape(dir))
			if has_pins then
				vim.schedule(function()
					vim.schedule(function()
						pinned_tabs.restore_pins({ focus = true })
					end)
				end)
			end
			vim.notify("📁 Opened folder: " .. dir, vim.log.levels.INFO)
		end

		local open_folder_picker

		--- Browses directories; <CR> adopts one (or calls on_select), <C-l> descends, <C-h> goes up.
		--- @param opts table|nil `{ cwd = string }` Directory to browse.
		--- @param on_select function|nil `function(dir)` Optional callback when selected.
		open_folder_picker = function(opts, on_select)
			opts = opts or {}
			return require("plugins.krs.tools.file_explorer").open_folder_picker(opts, on_select)
		end

		_G.OpenFolderPicker = open_folder_picker

		pcall(telescope.load_extension, "file_browser")

		vim.api.nvim_create_user_command("TelescopeOpenFolder", function()
			open_folder_picker()
		end, { desc = "Browse folders and open one as the active project" })
		if settings.open_folder_key then
			vim.keymap.set({ "n", "i" }, settings.open_folder_key, function()
				require("plugins.krs.dev.sneak_peek").toggle_or_pick()
			end, { desc = "Sneak-Peek Project Modal (Ctrl+Shift+O)" })
		end

		vim.api.nvim_create_user_command("TelescopeFileBrowserDesktop", function()
			require("plugins.krs.tools.file_explorer").open_desktop_explorer()
		end, { desc = "Open the floating desktop file explorer" })
		if settings.desktop_explorer_key then
			vim.keymap.set({ "n", "i" }, settings.desktop_explorer_key, function()
				require("plugins.krs.tools.file_explorer").open_desktop_explorer()
			end, { desc = "Open Desktop File Explorer" })
		end

		-- ------------------------------------------------------------------
		-- Split finders
		-- ------------------------------------------------------------------

		--- Finds a file and opens it in a split in `direction`.
		--- @param direction "h"|"j"|"k"|"l"
		local function open_find_files_split(direction)
			ensure_code_window()
			local split = settings.splits[direction]

			builtin.find_files({
				prompt_title = " 🔍 Find & Open File " .. (split and split.label or direction) .. " ",
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)

						local filepath = selection and (selection.value or selection[1])
						if filepath and split then
							vim.cmd(split.command .. " " .. vim.fn.fnameescape(filepath))
						end
					end)
					return true
				end,
			})
		end

		-- Keys for these live in lua/keymaps/search.lua (see the header).
		local split_commands = {
			TelescopeFindFilesSplitLeft = "h",
			TelescopeFindFilesSplitBelow = "j",
			TelescopeFindFilesSplitAbove = "k",
			TelescopeFindFilesSplitRight = "l",
		}
		for name, direction in pairs(split_commands) do
			vim.api.nvim_create_user_command(name, function()
				open_find_files_split(direction)
			end, { desc = "Find a file and open it in a split (" .. direction .. ")" })
		end
	end,
}
