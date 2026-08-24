-- ============================================================================
-- PLUGIN: project.nvim -- recent projects, with a custom picker (<C-r>).
-- ============================================================================
-- WHY THE PICKER IS CUSTOM
--   The stock `Telescope projects` list cannot show WSL projects, favorites, or
--   per-language icons, and it stats every path on open -- which BOOTS WSL over
--   SMB and freezes the UI for seconds. This picker:
--     * merges project.nvim history with the WSL recent list,
--     * pins favorites (shared with the file explorer) to the top,
--     * never stats a WSL path until you actually pick it,
--     * opens a project cleanly: close splits, drop old buffers, cd, show tree.
--
-- PICKER KEYS
--   <CR> open   f favorite   r rename   d remove from the list
--
-- COLLABORATORS
--   krs.projects.favorites   Starred paths, shared with the file explorer.
--   plugins.krs.wsl          WSL detection and its own recent list.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local favorites = lazy_req("krs.projects.favorites")
local path_util = lazy_req("krs.core.path")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Files and directories that mark a project root for project.nvim.
	root_patterns = {
		".git",
		"_darcs",
		".hg",
		".bzr",
		".svn",
		"Makefile",
		"package.json",
		"go.mod",
		"Cargo.toml",
		"pyproject.toml",
		"tsconfig.json",
		"pom.xml",
		"build.gradle",
	},

	--- Picker geometry.
	picker = { width = 0.85, height = 0.70 },

	--- Icon for a project, chosen by the first marker file that exists.
	--- `devicon` is looked up in nvim-web-devicons; `fallback` is used without it.
	--- ADD A LANGUAGE HERE.
	icons = {
		{ files = { "Cargo.toml" }, devicon = "Cargo.toml", fallback = "🦀", highlight = "DevIconRs" },
		{ files = { "package.json" }, devicon = "package.json", fallback = "", highlight = "DevIconJson" },
		{
			files = { "pyproject.toml", "requirements.txt", "setup.py" },
			devicon = "a.py",
			fallback = "",
			highlight = "DevIconPy",
		},
		{ files = { "go.mod" }, devicon = "go.mod", fallback = "", highlight = "DevIconGo" },
		{
			files = { "pom.xml", "build.gradle", "build.gradle.kts" },
			devicon = "a.java",
			fallback = "",
			highlight = "DevIconJava",
		},
		{ files = { "CMakeLists.txt", "Makefile" }, devicon = "CMakeLists.txt", fallback = "", highlight = "DevIconC" },
		{ files = { "init.lua" }, dirs = { "lua" }, devicon = "init.lua", fallback = "", highlight = "DevIconLua" },
		{ files = { "composer.json" }, devicon = "composer.json", fallback = "🐘", highlight = "DevIconPhp" },
	},

	--- Icon for a project that matches nothing above, and for WSL projects.
	default_icon = { icon = "📄", highlight = "Directory" },
	wsl_icon = { icon = "🐧", highlight = "Directory" },

	--- Bogus entries that a broken history file can contain.
	invalid_paths = { "c:", "c:/" },

	--- Open the picker.
	keys = { "<C-S-r>", "<C-S-R>", "<C-r>", "<C-R>", "<leader>fp" },
}

