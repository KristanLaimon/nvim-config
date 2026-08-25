-- ============================================================================
-- KRS PLUGIN: Launch Profiles -- per-project run/debug configurations.
-- ============================================================================
-- WHAT IT DOES
--   Stores named launch configurations in `.krsnvim/launch.json` and runs them
--   either as a terminal task or through nvim-dap, after any pre-launch tasks.
--
-- KEYBINDS (see M.settings.keys)
--   <C-S-s>  Smart launch: stop a running debug session, else run the default
--            profile, else open the management UI.
--   <C-S-q>  Management UI (run / edit / rename / delete / favorite).
--
-- PROJECT FILE -- `.krsnvim/launch.json`
--   {
--     "profiles": [{
--       "id": "profile-1712345678",     // unique, generated on creation
--       "name": "Run API",
--       "runtime": "bun",               // see krs.launch.runtimes for the list
--       "entry_point": "src/index.ts",  // relative to the project root
--       "args": ["--watch"],
--       "env": { "NODE_ENV": "development" },
--       "pre_launch_tasks": ["npm run build"],
--       "mode": "run",                  // "run" = terminal, "debug" = DAP
--       "is_default": true,             // only one profile may be the default
--       "auto_build": false             // dotnet only: build before launching
--     }]
--   }
--
-- STRUCTURE
--   krs.launch.runtimes  Runtime table: how to run and how to debug. ADD LANGUAGES THERE.
--   this file            Persistence, the profile form, the picker, keymaps.
--
-- COLLABORATORS
--   plugins.krs.tasks        Runs pre-launch tasks and terminal launches.
--   plugins.krs.input_modal  Single-field prompts used by the form.
--   telescope / dap          Picker UI and debug sessions.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path = lazy_req("krs.core.path")
local ui = lazy_req("krs.core.ui")
local runtimes = lazy_req("krs.launch.runtimes")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Per-project file name, resolved inside `.krsnvim/` (see krs.core.project).
	config_file = "launch.json",

	--- Notification titles, kept distinct so debugger errors are recognizable.
	notify_title = "Launch Profiles",
	debug_notify_title = "Launch Profiles Debugger",

	--- Profile form geometry, in cells.
	form_width = 78,
	form_height = 18,

	--- Fields in the profile form, in display order. `edit` names the behaviour:
	---   "text"   -> prompt through input_modal
	---   "cycle"  -> step through krs.launch.runtimes.order
	---   "toggle" -> flip a boolean
	---   "list"   -> prompt, then split on `separator`
	--- ADD A PROFILE FIELD HERE and in `M.new_profile` -- the form renders itself.
	form_fields = {
		{ key = "name", label = "Profile Name", edit = "text" },
		{ key = "runtime", label = "Runtime", edit = "cycle" },
		{ key = "entry_point", label = "Entry Point File", edit = "text", prompt = "Entry Point File (relative path)" },
		{
			key = "args",
			label = "Command Args",
			edit = "list",
			separator = "%S+",
			join = " ",
			prompt = "Command Arguments (space separated)",
		},
		{
			key = "pre_launch_tasks",
			label = "Pre-launch Tasks",
			edit = "list",
			separator = "[^,]+",
			join = ", ",
			prompt = "Pre-launch Tasks (comma separated)",
		},
		{ key = "mode", label = "Execution Mode", edit = "swap", values = { "run", "debug" } },
		{ key = "is_default", label = "Primary Default", edit = "toggle" },
		{ key = "auto_build", label = "Auto Build", edit = "toggle" },
	},

	keys = {
		--- Smart launch, bound in normal, insert, visual and terminal mode.
		smart_launch = is_mobile_lp and { "<C-S-s>", "<C-S-S>", "<C-S>", "<C-s>" } or { "<C-S-s>", "<C-S-S>" },
		--- Open the management picker.
		manage = { "<C-S-q>", "<C-S-Q>", "<C-Q>" },
	},
}

--- Fresh profile used by the creation form.
--- @param root string Project root, used for the default name.
--- @return table profile
function M.new_profile(root)
	return {
		id = "profile-" .. os.time(),
		name = "Run " .. vim.fn.fnamemodify(root, ":t"),
		runtime = "bun",
		entry_point = "src/index.ts",
		args = {},
		env = {},
		pre_launch_tasks = {},
		mode = "run",
		is_default = false,
		auto_build = false,
	}
