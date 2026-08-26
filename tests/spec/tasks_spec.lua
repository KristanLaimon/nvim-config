-- ============================================================================
-- tests/spec/tasks_spec.lua -- Task Runner logic (no UI, no processes).
-- ============================================================================
-- Covered: chain resolution, project discovery, and `.krsnvim/tasks.json`
-- persistence including the two legacy fallbacks. Terminal execution and the
-- Telescope picker are deliberately out of scope -- they need a real UI.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local tasks = require("plugins.krs.dev.tasks")
local path = require("krs.core.path")

local root

--- Writes `lines` to `<root>/<relative>`, creating directories as needed.
local function write(relative, lines)
	local file = path.join(root, relative)
	path.ensure_dir(vim.fs.dirname(file))
	vim.fn.writefile(lines, file)
	return file
end

describe("tasks.resolve_steps", function()
	it("wraps a bare command string", function()
		expect(tasks.resolve_steps("npm run dev", {})).toEqual({ "npm run dev" })
	end)

	it("returns the cmd of a simple task", function()
		expect(tasks.resolve_steps({ name = "Dev", cmd = "npm run dev" }, {})).toEqual({ "npm run dev" })
	end)

	it("expands a chain in order", function()
		local steps = tasks.resolve_steps({ name = "Ship", chain = { "build", "test", "deploy" } }, {})

		expect(steps).toEqual({ "build", "test", "deploy" })
	end)

	it("prefers chain over cmd when both are present", function()
		local steps = tasks.resolve_steps({ chain = { "a" }, cmd = "b" }, {})

		expect(steps).toEqual({ "a" })
	end)

	it("resolves depends_on before the task's own command", function()
		local pdata = { custom_tasks = { { name = "Build", cmd = "npm run build" } } }
		local steps = tasks.resolve_steps({ name = "Deploy", depends_on = { "Build" }, cmd = "npm run deploy" }, pdata)

		expect(steps).toEqual({ "npm run build", "npm run deploy" })
	end)

	it("resolves nested dependencies recursively", function()
		local pdata = {
			custom_tasks = {
				{ name = "Install", cmd = "npm ci" },
				{ name = "Build", depends_on = { "Install" }, cmd = "npm run build" },
			},
		}
		local steps = tasks.resolve_steps({ name = "Deploy", depends_on = { "Build" }, cmd = "deploy" }, pdata)

		expect(steps).toEqual({ "npm ci", "npm run build", "deploy" })
	end)

	it("ignores unknown dependency names instead of failing", function()
		local steps = tasks.resolve_steps({ depends_on = { "Nope" }, cmd = "go" }, { custom_tasks = {} })

		expect(steps).toEqual({ "go" })
	end)

	it("returns no steps for nil, numbers or an empty task", function()
		expect(tasks.resolve_steps(nil, {})).toEqual({})
		expect(tasks.resolve_steps(42, {})).toEqual({})
		expect(tasks.resolve_steps({ name = "Empty" }, {})).toEqual({})
	end)
end)

describe("tasks.discover_tasks", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
	end)

	afterEach(function()
		vim.fn.delete(root, "rf")
	end)

	it("finds nothing in an empty project", function()
		expect(tasks.discover_tasks(root)).toEqual({})
	end)

	it("reads Makefile targets and skips .PHONY and all", function()
		write("Makefile", { ".PHONY: build", "all:", "build:", "\tgcc x.c", "test-unit:" })

		local names = vim.tbl_map(function(entry)
			return entry.name
		end, tasks.discover_tasks(root))

		expect(names).toEqual({ "make build", "make test-unit" })
	end)

	it("reads package.json scripts", function()
		write("package.json", { '{"scripts":{"dev":"vite"}}' })

		local found = tasks.discover_tasks(root)

		expect(found).toHaveLength(1)
		expect(found[1].cmd).toBe("npm run dev")
		expect(found[1].source).toBe("package.json")
	end)

	it("survives a malformed package.json", function()
		write("package.json", { "{ broken" })

		expect(tasks.discover_tasks(root)).toEqual({})
	end)

	it("offers the standard commands for Cargo and Go projects", function()
		write("Cargo.toml", { "[package]" })
		write("go.mod", { "module x" })

		local cmds = vim.tbl_map(function(entry)
			return entry.cmd
		end, tasks.discover_tasks(root))

		expect(cmds).toEqual({ "cargo run", "cargo build", "cargo test", "go run .", "go test ./..." })
	end)
end)

describe("tasks project data persistence", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
	end)

	afterEach(function()
		vim.fn.delete(root, "rf")
	end)

	it("returns empty data for a project with no config", function()
		expect(tasks.get_project_data(root)).toEqual({ custom_tasks = {} })
	end)

	it("round-trips through .krsnvim/tasks.json", function()
		local task = { name = "Dev", cmd = "npm run dev" }
		tasks.save_project_data(root, { default_task = task, custom_tasks = { task } })

		local loaded = tasks.get_project_data(root)

		expect(loaded.default_task).toEqual(task)
		expect(loaded.custom_tasks).toEqual({ task })
	end)

	it("supports editing and updating custom tasks in project data", function()
		local initial = { name = "Build", cmd = "npm run build" }
		tasks.save_project_data(root, { custom_tasks = { initial } })

		local pdata = tasks.get_project_data(root)
		pdata.custom_tasks[1] = { name = "Build Production", cmd = "npm run build:prod" }
		tasks.save_project_data(root, pdata)

		local updated = tasks.get_project_data(root)
		expect(#updated.custom_tasks).toBe(1)
		expect(updated.custom_tasks[1].name).toBe("Build Production")
		expect(updated.custom_tasks[1].cmd).toBe("npm run build:prod")
	end)

	it("writes into .krsnvim/ specifically", function()
		tasks.save_project_data(root, { custom_tasks = {} })

		expect(path.is_file(path.join(root, ".krsnvim", "tasks.json"))).toBeTruthy()
	end)

	it("reads the legacy .nvimkrs root file when .krsnvim is absent", function()
		write(".nvimkrs", { '{"default_task":{"name":"Legacy","cmd":"make"},"custom_tasks":[]}' })

		expect(tasks.get_project_data(root).default_task.name).toBe("Legacy")
	end)

	it("toggles off when re-running same active task, and allocates new slot for different task", function()
		local t1 = { name = "Long Task 1", cmd = "echo t1" }
		local t2 = { name = "Long Task 2", cmd = "echo t2" }

		tasks.run_task_item(t1, root)
		local s1 = tasks.slots[1]
		expect(s1).toBeTruthy()

		-- Running same task t1 again toggles it off
		tasks.run_task_item(t1, root)
		expect(tasks.slots[1].job_id).toBeNil()

		-- Running different task t2 allocates slot
		tasks.run_task_item(t2, root)
		expect(tasks.slots[1].name).toBe("Long Task 2")
	end)

	it("prefers .krsnvim/tasks.json over the legacy file", function()
		write(".nvimkrs", { '{"default_task":{"name":"Legacy"},"custom_tasks":[]}' })
		tasks.save_project_data(root, { default_task = { name = "Current" }, custom_tasks = {} })

		expect(tasks.get_project_data(root).default_task.name).toBe("Current")
	end)

	it("coerces a malformed custom_tasks field to an empty list", function()
		write(".krsnvim/tasks.json", { '{"custom_tasks": "not a list"}' })

		expect(tasks.get_project_data(root).custom_tasks).toEqual({})
	end)
end)
