-- ============================================================================
-- KRS PLUGIN: .NET Project Creator -- Create C# / .NET projects with `dotnet new`
-- ============================================================================
-- WHAT IT DOES
--   Presents an interactive picker of official .NET templates (Web API, Console,
--   Blazor, MVC, Class Library, Worker, xUnit, MSTest, Avalonia UI, etc.),
--   prompts for project name and target path, and generates the new .NET project!
--
-- COMMANDS
--   :DotnetNew / :CsharpNewProject / :DotnetCreateProject
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")

local M = {}

--- Curated list of popular .NET templates for `dotnet new`.
M.templates = {
	{ name = "🚀 ASP.NET Core Web API", short = "webapi", desc = "RESTful Web API service" },
	{ name = "💻 Console Application", short = "console", desc = "Command-line C# application" },
	{ name = "🌐 Blazor Web App", short = "blazor", desc = "Full-stack web app with C# & Razor" },
	{ name = "🖥️ ASP.NET Core Web App (MVC)", short = "mvc", desc = "Model-View-Controller web application" },
	{ name = "📚 Class Library", short = "classlib", desc = "Reusable C# library assembly" },
	{ name = "⚙️ Worker Service", short = "worker", desc = "Background service / daemon" },
	{ name = "🧪 xUnit Test Project", short = "xunit", desc = "xUnit unit testing project" },
	{ name = "🧪 MSTest Test Project", short = "mstest", desc = "MSTest unit testing project" },
	{ name = "🧪 NUnit Test Project", short = "nunit", desc = "NUnit unit testing project" },
	{ name = "🎨 Avalonia .NET App", short = "avalonia.app", desc = "Cross-platform Desktop UI app" },
	{ name = "🎨 Avalonia MVVM App", short = "avalonia.mvvm", desc = "Avalonia UI app with MVVM pattern" },
	{ name = "📂 Solution File", short = "sln", desc = ".NET Solution container file" },
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = ".NET Project Creator" })
end

--- Generates a new .NET project using `dotnet new`
--- @param template_short string
--- @param project_name string
--- @param target_dir string
function M.create_project(template_short, project_name, target_dir)
	if vim.fn.executable("dotnet") == 0 then
		notify("❌ .NET SDK ('dotnet') is not installed or not in PATH.", vim.log.levels.ERROR)
		return
	end

	target_dir = target_dir or (vim.fn.getcwd() .. "/" .. project_name)
	notify(string.format("🔨 Creating .NET project '%s' (%s)...", project_name, template_short))

	local cmd = { "dotnet", "new", template_short, "-n", project_name, "-o", target_dir }

	vim.system(cmd, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				notify(string.format("🎉 Successfully created .NET project '%s' in %s!", project_name, target_dir))

				-- Look for Program.cs or .csproj to open
				local files_to_check = {
					target_dir .. "/Program.cs",
					target_dir .. "/" .. project_name .. ".csproj",
					target_dir .. "/Class1.cs",
				}

				local file_to_open = nil
				for _, f in ipairs(files_to_check) do
					if (vim.uv or vim.loop).fs_stat(f) then
						file_to_open = f
						break
					end
				end

				if file_to_open then
					vim.cmd("edit " .. vim.fn.fnameescape(file_to_open))
				end
			else
				local err = (obj.stderr ~= "" and obj.stderr or obj.stdout) or "Unknown error"
				notify("❌ Failed to create .NET project: " .. err, vim.log.levels.ERROR)
			end
		end)
	end)
end

--- Opens the interactive template picker
function M.open_picker()
	local options = {}
	local template_map = {}

	for _, t in ipairs(M.templates) do
		local label = string.format("%s [%s] - %s", t.name, t.short, t.desc)
		table.insert(options, label)
		template_map[label] = t
	end

	table.insert(options, "🔍 Custom Template (Type Short Name)")

	vim.ui.select(options, {
		prompt = "🔨 Select .NET Project Template (dotnet new):",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if not choice then
			return
		end

		local short_name = ""
		if choice:find("Custom Template") then
			short_name = vim.fn.input("Enter dotnet new template short name: ", "console")
			if short_name == "" then
				return
			end
		else
			local selected = template_map[choice]
			if not selected then
				return
			end
			short_name = selected.short
		end

		local default_name = "MyDotnetApp"
		if short_name == "webapi" then
			default_name = "MyWebApi"
		elseif short_name == "classlib" then
			default_name = "MyLibrary"
		elseif short_name == "xunit" or short_name == "mstest" or short_name == "nunit" then
			default_name = "MyTests"
		end

		local project_name = vim.fn.input("Enter Project Name: ", default_name)
		if not project_name or project_name == "" then
			notify("Cancelled project creation.", vim.log.levels.WARN)
			return
		end

		local cwd = vim.fn.getcwd()
		local target_dir = cwd .. "/" .. project_name

		M.create_project(short_name, project_name, target_dir)
	end)
end

--- Setup user commands
function M.setup()
	if vim.fn.exists(":DotnetNew") == 0 then
		vim.api.nvim_create_user_command("DotnetNew", function()
			M.open_picker()
		end, { desc = "Create a new .NET project with interactive template picker (dotnet new)" })
	end

	if vim.fn.exists(":CsharpCreateProject") == 0 then
		vim.api.nvim_create_user_command("CsharpCreateProject", function()
			M.open_picker()
		end, { desc = "Create a new C# / .NET project (dotnet new)" })
	end

	if vim.fn.exists(":DotnetCreateProject") == 0 then
		vim.api.nvim_create_user_command("DotnetCreateProject", function()
			M.open_picker()
		end, { desc = "Create a new C# / .NET project (dotnet new)" })
	end
end

_G.DotnetCreator = M

return setmetatable({
	name = "krs_dotnet_creator",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "DotnetNew", "CsharpCreateProject", "DotnetCreateProject" },
	ft = { "cs", "xml" },
	config = M.setup,
}, { __index = M })