end

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
--- @param title string|nil Defaults to `M.settings.notify_title`.
local function notify(msg, level, title)
	vim.notify(msg, level or vim.log.levels.INFO, { title = title or M.settings.notify_title })
end

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

--- Project root for the current buffer, shared with the task runner so both
--- agree on what "this project" means.
--- @return string root
function M.get_project_root()
	local ok, tasks = pcall(require, "plugins.krs.tasks")
	if ok and tasks.get_project_root then
		return tasks.get_project_root()
	end
	return project.root()
end

--- Resolves `launch.json` for a project (`.krsnvim`, then `.krslocal`, then
--- `.nvimkrs`). Returns the `.krsnvim` path when the file does not exist yet.
---
--- @param root string|nil Project root.
--- @return string filepath
function M.get_launch_filepath(root)
	return (project.config_path(M.settings.config_file, root or M.get_project_root()))
end

local function load_vscode_launch_configs(root)
	local vscode_path = path.join(root or M.get_project_root(), ".vscode", "launch.json")
	if not path.is_file(vscode_path) then
		return {}
	end
	local raw_data = store.load(vscode_path, {})
	local configs = raw_data.configurations or {}
	local profiles = {}

	for idx, cfg in ipairs(configs) do
		if type(cfg) == "table" and cfg.name then
			local entry = cfg.program or cfg.script or cfg.main or ""
			if type(entry) == "string" then
				entry = entry:gsub("^%${workspaceFolder}/", "")
			end

			table.insert(profiles, {
				id = "vscode-" .. (cfg.name:gsub("%s+", "_"):lower()) .. "-" .. idx,
				name = "⚡ [VSCode] " .. cfg.name,
				runtime = cfg.type or "node",
				entry_point = entry,
				args = type(cfg.args) == "table" and cfg.args or {},
				env = type(cfg.env) == "table" and cfg.env or {},
				pre_launch_tasks = cfg.preLaunchTask and { cfg.preLaunchTask } or {},
				mode = cfg.request == "attach" and "debug" or "run",
				is_default = false,
				is_vscode = true,
			})
		end
	end
	return profiles
end

--- Loads every profile defined for the project.
--- @param root string|nil Project root.
--- @return table data `{ profiles = {...} }`, always with a profiles array.
function M.load_profiles(root)
	root = root or M.get_project_root()
	local data = store.load(M.get_launch_filepath(root), { profiles = {} })
	data.profiles = data.profiles or {}

	local vscode_profiles = load_vscode_launch_configs(root)
	for _, vp in ipairs(vscode_profiles) do
		local exists = false
		for _, existing in ipairs(data.profiles) do
			if existing.name == vp.name then
				exists = true
				break
			end
		end
		if not exists then
			table.insert(data.profiles, vp)
		end
	end

	return data
end

