-- ============================================================================
-- KRS PLUGIN: Dev Server Bridge (Vite / Astro / SvelteKit / Next / Angular).
-- ============================================================================
-- WHY IT EXISTS
--   Browser debug configurations need a URL that is ALREADY serving. This starts
--   the project's dev server (or reuses one that is up) and hands back its URL.
--
-- HOW TO USE IT
--   As a *function value* inside a nvim-dap configuration:
--       url = function() return require("plugins.krs.dev.dev_server").url() end
--   nvim-dap resolves those inside a coroutine, so yielding here waits for the
--   server without blocking the editor, and the browser only launches once the
--   port answers. Every public function below must run inside a coroutine.
--
-- PORT DETECTION
--   A TCP connect is the only check that proves something is ACCEPTING. Parsing
--   `netstat` reports a bound socket and races the server's first real listen.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Ports probed, in order. Override per project with `vim.g.krs_dev_ports`.
	--- ponytail: a fixed list instead of parsing vite/astro/angular/next configs,
	--- each of which puts the port somewhere different and can be overridden by a
	--- CLI flag anyway.
	default_ports = {
		5173, -- vite / sveltekit
		4321, -- astro
		3000, -- next / nuxt / remix
		4200, -- angular
		5174, -- vite, second instance
		8080,
		1420, -- tauri
		3001,
	},

	--- How long to wait for the dev server to come up, in milliseconds.
	startup_timeout_ms = 60000,

	--- Gap between port sweeps while waiting for startup.
	poll_interval_ms = 500,

	--- How long a single TCP probe may take before it counts as "closed".
	probe_timeout_ms = 400,

	--- Host the probe connects to, and the URL template handed to the debugger.
	host = "127.0.0.1",
	url_template = "http://localhost:%d",

	--- Lockfile -> package manager. First match wins.
	package_managers = {
		{ lockfile = "bun.lock", runner = "bun run" },
		{ lockfile = "bun.lockb", runner = "bun run" },
		{ lockfile = "pnpm-lock.yaml", runner = "pnpm" },
		{ lockfile = "yarn.lock", runner = "yarn" },
	},

	--- Used when no lockfile is recognized.
	default_runner = "npm run",

	--- package.json scripts tried, in order.
	dev_scripts = { "dev", "start", "serve" },

	--- Notification title.
	notify_title = "Dev Server",
}

-- ============================================================================
-- COROUTINE PLUMBING
-- ============================================================================

--- Runs `start(resume)` and yields until it calls back, returning its value.
--- @param start fun(resume: fun(value: any))
--- @return any value
local function await(start)
	local co = assert(coroutine.running(), "krs dev_server must be called from a coroutine")
	local result, done = nil, false

	start(function(value)
		result, done = value, true
		if coroutine.status(co) == "suspended" then
			coroutine.resume(co)
		end
	end)

	if not done then
		coroutine.yield()
	end
	return result
end

--- Yields for `ms` milliseconds.
--- @param ms integer
local function sleep(ms)
	await(function(resume)
		vim.defer_fn(resume, ms)
	end)
end

--- Ports to probe for this project.
--- @return integer[]
local function candidate_ports()
	return vim.g.krs_dev_ports or M.settings.default_ports
end

--- Project root, shared with the task runner.
--- @return string
local function project_root()
	return require("plugins.krs.dev.tasks").get_project_root()
end

--- Attempts a TCP connect, reporting whether anything accepted.
--- @param port integer
--- @param cb fun(is_open: boolean) Always called exactly once, on the main loop.
local function probe(port, cb)
	local sock = vim.uv.new_tcp()
	local settled = false

	local function finish(is_open)
		if settled then
			return
		end
		settled = true
		pcall(function()
			sock:close()
		end)
		vim.schedule(function()
			cb(is_open)
		end)
	end

	sock:connect(M.settings.host, port, function(err)
		finish(err == nil)
	end)
	vim.defer_fn(function()
		finish(false)
	end, M.settings.probe_timeout_ms)
end

-- ============================================================================
-- API
-- ============================================================================

--- First candidate port that answers right now.
--- All ports are probed in parallel; the first success wins.
--- @return integer|nil port
function M.find_running_port()
	return await(function(resume)
		local ports = candidate_ports()
		local pending, answered = #ports, false

		for _, port in ipairs(ports) do
			probe(port, function(is_open)
				pending = pending - 1
				if is_open and not answered then
					answered = true
					resume(port)
				elseif pending == 0 and not answered then
					resume(nil)
				end
			end)
		end
	end)
end

--- The command that starts this project's dev server.
--- The lockfile decides the package manager, package.json decides the script.
---
--- @param root string|nil Project root.
--- @return string cmd
function M.dev_command(root)
	root = root or project_root()

	local runner = M.settings.default_runner
	for _, manager in ipairs(M.settings.package_managers) do
		if path.is_file(path.join(root, manager.lockfile)) then
			runner = manager.runner
			break
		end
	end

	local script = M.settings.dev_scripts[1]
	local scripts = store.load(path.join(root, "package.json"), {}).scripts or {}
	for _, name in ipairs(M.settings.dev_scripts) do
		if scripts[name] then
			script = name
			break
		end
	end

	return runner .. " " .. script
end

--- URL of the running dev server, starting it when nothing is up yet.
--- Returns nil (and notifies) when the server never came up, which aborts the
--- debug session instead of launching a browser at a dead URL.
---
--- @param timeout_ms integer|nil Overrides `M.settings.startup_timeout_ms`.
--- @return string|nil url
function M.url(timeout_ms)
	timeout_ms = timeout_ms or M.settings.startup_timeout_ms

	local port = M.find_running_port()
	if port then
		return string.format(M.settings.url_template, port)
	end

	local root = project_root()
	local cmd = M.dev_command(root)
	vim.notify("🌐 Starting dev server: " .. cmd, vim.log.levels.INFO, { title = M.settings.notify_title })
	require("plugins.krs.dev.tasks").run_task_cmd(cmd, root)

	local deadline = vim.uv.now() + timeout_ms
	repeat
		sleep(M.settings.poll_interval_ms)
		port = M.find_running_port()
	until port or vim.uv.now() > deadline

	if not port then
		vim.notify(
			"❌ No dev server answered on "
				.. table.concat(candidate_ports(), ", ")
				.. " within "
				.. math.floor(timeout_ms / 1000)
				.. "s.\n  Set vim.g.krs_dev_ports if it serves on a different port.",
			vim.log.levels.ERROR,
			{ title = M.settings.notify_title }
		)
		return nil
	end

	vim.notify("✅ Dev server up on port " .. port, vim.log.levels.INFO, { title = M.settings.notify_title })
	return string.format(M.settings.url_template, port)
end

--- URL of a server that is ALREADY running. Never starts anything -- this is what
--- "attach" debug configurations use.
--- @return string|nil url
function M.existing_url()
	local port = M.find_running_port()
	if not port then
		vim.notify(
			"❌ No dev server found on "
				.. table.concat(candidate_ports(), ", ")
				.. ".\n  Use a 'Launch' config to start one.",
			vim.log.levels.ERROR,
			{ title = M.settings.notify_title }
		)
		return nil
	end
	return string.format(M.settings.url_template, port)
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.DevServer = M

-- ============================================================================
-- LAZY.NVIM SPEC -- no config(): debug configurations call in directly.
-- ============================================================================

return setmetatable({
	name = "krs_dev_server",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = true,
}, { __index = M })
