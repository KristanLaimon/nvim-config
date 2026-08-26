-- ============================================================================
-- KRS PLUGIN: NuGet Manager -- package references for C# projects.
-- ============================================================================
-- WHAT IT DOES
--   Lists `<PackageReference>` entries straight out of the `.csproj` and lets you
--   add, update or remove them. `:NugetManager` / `<leader>ng`.
--
-- WHY IT READS THE .csproj DIRECTLY
--   `dotnet list package` needs a restore and a recent SDK; the XML is always
--   there and parsing it works offline. WRITES still go through the `dotnet` CLI,
--   because that is the tool that mutates the project file correctly.
--
-- PICKER KEYS
--   a / <C-a> add     u / <C-u> update     d / <C-d> remove
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Glob used to find project files under the working directory.
	project_glob = "**/*.csproj",

	--- Notification title.
	notify_title = "Nuget",

	--- Picker geometry.
	picker_width = 0.75,

	keys = {
		--- Open the manager.
		open = nil,
	},

	--- Both attribute orders of a PackageReference. Each pattern captures two
	--- values; `swap` says the version comes first.
	reference_patterns = {
		{ pattern = '<PackageReference%s+Include="([^"]+)"%s+Version="([^"]+)"', swap = false },
		{ pattern = '<PackageReference%s+Version="([^"]+)"%s+Include="([^"]+)"', swap = true },
	},
}

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

-- ============================================================================
-- PROJECT DISCOVERY & PARSING
-- ============================================================================

--- Project files under the working directory.
--- @return string[] paths
local function find_projects()
	return vim.fn.globpath(vim.fn.getcwd(), M.settings.project_glob, false, true)
end

--- True when this workspace contains a C# project.
--- @return boolean
function M.has_csharp_project()
	return #find_projects() > 0
end

--- Resolves the project to operate on, asking when there are several.
--- @param callback fun(csproj: string)
local function with_project(callback)
	local matches = find_projects()

	if #matches == 0 then
		notify("No .csproj found in current project", vim.log.levels.WARN)
		return
	end
	if #matches == 1 then
		callback(matches[1])
		return
	end

	vim.ui.select(matches, { prompt = "Select .csproj:" }, function(choice)
		if choice then
			callback(choice)
		end
	end)
end

--- Package references declared in a project file, sorted by name.
--- @param csproj_path string
--- @return table[] packages `{ name, version }`
local function parse_packages(csproj_path)
	local content = store.read_file(csproj_path)
	if not content then
		return {}
	end

	local packages, seen = {}, {}
	for _, rule in ipairs(M.settings.reference_patterns) do
		for first, second in content:gmatch(rule.pattern) do
			local name = rule.swap and second or first
			local version = rule.swap and first or second
			if not seen[name] then
				seen[name] = true
				table.insert(packages, { name = name, version = version })
			end
		end
	end

	table.sort(packages, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return packages
end

--- Runs `dotnet` with the given arguments, reporting the outcome.
--- @param args string[] Arguments after `dotnet`.
--- @param on_done fun(ok: boolean)|nil
local function run_dotnet(args, on_done)
	notify("dotnet " .. table.concat(args, " "))

	vim.system(vim.list_extend({ "dotnet" }, args), { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				notify(
					(result.stderr ~= "" and result.stderr or result.stdout) or "dotnet command failed",
					vim.log.levels.ERROR
				)
			else
				notify("Done")
			end
			if on_done then
				on_done(result.code == 0)
			end
		end)
	end)
end

--- Builds the `dotnet add package` argument list.
--- @param csproj string Project file.
--- @param name string Package name.
--- @param version string|nil Blank or nil means latest.
--- @return string[] args
local function add_package_args(csproj, name, version)
	local args = { "add", csproj, "package", name }
	if version and version ~= "" then
		table.insert(args, "--version")
		table.insert(args, version)
	end
	return args
end

-- ============================================================================
-- PICKER
-- ============================================================================

--- Opens the package picker for a project file.
--- @param csproj string Project file path.
function M.show_picker(csproj)
	if not pcall(require, "telescope") then
		notify("Telescope is not available for Nuget Manager", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local themes = require("telescope.themes")

	pickers
		.new(
			themes.get_dropdown({
				prompt_title = string.format(
					" 📦 Nuget [%s] (a: Add | u: Update | d: Remove) ",
					vim.fn.fnamemodify(csproj, ":t")
				),
				width = M.settings.picker_width,
				results_title = "Package References",
			}),
			{
				finder = finders.new_table({
					results = parse_packages(csproj),
					entry_maker = function(entry)
						return {
							value = entry,
							display = string.format("%s  (%s)", entry.name, entry.version),
							ordinal = entry.name,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					--- Reopens the picker so the list reflects the change.
					local function refresh()
						vim.schedule(function()
							M.show_picker(csproj)
						end)
					end

					--- Binds one action to a normal-mode and an insert-mode key.
					local function map_both(normal_key, insert_key, fn)
						map("n", normal_key, fn)
						map("i", insert_key, fn)
					end

					--- Selected package, or nil.
					local function selected()
						local selection = action_state.get_selected_entry()
						return selection and selection.value or nil
					end

					map_both("a", "<C-a>", function()
						actions.close(prompt_bufnr)
						vim.schedule(function()
							vim.ui.input({ prompt = "Package name to add: " }, function(name)
								if not name or name == "" then
									return
								end
								vim.ui.input({ prompt = "Version (blank = latest): " }, function(version)
									run_dotnet(add_package_args(csproj, name, version), refresh)
								end)
							end)
						end)
					end)

					map_both("u", "<C-u>", function()
						local package = selected()
						if not package then
							return
						end
						actions.close(prompt_bufnr)
						vim.schedule(function()
							vim.ui.input({ prompt = "New version for " .. package.name .. " (blank = latest): " }, function(version)
								run_dotnet(add_package_args(csproj, package.name, version), refresh)
							end)
						end)
					end)

					map_both("d", "<C-d>", function()
						local package = selected()
						if not package then
							return
						end
						actions.close(prompt_bufnr)
						vim.schedule(function()
							run_dotnet({ "remove", csproj, "package", package.name }, refresh)
						end)
					end)

					return true
				end,
			}
		)
		:find()
end

--- Opens the manager, choosing the project first.
function M.open_manager()
	with_project(M.show_picker)
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers `:NugetManager` and its keymap.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	if vim.fn.exists(":NugetManager") == 0 then
		vim.api.nvim_create_user_command("NugetManager", function()
			if not M.has_csharp_project() then
				notify("No C# project (.csproj) found in current workspace", vim.log.levels.WARN)
				return
			end
			M.open_manager()
		end, { desc = "Open Nuget Package Manager (C# projects only)" })
	end

	vim.keymap.set("n", M.settings.keys.open, function()
		vim.cmd("NugetManager")
	end, { desc = "Nuget Package Manager" })
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.NugetManager = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_nuget_manager",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = "NugetManager",
	ft = { "cs" },
	keys = {},
	dependencies = { "nvim-telescope/telescope.nvim" },
	config = M.setup,
}, { __index = M })