return {
	"ahmedkhalf/project.nvim",
	cmd = { "Telescope projects", "ProjectRoot", "RecentProjects" },
	keys = {
		{ "<C-S-r>", "<cmd>Telescope projects<CR>", mode = { "n", "i", "v", "t" }, desc = "Open Recent Projects UI" },
		{ "<C-S-R>", "<cmd>Telescope projects<CR>", mode = { "n", "i", "v", "t" }, desc = "Open Recent Projects UI" },
		{ "<C-r>", "<cmd>Telescope projects<CR>", mode = { "n", "i", "v", "t" }, desc = "Open Recent Projects UI" },
		{ "<leader>fp", "<cmd>Telescope projects<CR>", mode = { "n", "i", "v", "t" }, desc = "Open Recent Projects UI" },
	},
	dependencies = {
		"nvim-telescope/telescope.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	config = function()
		require("project_nvim").setup({
			-- Manual mode: the working directory only changes when a project is
			-- opened deliberately, never by opening a file from somewhere else.
			manual_mode = true,
			manual_gc = false,
			detection_methods = { "pattern", "lsp" },
			patterns = settings.root_patterns,
			silent_chdir = true,
			scope_chdir = "global",
		})
		require("telescope").load_extension("projects")

		local history = require("project_nvim.utils.history")

		-- ------------------------------------------------------------------
		-- Helpers
		-- ------------------------------------------------------------------

		--- Comparison/storage form of a project path (see krs.projects.favorites).
		--- @param p string|nil
		--- @return string
		local function normalize(p)
			return favorites.key(p)
		end

		--- Rewrites project.nvim's history file, dropping duplicates and junk.
		--- project.nvim only persists on exit, so anything changed here has to be
		--- written by hand or it is lost.
		---
		--- @param list string[] Project paths, oldest first.
		local function save_history(list)
			local ok, path_module = pcall(require, "project_nvim.utils.path")
			if not ok then
				return
			end

			local file = io.open(path_module.historyfile, "w")
			if not file then
				return
			end

			local seen = {}
			for _, project in ipairs(list) do
				local clean = type(project) == "string" and normalize(project) or ""
				local is_junk = clean == "" or vim.tbl_contains(settings.invalid_paths, clean)
				if not is_junk and not seen[clean:lower()] then
					seen[clean:lower()] = true
					file:write(clean .. "\n")
				end
			end
			file:close()
		end

		--- Icon and highlight for a project directory.
		--- @param dir string Project directory.
		--- @return string icon
		--- @return string highlight
		local function project_icon(dir)
			local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

			for _, rule in ipairs(settings.icons) do
				for _, name in ipairs(rule.files or {}) do
					if vim.fn.filereadable(dir .. "/" .. name) == 1 then
						return (devicons_ok and devicons.get_icon(rule.devicon)) or rule.fallback, rule.highlight
					end
				end
				for _, name in ipairs(rule.dirs or {}) do
					if vim.fn.isdirectory(dir .. "/" .. name) == 1 then
						return (devicons_ok and devicons.get_icon(rule.devicon)) or rule.fallback, rule.highlight
					end
				end
			end

			return settings.default_icon.icon, settings.default_icon.highlight
		end

		--- WSL helper module, when it is available.
		--- @return table|nil wsl
		local function wsl_module()
			local ok, wsl = pcall(require, "plugins.krs.wsl")
			return ok and wsl or nil
		end

		--- True for a path inside a WSL distribution.
		--- @param p string
		--- @return boolean
		local function is_wsl_path(p)
			local wsl = wsl_module()
			if wsl and wsl.is_wsl_path then
				return wsl.is_wsl_path(p)
			end
			return p:gsub("\\", "/"):match("^//wsl") ~= nil
		end

		--- Ensures project.nvim history is loaded synchronously before reading.
		--- `history.read_projects_from_history()` runs asynchronously, causing
		--- `history.recent_projects` to be nil on initial picker open.
		local function ensure_history_loaded()
			if history.recent_projects == nil then
				local ok, path_module = pcall(require, "project_nvim.utils.path")
				if ok and path_module.historyfile then
					local file = io.open(path_module.historyfile, "r")
					if file then
						local content = file:read("*a")
						file:close()
						if content and content ~= "" then
							local loaded = {}
							for line in content:gmatch("[^\r\n]+") do
								local trimmed = vim.trim(line)
								if trimmed ~= "" then
									table.insert(loaded, trimmed)
								end
							end
							history.recent_projects = loaded
						end
					end
				end
			end
		end

		-- ------------------------------------------------------------------
		-- Project list
		-- ------------------------------------------------------------------

		--- Every known project, WSL list first, then project.nvim history, with
		--- duplicates removed.
		--- @return string[] paths
		local function collect_projects()
			ensure_history_loaded()
			local wsl = wsl_module()
			local projects, seen = {}, {}

			local function add(p)
				local key = normalize(p)
				if key ~= "" and not seen[key:lower()] then
					seen[key:lower()] = true
					table.insert(projects, p)
				end
			end

			if wsl and wsl.get_recent_projects then
				-- `false`: do not stat, which would boot WSL just to draw a list.
				for _, project in ipairs(wsl.get_recent_projects(false)) do
					add(project)
				end
			end
			for _, project in ipairs(history.get_recent_projects() or {}) do
				add(project)
			end

			return projects
		end

		--- Picker rows: favorites first, then the rest, each with its icon.
		--- Local directories that no longer exist are dropped; WSL paths are kept
		--- unchecked, because verifying them is what makes the list slow.
		---
		--- @return table[] entries
		local function build_entries()
			local starred = favorites.load()
			local favorite_entries, other_entries = {}, {}

			for _, project in ipairs(collect_projects()) do
				local key = normalize(project)
				local wsl = is_wsl_path(project)
				local icon, highlight = settings.wsl_icon.icon, settings.wsl_icon.highlight
				local keep = true

				if not wsl then
					keep = vim.fn.isdirectory(project) == 1
					if keep then
						icon, highlight = project_icon(project)
					end
				end

				if keep then
					local entry = {
						path = project,
						norm = key,
						is_favorite = starred[key] == true,
						is_wsl = wsl,
						icon = icon,
						hl = highlight,
					}
					table.insert(entry.is_favorite and favorite_entries or other_entries, entry)
				end
			end

			return vim.list_extend(favorite_entries, other_entries)
		end

		-- ------------------------------------------------------------------
		-- Opening a project
		-- ------------------------------------------------------------------

		--- Switches to a project: clears the previous one, changes directory,
		--- records it as recent, and reopens the file tree there.
		--- @param dir string Project directory.
		local function open_project(dir)
			if not dir or dir == "" then
				return
			end

			-- Deliberate action, so now it is fine to touch a WSL path.
			if vim.fn.isdirectory(dir) == 0 then
				local message = is_wsl_path(dir)
						and ("🐧 WSL project directory is unreachable or does not exist:\n" .. tostring(dir))
					or ("Directory does not exist: " .. tostring(dir))
				vim.notify(message, vim.log.levels.ERROR, { title = "Recent Projects" })
				return
			end

			-- Stop all LSP clients from previous project to free memory and avoid cross-project pollution
			for _, client in ipairs(vim.lsp.get_clients()) do
				client:stop()
			end

			pcall(vim.cmd, "Neotree close")
			pcall(vim.cmd, "only")

			vim.cmd("enew")
			local new_buf = vim.api.nvim_get_current_buf()
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if buf ~= new_buf and vim.api.nvim_buf_is_valid(buf) then
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
			end

			pcall(vim.api.nvim_set_current_dir, dir)

			local wsl = wsl_module()
			if wsl and wsl.add_recent_project and is_wsl_path(dir) then
				wsl.add_recent_project(dir)
			end

			-- Move the project to the end of the history, which is "most recent".
			if history.recent_projects then
				local updated = {}
				for _, project in ipairs(history.recent_projects) do
					if not path_util.equals(normalize(project), normalize(dir)) then
						table.insert(updated, project)
					end
				end
				table.insert(updated, dir)
				history.recent_projects = updated
				save_history(updated)
			end

			if _G.AddOpenedFolder then
				_G.AddOpenedFolder(dir)
			end

			pcall(vim.cmd, "Neotree show dir=" .. vim.fn.fnameescape(dir))
			vim.notify("📁 Switched to project: " .. dir, vim.log.levels.INFO)
		end

		-- ------------------------------------------------------------------
		-- Picker
		-- ------------------------------------------------------------------

		local open_projects_picker

		--- Removes a project from every list it appears in.
		--- @param entry table Picker entry.
		local function forget_project(entry)
			for _, field in ipairs({ "recent_projects", "session_projects" }) do
				if history[field] then
					local kept = {}
					for _, project in ipairs(history[field]) do
						if normalize(project) ~= entry.norm then
							table.insert(kept, project)
						end
					end
					history[field] = kept
				end
			end
			save_history(history.get_recent_projects())

			local wsl = wsl_module()
			if wsl then
				wsl.remove_recent_project(entry.path)
			end
			favorites.remove(entry.path)
		end

		--- Renames a project directory and follows it through every list.
		--- WSL directories are not renamed on disk -- only the entries are updated.
		--- @param entry table Picker entry.
		--- @param new_name string New folder name.
		--- @return boolean ok
		local function rename_project(entry, new_name)
			local parent = vim.fn.fnamemodify(entry.path, ":h")
			local new_path = parent .. "/" .. new_name
			local wsl = wsl_module()
			local wsl_path = is_wsl_path(entry.path)

			if not wsl_path and vim.fn.isdirectory(entry.path) == 1 then
				local renamed, err = os.rename(entry.path, new_path)
				if not renamed then
					vim.notify("Failed to rename directory: " .. tostring(err), vim.log.levels.ERROR, {
						title = "Recent Projects",
					})
					return false
				end
			end

			if history.recent_projects then
				local updated = {}
				for _, project in ipairs(history.recent_projects) do
					table.insert(updated, normalize(project) == entry.norm and new_path or project)
				end
				history.recent_projects = updated
				save_history(updated)
			end

			if wsl_path and wsl then
				wsl.remove_recent_project(entry.path)
				wsl.add_recent_project(new_path)
			end

			favorites.move(entry.path, new_path)
			vim.notify("✏️ Project renamed to: " .. new_name, vim.log.levels.INFO, { title = "Recent Projects" })
			return true
		end

		--- Opens the recent projects picker.
		--- @param opts table|nil Reserved; passed through on refresh.
		open_projects_picker = function(opts)
			opts = opts or {}

			local pickers = require("telescope.pickers")
			local finders = require("telescope.finders")
			local conf = require("telescope.config").values
			local actions = require("telescope.actions")
			local action_state = require("telescope.actions.state")
			local themes = require("telescope.themes")

			pickers
				.new(themes.get_dropdown({
					prompt_title = " 📁 Recent Projects | [f] Favorite | [r] Rename | [d] Delete ",
					width = settings.picker.width,
					layout_config = settings.picker,
					finder = finders.new_table({
						results = build_entries(),
						entry_maker = function(entry)
							return {
								value = entry,
								display = entry.icon .. "  " .. entry.path .. (entry.is_favorite and " ⭐ [Favorite]" or ""),
								ordinal = (entry.is_favorite and "0_" or "1_") .. entry.path,
							}
						end,
					}),
					sorter = conf.generic_sorter({}),
					attach_mappings = function(prompt_bufnr, map)
						--- Selected entry, or nil.
						local function selected()
							local selection = action_state.get_selected_entry()
							return selection and selection.value or nil
						end

						--- Reopens the picker so it reflects a change.
						local function reopen()
							vim.schedule(function()
								open_projects_picker(opts)
							end)
						end

						actions.select_default:replace(function()
							local entry = selected()
							actions.close(prompt_bufnr)
							if entry then
								open_project(entry.path)
							end
						end)

						map("n", "f", function()
							local entry = selected()
							if not entry then
								return
							end

							if favorites.toggle(entry.path) then
								vim.notify("⭐ Project saved as favorite (top first)", vim.log.levels.INFO, {
									title = "Recent Projects",
								})
							else
								vim.notify("Removed project from favorites", vim.log.levels.INFO, {
									title = "Recent Projects",
								})
							end

							actions.close(prompt_bufnr)
							reopen()
						end)

						map("n", "r", function()
							local entry = selected()
							if not entry then
								return
							end
							local old_name = vim.fn.fnamemodify(entry.path, ":t")
							actions.close(prompt_bufnr)

							vim.schedule(function()
								require("plugins.krs.input_modal").open({
									label = "Rename Project (" .. old_name .. ")",
									default_value = old_name,
									relative = "editor",
									callback = function(ok, new_name)
										if ok and new_name and new_name ~= "" and new_name ~= old_name then
											rename_project(entry, new_name)
										end
										open_projects_picker(opts)
									end,
								})
							end)
						end)

						map("n", "d", function()
							local entry = selected()
							if not entry then
								return
							end
							if vim.fn.confirm("Delete '" .. entry.path .. "' from project list?", "&Yes\n&No", 2) ~= 1 then
								return
							end

							forget_project(entry)
							actions.close(prompt_bufnr)
							reopen()
						end)

						return true
					end,
				}), {})
				:find()
		end

		-- `Telescope projects` and the dashboard both route here.
		pcall(function()
			local tel = require("telescope")
			tel.load_extension("projects")
			if tel.extensions and tel.extensions.projects then
				tel.extensions.projects.projects = open_projects_picker
			end
		end)

		_G.OpenRecentProjects = open_projects_picker

		vim.api.nvim_create_user_command("RecentProjects", function()
			open_projects_picker()
		end, { desc = "Open Recent Projects UI" })

		local function from_any_mode(fn)
			return function()
				local mode = vim.fn.mode()
				if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
					pcall(vim.cmd, "stopinsert")
				end
				fn()
			end
		end

		for _, k in ipairs(settings.keys) do
			vim.keymap.set({ "n", "i", "v", "t" }, k, from_any_mode(open_projects_picker), {
				noremap = true,
				silent = true,
				desc = "Open Recent Projects UI",
			})
		end
	end,
}