--- Writes the profile file back, creating its directory.
--- @param root string|nil Project root.
--- @param data table `{ profiles = {...} }`
function M.save_profiles(root, data)
	root = root or M.get_project_root()
	local filepath = M.get_launch_filepath(root)

	local ok, err = store.save(filepath, data)
	if not ok then
		notify("Error writing " .. filepath .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Makes one profile the single default, clearing the flag on the others.
--- @param profile_id string Profile id.
--- @param root string|nil Project root.
function M.toggle_default(profile_id, root)
	root = root or M.get_project_root()
	local data = M.load_profiles(root)

	local updated_name = ""
	for _, p in ipairs(data.profiles) do
		if p.id == profile_id then
			p.is_default = not p.is_default
			updated_name = p.name
		else
			p.is_default = false
		end
	end

	M.save_profiles(root, data)
	notify("⭐ Primary default profile set: " .. updated_name)
end

--- Renames a profile in place.
--- @param profile_id string Profile id.
--- @param new_name string New display name.
--- @param root string|nil Project root.
function M.rename_profile(profile_id, new_name, root)
	root = root or M.get_project_root()
	local data = M.load_profiles(root)

	for _, p in ipairs(data.profiles) do
		if p.id == profile_id then
			local old_name = p.name
			p.name = new_name
			M.save_profiles(root, data)
			notify("✏️ Profile renamed: " .. old_name .. " ➜ " .. new_name)
			return
		end
	end
end

--- Finds a profile by id.
--- @param data table Loaded profile data.
--- @param profile_id string Profile id.
--- @return table|nil profile
local function find_profile(data, profile_id)
	for _, p in ipairs(data.profiles or {}) do
		if p.id == profile_id then
			return p
		end
	end
	return nil
end

-- ============================================================================
-- RUNTIME BRIDGE -- thin wrappers over krs.launch.runtimes
-- ============================================================================

--- How to run a `.ts`/`.tsx` file under node. Also used by plugins/editor/dap.lua.
--- @param root string Project root.
--- @param entry string Entry point.
--- @return table `{ exe = string, args = string[] }`
function M.ts_runtime(root, entry)
	return runtimes.ts_runtime(root, entry)
end

--- Maps a profile to a real DAP configuration.
--- @param profile table Launch profile.
--- @param root string Project root.
--- @return table|nil config
function M.build_dap_config(profile, root)
	return runtimes.build_dap_config(profile, root)
end

-- ============================================================================
-- EXECUTION
-- ============================================================================

--- Runs pre-launch tasks one at a time, stopping at the first failure.
---
--- @param tasks_list table[]|string[]|nil Commands or task tables.
--- @param callback function(success: boolean) Called once, when the chain ends.
function M.run_pre_launch_tasks(tasks_list, callback)
	if not tasks_list or #tasks_list == 0 then
		callback(true)
		return
	end

	local tasks = require("plugins.krs.tasks")
	local idx = 1

	local function run_next()
		if idx > #tasks_list then
			callback(true)
			return
		end

		local item = tasks_list[idx]
		local cmd = type(item) == "table" and (item.cmd or item.name) or tostring(item)

		notify(
			"⚙️ Executing pre-launch task [" .. idx .. "/" .. #tasks_list .. "]: " .. cmd,
			vim.log.levels.INFO,
			"Pre-Launch Tasks"
		)

		tasks.run_custom_command(cmd, nil, function(exit_code)
			if exit_code ~= 0 then
				notify(
					"❌ Pre-launch task failed with exit code " .. exit_code .. ": " .. cmd,
					vim.log.levels.ERROR,
					"Launch Profile Aborted"
				)
				callback(false)
				return
			end
			idx = idx + 1
			run_next()
		end)
	end

	run_next()
end

--- Starts a debug session for a profile.
--- @param profile table Launch profile.
--- @param root string Project root.
local function start_debug_session(profile, root)
	local dap_ok, dap = pcall(require, "dap")
	if not dap_ok then
		notify("DAP is not installed", vim.log.levels.ERROR)
		return
	end

	local config = M.build_dap_config(profile, root)
	if not config then
		return
	end

	local args = profile.args or {}
	if #args > 0 then
		config.args = args
	end

	if not dap.adapters[config.type] then
		local how = config.type == "bun" and ":KrsBunDapInstall, then restart nvim"
			or ":Mason (or restart nvim to let mason-nvim-dap fetch it)"
		notify(
			"❌ Debug adapter '" .. config.type .. "' is not installed.\n  Install it with " .. how .. ".",
			vim.log.levels.ERROR,
			M.settings.debug_notify_title
		)
		return
	end

	notify(
		"🐞 Launching DAP Debugger for " .. (profile.name or profile.id) .. " (" .. (profile.runtime or "node") .. ")",
		vim.log.levels.INFO,
		M.settings.debug_notify_title
	)
	dap.run(config)
end

--- Runs a profile: pre-launch tasks first, then DAP or a terminal task.
--- @param profile table|string Profile table, or a profile id to look up.
function M.run_profile(profile)
	if not profile then
		return
	end

	if type(profile) == "string" then
		local found = find_profile(M.load_profiles(M.get_project_root()), profile)
		if not found then
			notify("❌ Profile not found: " .. profile, vim.log.levels.ERROR)
			return
		end
		profile = found
	end

	local profile_name = profile.name or profile.id or "Unnamed Profile"
	local pre_tasks = vim.deepcopy(profile.pre_launch_tasks or {})

	-- auto_build reuses the pre-launch task runner instead of a second pipeline.
	if profile.auto_build and (profile.runtime or "node") == "dotnet" then
		local target = profile.entry_point or ""
		if target:match("%.dll$") then
			target = vim.fn.fnamemodify(target, ":h")
		end
		table.insert(pre_tasks, 1, "dotnet build " .. target)
	end

	M.run_pre_launch_tasks(pre_tasks, function(success)
		if not success then
			return
		end

		local root = M.get_project_root()
		local cmd, ctx = runtimes.build_command(profile, root)

		-- A runtime that executes itself (the transpiler) never reaches DAP or a
		-- terminal: it did its work while the command was being built.
		if not cmd then
			runtimes.get(profile.runtime).execute(ctx)
			return
		end

		if profile.mode == "debug" then
			start_debug_session(profile, root)
			return
		end

		notify("🚀 Launching profile: " .. profile_name .. " (" .. cmd .. ")")
		require("plugins.krs.tasks").run_custom_command(cmd, profile.env or {})
	end)
end

-- ============================================================================
-- PROFILE FORM -- single floating window, one line per field
-- ============================================================================

--- Renders a field's value as shown in the form.
--- @param profile table Profile being edited.
--- @param field table Entry from `M.settings.form_fields`.
--- @return string
local function render_field_value(profile, field)
	local value = profile[field.key]

	if field.edit == "list" then
		return (value and #value > 0) and table.concat(value, field.join) or "(none)"
	end
	if field.key == "runtime" then
		return tostring(value):upper() .. "  (" .. table.concat(runtimes.order, " | ") .. ")"
	end
	if field.key == "mode" then
		return value == "debug" and "🐞 DAP Debugger" or "🖥️ Terminal Task Slot"
	end
	if field.key == "is_default" then
		return value and "✅ YES (Primary for Ctrl+Shift+S)" or "❌ No"
	end
	if field.key == "auto_build" then
		return value and "✅ YES (dotnet build before launch)" or "❌ No  (dotnet only)"
	end
	return tostring(value)
end

--- Opens the profile form. Saving writes the profile back into `launch.json`.
---
--- @param root string|nil Project root.
--- @param existing_profile table|nil Profile to edit; nil creates a new one.
--- @param on_saved function(profile)|nil Called after a successful save.
function M.open_form_editor(root, existing_profile, on_saved)
	root = root or M.get_project_root()

	local is_edit = existing_profile ~= nil
	local profile = existing_profile and vim.deepcopy(existing_profile) or M.new_profile(root)
	local fields = M.settings.form_fields
	local selected = 1

	local buf, win = ui.float({
		width = M.settings.form_width,
		height = M.settings.form_height,
		filetype = "krslaunchform",
		title = is_edit and " 📝 Edit Launch Profile Form " or " 🚀 New Launch Profile Form ",
	})

	local function render()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local lines = {
			" ────────────── Launch Profile Specifications (Form View) ──────────────",
			"",
		}
		for idx, field in ipairs(fields) do
			table.insert(
				lines,
				string.format(
					"  %s [%d] %-17s %s",
					selected == idx and "👉" or "  ",
					idx,
					field.label .. ":",
					render_field_value(profile, field)
				)
			)
		end
		vim.list_extend(lines, {
			"",
			" ───────────────────────────────────────────────────────────────────────",
			string.format("  Navigation: [1-%d] Select Field  |  [j/k/Tab] Move  |  [Enter/Space] Edit/Cycle", #fields),
			"  [S] Save Profile  |  [Esc/q] Cancel",
		})

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
	end

	--- Applies the edit behaviour of one field, re-rendering when it finishes.
	local function edit_field(idx)
		selected = idx
		render()

		local field = fields[idx]

		if field.edit == "toggle" then
			profile[field.key] = not profile[field.key]
			render()
		elseif field.edit == "swap" then
			profile[field.key] = profile[field.key] == field.values[1] and field.values[2] or field.values[1]
			render()
		elseif field.edit == "cycle" then
			local cur = 1
			for i, name in ipairs(runtimes.order) do
				if name == profile[field.key] then
					cur = i
					break
				end
			end
			profile[field.key] = runtimes.order[(cur % #runtimes.order) + 1]
			render()
		elseif field.edit == "list" then
			local current = profile[field.key] or {}
			require("plugins.krs.input_modal").open({
				label = field.prompt or field.label,
				default_value = #current > 0 and table.concat(current, field.join) or "",
				callback = function(ok, value)
					profile[field.key] = {}
					if ok and value ~= "" then
						for item in value:gmatch(field.separator) do
							local trimmed = vim.trim(item)
							if trimmed ~= "" then
								table.insert(profile[field.key], trimmed)
							end
						end
					end
					render()
				end,
			})
		else
			require("plugins.krs.input_modal").open({
				label = field.prompt or field.label,
				default_value = profile[field.key],
				callback = function(ok, value)
					if ok and value ~= "" then
						profile[field.key] = value
					end
					render()
				end,
			})
		end
	end

	--- Writes the profile back, enforcing the single-default rule.
	local function save_and_close()
		ui.close(win)

		local data = M.load_profiles(root)
		if profile.is_default then
			for _, other in ipairs(data.profiles) do
				if other.id ~= profile.id then
					other.is_default = false
				end
			end
		end

		local replaced = false
		for idx, other in ipairs(data.profiles) do
			if other.id == profile.id then
				data.profiles[idx] = profile
				replaced = true
				break
			end
		end
		if not replaced then
			table.insert(data.profiles, profile)
		end

		M.save_profiles(root, data)
		notify("✅ Saved Launch Profile: " .. profile.name)
		if on_saved then
			on_saved(profile)
		end
	end

	render()

	local kopts = { buffer = buf, noremap = true, silent = true }
	local function move(delta)
		return function()
			selected = (selected - 1 + delta) % #fields + 1
			render()
		end
	end

	vim.keymap.set("n", "j", move(1), kopts)
	vim.keymap.set("n", "<Tab>", move(1), kopts)
	vim.keymap.set("n", "k", move(-1), kopts)

	for idx = 1, #fields do
		vim.keymap.set("n", tostring(idx), function()
			edit_field(idx)
		end, kopts)
	end

	for _, key in ipairs({ "<CR>", "<Space>" }) do
		vim.keymap.set("n", key, function()
			edit_field(selected)
		end, kopts)
	end

	for _, key in ipairs({ "S", "s", "<C-s>" }) do
		vim.keymap.set("n", key, save_and_close, kopts)
	end

	for _, key in ipairs({ "<Esc>", "q" }) do
		vim.keymap.set("n", key, function()
			ui.close(win)
		end, kopts)
	end
end

--- Opens the form with a brand new profile.
--- @param root string|nil Project root.
--- @param on_created function(profile)|nil Called after saving.
function M.open_creation_wizard(root, on_created)
	M.open_form_editor(root, nil, on_created)
end

-- ============================================================================
-- MANAGEMENT PICKER (Telescope)
-- ============================================================================

--- Card shown in the picker preview.
--- @param p table Profile.
--- @return string[] lines
local function profile_card(p)
	return {
		"┌──────────────────────────────────────────────────────────────┐",
		string.format("│ 🚀 PROFILE CARD: %-43s │", p.name:sub(1, 43)),
		"├──────────────────────────────────────────────────────────────┤",
		string.format("│ ⚡ Runtime:        %-42s │", tostring(p.runtime):upper():sub(1, 42)),
		string.format("│ 📄 Entry Point:    %-42s │", tostring(p.entry_point):sub(1, 42)),
		string.format(
			"│ 📌 Arguments:      %-42s │",
			(p.args and #p.args > 0) and table.concat(p.args, " "):sub(1, 42) or "(none)"
		),
		string.format(
			"│ ⚙️ Pre-Tasks:      %-42s │",
			(p.pre_launch_tasks and #p.pre_launch_tasks > 0) and table.concat(p.pre_launch_tasks, ", "):sub(1, 42) or "(none)"
		),
		string.format(
			"│ 🛠️ Exec Mode:      %-42s │",
			(p.mode == "debug" and "🐞 DAP Debugger" or "🖥️ Terminal Task Slot"):sub(1, 42)
		),
		string.format(
			"│ ⭐ Primary Default: %-42s │",
			(p.is_default and "✅ YES (Primary for Ctrl+Shift+S)" or "❌ No"):sub(1, 42)
		),
		string.format(
			"│ 🔨 Auto Build:     %-42s │",
			(p.auto_build and "✅ YES (dotnet build first)" or "❌ No"):sub(1, 42)
		),
		"└──────────────────────────────────────────────────────────────┘",
	}
end

--- One row of the picker list.
--- @param p table Profile.
--- @param idx integer Position in the file.
--- @return table entry
local function profile_entry(p, idx)
	local star = p.is_default and "⭐ [DEFAULT]" or "           "
	local mode_str = p.mode == "debug" and "🐞 DEBUG" or "🚀 RUN  "
	local args_str = (p.args and #p.args > 0) and (" [" .. table.concat(p.args, " ") .. "]") or ""
	local tasks_str = (p.pre_launch_tasks and #p.pre_launch_tasks > 0)
			and (" (pre: " .. table.concat(p.pre_launch_tasks, ", ") .. ")")
		or ""

	return {
		display = string.format(
			"%s  %s  %-20s ──>  %-22s%s%s",
			star,
			mode_str,
			p.name,
			p.runtime .. ":" .. p.entry_point,
			args_str,
			tasks_str
		),
		value = p,
		-- Defaults sort first; the prefix is stripped by the sorter's display.
		ordinal = (p.is_default and "0_" or "1_") .. p.name .. " " .. p.runtime .. " " .. p.entry_point,
		index = idx,
	}
end

--- Opens the profile manager: <CR> runs, `d` deletes, `r` renames, `e` edits,
--- `f` toggles the default, `a` creates. <C-d>/<C-e>/<C-n>/<C-x> mirror them for
--- insert mode.
---
--- @param root string|nil Project root.
function M.open_management_menu(root)
	root = root or M.get_project_root()
	local data = M.load_profiles(root)

	if #data.profiles == 0 then
		notify("No Launch Profiles found. Opening Form Editor...")
		M.open_creation_wizard(root, function(new_profile)
			M.run_profile(new_profile)
		end)
		return
	end

	local telescope_ok, pickers = pcall(require, "telescope.pickers")
	if not telescope_ok then
		vim.notify("Telescope is required for Launch Profiles UI", vim.log.levels.ERROR)
		return
	end

	local finders = require("telescope.finders")
	local previewers = require("telescope.previewers")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local entries = {}
	for idx, p in ipairs(data.profiles) do
		table.insert(entries, profile_entry(p, idx))
	end

	pickers
		.new({}, {
			prompt_title = " 🚀 Launch Profiles | <Enter>: Run | [d] Delete | [r] Rename | [e] Edit | [f] Favorite | [a] New ",
			layout_strategy = "horizontal",
			layout_config = {
				horizontal = { preview_width = 0.48, width = 0.9, height = 0.8 },
				preview_cutoff = 0,
			},
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return { value = entry.value, display = entry.display, ordinal = entry.ordinal }
				end,
			}),
			previewer = previewers.new_buffer_previewer({
				title = " 📋 Profile Card Preview ",
				define_preview = function(self, entry)
					if not entry.value then
						return
					end
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, profile_card(entry.value))
					pcall(function()
						vim.bo[self.state.bufnr].filetype = "markdown"
					end)
					if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
						vim.wo[self.state.winid].conceallevel = 3
						vim.wo[self.state.winid].concealcursor = "nvic"
						local ok, rm_ui = pcall(require, "render-markdown.core.ui")
						if ok and rm_ui and type(rm_ui.update) == "function" then
							rm_ui.update(self.state.bufnr, self.state.winid, "UserCommand", true)
						end
					end
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				--- Deletes the selected profile and reopens the menu.
				local function action_delete(selection)
					if not (selection and selection.value) then
						return
					end
					local cur = M.load_profiles(root)
					local kept = {}
					for _, p in ipairs(cur.profiles) do
						if p.id ~= selection.value.id then
							table.insert(kept, p)
						end
					end
					cur.profiles = kept
					M.save_profiles(root, cur)
					notify("🗑️ Deleted launch profile: " .. selection.value.name)
					M.open_management_menu(root)
				end

				local function action_rename(selection)
					if not (selection and selection.value) then
						return
					end
					require("plugins.krs.input_modal").open({
						label = "Rename Launch Profile",
						default_value = selection.value.name,
						callback = function(ok, new_name)
							if ok and new_name ~= "" and new_name ~= selection.value.name then
								M.rename_profile(selection.value.id, new_name, root)
							end
							M.open_management_menu(root)
						end,
					})
				end

				local function action_edit(selection)
					if not (selection and selection.value) then
						return
					end
					M.open_form_editor(root, selection.value, function()
						M.open_management_menu(root)
					end)
				end

				local function action_toggle_favorite(selection)
					if not (selection and selection.value) then
						return
					end
					M.toggle_default(selection.value.id, root)
					M.open_management_menu(root)
				end

				local function action_create_new()
					M.open_creation_wizard(root, function()
						M.open_management_menu(root)
					end)
				end

				--- Closes the picker, then runs `fn` with the entry that was selected.
				--- @param fn function(selection)|function()
				--- @param needs_selection boolean|nil False for actions that ignore the row.
				local function with_selection(fn, needs_selection)
					return function()
						local selection = needs_selection ~= false and action_state.get_selected_entry() or nil
						actions.close(prompt_bufnr)
						fn(selection)
					end
				end

				actions.select_default:replace(with_selection(function(selection)
					if selection and selection.value then
						M.run_profile(selection.value)
					end
				end))

				map("n", "d", with_selection(action_delete))
				map("n", "r", with_selection(action_rename))
				map("n", "e", with_selection(action_edit))
				map("n", "f", with_selection(action_toggle_favorite))
				map("n", "a", with_selection(action_create_new, false))

				-- Control-key mirrors so the same actions work while typing a filter.
				map({ "n", "i" }, "<C-d>", with_selection(action_toggle_favorite))
				map({ "n", "i" }, "<C-e>", with_selection(action_edit))
				map({ "n", "i" }, "<C-n>", with_selection(action_create_new, false))
				map({ "n", "i" }, "<C-x>", with_selection(action_delete))

				return true
			end,
		})
		:find()
end

--- The `<C-S-s>` behaviour: stop a live debug session, else run the default
--- profile, else offer the picker (or the creation form when there are none).
function M.handle_smart_launch()
	local has_dap, dap = pcall(require, "dap")
	if has_dap and dap.session() then
		dap.terminate()
		notify("⏹️ Debug session terminated")
		return
	end

	local root = M.get_project_root()
	local data = M.load_profiles(root)

	if #data.profiles == 0 then
		M.open_creation_wizard(root, function(new_profile)
			M.run_profile(new_profile)
		end)
		return
	end

	for _, p in ipairs(data.profiles) do
		if p.is_default then
			M.run_profile(p)
			return
		end
	end

	M.open_management_menu(root)
end

--- Returns the primary default launch profile for a project root, if any.
--- @param root string|nil
--- @return table|nil
function M.get_default_profile(root)
	root = root or M.get_project_root()
	local data = M.load_profiles(root)
	for _, p in ipairs(data.profiles) do
		if p.is_default then
			return p
		end
	end
	return nil
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers `:LaunchProfiles`, `:LaunchProfilesSmart` and the keymaps.
function M.setup()
	pcall(vim.api.nvim_create_user_command, "LaunchProfiles", function()
		M.open_management_menu()
	end, { desc = "Open Launch Profiles Management UI" })

	pcall(vim.api.nvim_create_user_command, "LaunchProfilesSmart", function()
		M.handle_smart_launch()
	end, { desc = "Run Default Launch Profile or Open Management UI" })

	--- Leaves terminal mode first, so the mapping also works from a terminal.
	local function from_any_mode(fn)
		return function()
			local mode = vim.fn.mode()
			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			fn()
		end
	end

	local bindings = {
		{ keys = M.settings.keys.smart_launch, fn = M.handle_smart_launch, desc = "Smart Launch / Profile Debug UI" },
		{ keys = M.settings.keys.manage, fn = M.open_management_menu, desc = "Open Launch Profiles Management UI" },
	}
	for _, binding in ipairs(bindings) do
		for _, key in ipairs(binding.keys) do
			vim.keymap.set(
				{ "n", "i", "v", "t" },
				key,
				from_any_mode(function()
					binding.fn()
				end),
				{ noremap = true, silent = true, desc = binding.desc }
			)
		end
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.LaunchProfiles = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_launch_profiles",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "LaunchProfiles", "LaunchProfilesRun", "LaunchProfilesDebug" },
	keys = is_mobile_lp and {
		{ "<C-S-s>", mode = { "n", "i" }, desc = "Open Launch Profiles" },
		{ "<C-S>", mode = { "n", "i" }, desc = "Open Launch Profiles (Mobile)" },
		{ "<C-S-q>", mode = { "n", "i" }, desc = "Quick Launch Default Profile" },
		{ "<C-Q>", mode = { "n", "i" }, desc = "Quick Launch Default Profile (Mobile)" },
	} or {
		{ "<C-S-s>", mode = { "n", "i" }, desc = "Open Launch Profiles" },
		{ "<C-S-q>", mode = { "n", "i" }, desc = "Quick Launch Default Profile" },
	},
	config = M.setup,
}, { __index = M })
