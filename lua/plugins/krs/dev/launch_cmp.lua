-- ============================================================================
-- KRS PLUGIN: launch.json IntelliSense -- a blink.cmp completion source.
-- ============================================================================
-- WHAT IT COMPLETES (only inside a file named `launch.json`)
--   "pre_launch_tasks"  Tasks this project actually has: the saved ones from
--                       `.krsnvim/tasks.json` plus everything discoverable
--                       (npm scripts, Makefile targets, cargo/go commands).
--   "runtime"           Every runtime in krs.launch.runtimes -- the single source
--                       of truth, so a new language shows up here for free.
--   "mode"              run | debug.
--
-- WIRING
--   Registered as a blink.cmp source in lua/plugins/lsp/blink_sources.lua.
-- ============================================================================

local runtimes = require("krs.launch.runtimes")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Only this file name gets these completions.
	filename = "launch.json",

	--- LSP CompletionItemKind used for every item (12 = Value).
	item_kind = 12,

	--- One-line description per runtime. Runtimes missing here still complete.
	runtime_details = {
		bun = "Bun JavaScript/TypeScript runtime",
		node = "Node.js JavaScript runtime (npx tsx for TS)",
		deno = "Deno TypeScript/JavaScript runtime",
		python = "Python interpreter",
		go = "Go toolchain (go run)",
		php = "PHP CLI binary",
		dotnet = ".NET CLI (dotnet run)",
		lua = "Built-in Neovim LuaJIT runtime (nvim --headless -l)",
		krsnvimscript = "krsnvimscript automation script",
		krsnvimtranspiler = "Transpile a .krsnvim script to .sh / .ps1",
		custom = "Custom command string",
	},

	--- Launch modes offered for the "mode" field.
	modes = {
		{ label = "run", detail = "Execute in terminal task window" },
		{ label = "debug", detail = "Launch with DAP interactive debugger" },
	},

	--- JSON keys recognized, and which completion set each one gets.
	fields = {
		{ key = "pre_launch_tasks", kind = "tasks" },
		{ key = "runtime", kind = "runtimes" },
		{ key = "mode", kind = "modes" },
	},
}

-- ============================================================================
-- COMPLETION SETS
-- ============================================================================

--- Wraps a label and description as a blink.cmp item.
--- @param label string
--- @param detail string
--- @return table item
local function item(label, detail)
	return { label = label, kind = M.settings.item_kind, detail = detail, insertText = label }
end

--- Task names available in this project: saved first, then discovered.
--- @return table[] items
local function task_items()
	local ok, tasks = pcall(require, "plugins.krs.dev.tasks")
	if not ok then
		return {}
	end

	local root = tasks.get_project_root()
	local items, seen = {}, {}

	for _, task in ipairs(tasks.get_project_data(root).custom_tasks or {}) do
		local name = type(task) == "table" and (task.name or task.cmd) or tostring(task)
		if name and not seen[name] then
			seen[name] = true
			table.insert(items, item(name, "Saved Project Task"))
		end
	end

	for _, task in ipairs(tasks.discover_tasks(root) or {}) do
		local name = task.name or task.cmd
		if name and not seen[name] then
			seen[name] = true
			table.insert(items, item(name, "Discovered Task (" .. (task.source or "Project") .. ")"))
		end
	end

	return items
end

--- Every registered runtime.
--- @return table[] items
local function runtime_items()
	local items = {}
	for _, name in ipairs(runtimes.order) do
		table.insert(items, item(name, M.settings.runtime_details[name] or "Launch runtime"))
	end
	return items
end

--- The two launch modes.
--- @return table[] items
local function mode_items()
	local items = {}
	for _, mode in ipairs(M.settings.modes) do
		table.insert(items, item(mode.label, mode.detail))
	end
	return items
end

local providers = { tasks = task_items, runtimes = runtime_items, modes = mode_items }

-- ============================================================================
-- BLINK.CMP SOURCE INTERFACE
-- ============================================================================

--- Constructs a source instance. Required by blink.cmp.
--- @return table source
function M.new()
	return setmetatable({}, { __index = M })
end

--- Supplies completions for the field under the cursor.
--- @param context table blink.cmp context.
--- @param callback fun(result: table)
function M:get_completions(context, callback)
	local function respond(items)
		callback({ items = items or {}, is_incomplete_forward = false, is_incomplete_backward = false })
	end

	local buf = context.bufnr or vim.api.nvim_get_current_buf()
	if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t") ~= M.settings.filename then
		return respond({})
	end

	local line = context.line or ""
	local before_cursor = line:sub(1, context.cursor[2] or #line)

	-- The key may be on this line before the cursor, or simply somewhere on the
	-- line (a multi-line array, where the cursor sits inside the brackets).
	for _, field in ipairs(M.settings.fields) do
		if before_cursor:find(field.key, 1, true) or line:find('"' .. field.key .. '"', 1, true) then
			return respond(providers[field.kind]())
		end
	end

	respond({})
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.LaunchCmp = M

-- ============================================================================
-- LAZY.NVIM SPEC -- no config(): blink.cmp instantiates this source itself.
-- ============================================================================

return setmetatable({
	name = "krs_launch_cmp",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = true,
}, { __index = M })
