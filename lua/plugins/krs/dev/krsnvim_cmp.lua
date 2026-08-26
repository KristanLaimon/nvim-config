-- ============================================================================
-- KRS PLUGIN: .krsnvim IntelliSense -- a blink.cmp completion source.
-- ============================================================================
-- WHAT IT COMPLETES (only inside `*.krsnvim` files)
--   console.<method>   log, dir, info, warn, error, debug, json, dump
--   fetch.<method>     get, post, put, delete, patch, head
--   import("<module>") json, yaml, toml, terminal, cli, fs, fetch, console, ...
--   krsnvim.<module>   the same library modules, as fields
--   anything else      the top-level globals available to a script
--
-- HOW TO ADD COMPLETIONS
--   Everything is data: append to the relevant list in `M.settings.contexts`.
--   `pattern` is matched against the text BEFORE the cursor; the first context
--   that matches wins, and the last one (no pattern) is the fallback.
--
-- WIRING
--   Registered as a blink.cmp source in lua/plugins/lsp/blink_sources.lua.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

--- LSP CompletionItemKind values used below.
local KIND = { method = 2, object = 3, module = 9, value = 12 }

--- Marks an item's `insertText` as an LSP snippet (`${1:...}` placeholders).
local SNIPPET = 2

M.settings = {
	--- Files this source fires in.
	file_pattern = "%.krsnvim$",
	filetype = "krsnvim",

	--- Checked in order; the first matching `pattern` wins, and an entry with no
	--- pattern is the fallback.
	contexts = {
		{
			pattern = "console%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "log",
					detail = "console.log(...) - Print space-separated args / pretty JSON tables",
					insertText = "log(${1:data})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "dir",
					detail = "console.dir(obj) - Inspect table object in multi-line indented JSON",
					insertText = "dir(${1:object})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "info",
					detail = "console.info(...) - Log with ℹ️ [INFO] prefix",
					insertText = "info(${1:message})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "warn",
					detail = "console.warn(...) - Log with ⚠️ [WARN] prefix",
					insertText = "warn(${1:message})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "error",
					detail = "console.error(...) - Log with ❌ [ERROR] prefix",
					insertText = "error(${1:message})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "debug",
					detail = "console.debug(...) - Log with 🐛 [DEBUG] prefix",
					insertText = "debug(${1:message})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "json",
					detail = "console.json(obj) - Format object to indented JSON string",
					insertText = "json(${1:object})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "dump",
					detail = "console.dump(obj) - Alias for console.dir",
					insertText = "dump(${1:object})",
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = "fetch%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "get",
					detail = "fetch.get(url, opts) - Perform HTTP GET request",
					insertText = 'get("${1:url}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "post",
					detail = "fetch.post(url, body, opts) - Perform HTTP POST request",
					insertText = 'post("${1:url}", ${2:body})',
					insertTextFormat = SNIPPET,
				},
				{
					label = "put",
					detail = "fetch.put(url, body, opts) - Perform HTTP PUT request",
					insertText = 'put("${1:url}", ${2:body})',
					insertTextFormat = SNIPPET,
				},
				{
					label = "delete",
					detail = "fetch.delete(url, opts) - Perform HTTP DELETE request",
					insertText = 'delete("${1:url}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "patch",
					detail = "fetch.patch(url, body, opts) - Perform HTTP PATCH request",
					insertText = 'patch("${1:url}", ${2:body})',
					insertTextFormat = SNIPPET,
				},
				{
					label = "head",
					detail = "fetch.head(url, opts) - Perform HTTP HEAD request",
					insertText = 'head("${1:url}")',
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = 'import%s*%(%s*"?%a*$',
			kind = KIND.value,
			items = {
				{ label = '"json"', detail = "krsnvim.json - JSON parser & file I/O", insertText = '"json"' },
				{ label = '"yaml"', detail = "krsnvim.yaml - YAML parser & file I/O", insertText = '"yaml"' },
				{ label = '"toml"', detail = "krsnvim.toml - TOML parser & file I/O", insertText = '"toml"' },
				{
					label = '"terminal"',
					detail = "krsnvim.terminal - Cross-platform shell execution",
					insertText = '"terminal"',
				},
				{ label = '"cmd"', detail = "krsnvim.cmd - Cross-platform shell execution suite alias", insertText = '"cmd"' },
				{ label = '"cli"', detail = "krsnvim.cli - CLI argument parser & menu helper", insertText = '"cli"' },
				{ label = '"fs"', detail = "krsnvim.fs - File system helper suite", insertText = '"fs"' },
				{ label = '"fetch"', detail = "krsnvim.fetch - HTTP/HTTPS fetch client", insertText = '"fetch"' },
				{
					label = '"console"',
					detail = "krsnvim.console - Console logger & pretty-JSON printer",
					insertText = '"console"',
				},
				{
					label = '"async"',
					detail = "krsnvim.async - Concurrency, parallelism & async/await suite",
					insertText = '"async"',
				},
				{
					label = '"concurrent"',
					detail = "krsnvim.async - Concurrency & parallel tasks alias",
					insertText = '"concurrent"',
				},
				{
					label = '"parallel"',
					detail = "krsnvim.async - Parallelism & multi-threading alias",
					insertText = '"parallel"',
				},
				{ label = '"test"', detail = "krsnvim.test - Vitest-like testing framework", insertText = '"test"' },
				{ label = '"tests"', detail = "krsnvim.tests - Vitest-like testing framework", insertText = '"tests"' },
			},
		},
		{
			pattern = "krsnvim%.%a*$",
			kind = KIND.module,
			items = {
				{
					label = "console",
					detail = "krsnvim.console - Console logger & pretty-JSON printer",
					insertText = "console",
				},
				{ label = "fetch", detail = "krsnvim.fetch - HTTP/HTTPS fetch client", insertText = "fetch" },
				{ label = "test", detail = "krsnvim.test - Vitest-like testing framework", insertText = "test" },
				{ label = "async", detail = "krsnvim.async - Concurrency & OS thread parallelism suite", insertText = "async" },
				{ label = "concurrent", detail = "krsnvim.async - Concurrency alias", insertText = "concurrent" },
				{ label = "parallel", detail = "krsnvim.async - Parallelism alias", insertText = "parallel" },
				{ label = "json", detail = "krsnvim.json - JSON parser & file I/O", insertText = "json" },
				{ label = "yaml", detail = "krsnvim.yaml - YAML parser & file I/O", insertText = "yaml" },
				{ label = "toml", detail = "krsnvim.toml - TOML parser & file I/O", insertText = "toml" },
				{ label = "terminal", detail = "krsnvim.terminal - Shell execution suite", insertText = "terminal" },
				{ label = "cmd", detail = "krsnvim.cmd - Shell execution suite alias", insertText = "cmd" },
				{ label = "cli", detail = "krsnvim.cli - CLI argument parser & UI", insertText = "cli" },
				{ label = "fs", detail = "krsnvim.fs - File system helpers", insertText = "fs" },
				{ label = "tests", detail = "krsnvim.tests - Testing framework runner", insertText = "tests" },
			},
		},
		{
			pattern = "cmd%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "exec",
					detail = "cmd.exec(cmd, opts) - Synchronously execute shell command",
					insertText = 'exec("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "run",
					detail = "cmd.run(cmd, opts) - Synchronously execute shell command",
					insertText = 'run("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "cwd",
					detail = "cmd.cwd() - Get current working directory",
					insertText = "cwd()",
					insertTextFormat = SNIPPET,
				},
				{
					label = "echo",
					detail = "cmd.echo(msg) - Output message to console",
					insertText = 'echo("${1:message}")',
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = "async%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "parallel",
					detail = "async.parallel({ t1, t2 }, cb) - Execute tasks concurrently",
					insertText = "parallel({ ${1:tasks} })",
					insertTextFormat = SNIPPET,
				},
				{
					label = "race",
					detail = "async.race({ t1, t2 }, cb) - Execute tasks concurrently and resolve first result",
					insertText = "race({ ${1:tasks} })",
					insertTextFormat = SNIPPET,
				},
				{
					label = "thread",
					detail = "async.thread(fn, args, cb) - Execute worker function on background OS thread",
					insertText = "thread(${1:worker_fn}, { ${2:args} })",
					insertTextFormat = SNIPPET,
				},
				{
					label = "map",
					detail = "async.map(items, worker_fn, opts) - Map items concurrently",
					insertText = "map(${1:items}, ${2:worker_fn})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "series",
					detail = "async.series({ t1, t2 }, cb) - Execute tasks sequentially",
					insertText = "series({ ${1:tasks} })",
					insertTextFormat = SNIPPET,
				},
				{
					label = "waterfall",
					detail = "async.waterfall({ t1, t2 }, cb) - Sequential task chain passing arguments",
					insertText = "waterfall({ ${1:tasks} })",
					insertTextFormat = SNIPPET,
				},
				{
					label = "sleep",
					detail = "async.sleep(ms) - Non-blocking delay",
					insertText = "sleep(${1:ms})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "run",
					detail = "async.run(fn) - Run function in managed coroutine for async/await",
					insertText = "run(function()\n\t${1}\nend)",
					insertTextFormat = SNIPPET,
				},
				{
					label = "channel",
					detail = "async.channel() - Create thread-safe / coroutine-safe channel",
					insertText = "channel()",
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = "cli%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "parse_args",
					detail = "cli.parse_args(args, schema) - Parse flags and arguments",
					insertText = "parse_args(${1:arg}, ${2:schema})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "menu",
					detail = "cli.menu(title, options, callback) - Render interactive menu",
					insertText = 'menu("${1:title}", ${2:options}, function(choice, idx)\n\t${3}\nend)',
					insertTextFormat = SNIPPET,
				},
				{
					label = "help",
					detail = "cli.help(schema) - Generate formatted CLI help screen",
					insertText = "help(${1:schema})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "colorize",
					detail = "cli.colorize(text, color) - Colorize text with ANSI colors",
					insertText = "colorize(${1:text}, ${2:cli.colors.cyan})",
					insertTextFormat = SNIPPET,
				},
				{ label = "colors", detail = "cli.colors - Table of ANSI color codes", insertText = "colors.${1:cyan}" },
				{
					label = "ascii_title",
					detail = "cli.ascii_title(text, opts) - Generate ASCII art title banner",
					insertText = 'ascii_title("${1:title}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "table",
					detail = "cli.table(headers, rows) - Render formatted ASCII data table",
					insertText = "table(${1:headers}, ${2:rows})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "box",
					detail = "cli.box(content, title) - Render text box container",
					insertText = 'box(${1:content}, "${2:title}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "spinner",
					detail = "cli.spinner(message, work_fn) - Render animated terminal spinner",
					insertText = 'spinner("${1:message}", function()\n\t${2}\nend)',
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = "terminal%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "run",
					detail = "terminal.run(cmd, opts) - Execute command in terminal",
					insertText = 'run("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "exec",
					detail = "terminal.exec(cmd, opts) - Synchronously execute command",
					insertText = 'exec("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "sh",
					detail = "terminal.sh(cmd) - Run shell command returning stdout/stderr",
					insertText = 'sh("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "spawn",
					detail = "terminal.spawn(cmd, args, opts) - Spawn process",
					insertText = 'spawn("${1:cmd}", { ${2:args} })',
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = "term%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "run",
					detail = "term.run(cmd, opts) - Execute command in terminal",
					insertText = 'run("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "exec",
					detail = "term.exec(cmd, opts) - Synchronously execute command",
					insertText = 'exec("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "sh",
					detail = "term.sh(cmd) - Run shell command returning stdout/stderr",
					insertText = 'sh("${1:command}")',
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			pattern = "fs%.%a*$",
			kind = KIND.method,
			items = {
				{
					label = "exists",
					detail = "fs.exists(path) - Check if path exists",
					insertText = 'exists("${1:path}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "read",
					detail = "fs.read(path) - Read file content",
					insertText = 'read("${1:path}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "write",
					detail = "fs.write(path, content) - Write string content to file",
					insertText = 'write("${1:path}", ${2:content})',
					insertTextFormat = SNIPPET,
				},
				{
					label = "mkdir",
					detail = "fs.mkdir(path) - Create directory recursively",
					insertText = 'mkdir("${1:path}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "remove",
					detail = "fs.remove(path) - Remove file or directory",
					insertText = 'remove("${1:path}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "list",
					detail = "fs.list(path) - List files and directories",
					insertText = 'list("${1:path}")',
					insertTextFormat = SNIPPET,
				},
			},
		},
		{
			-- Fallback: the globals a script starts with.
			items = {
				{
					label = "console",
					kind = KIND.object,
					detail = "krsnvim.console - Human-readable console logger & JSON printer",
					insertText = "console.log(${1:data})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "fetch",
					kind = KIND.object,
					detail = "krsnvim.fetch - HTTP/HTTPS Web-standard fetch client",
					insertText = 'fetch.get("${1:url}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "cli",
					kind = KIND.object,
					detail = "krsnvim.cli - CLI argument parser & UI menu helper",
					insertText = 'cli.menu("${1:title}", ${2:options}, function(choice, idx)\n\t${3}\nend)',
					insertTextFormat = SNIPPET,
				},
				{
					label = "terminal",
					kind = KIND.object,
					detail = "krsnvim.terminal - Shell command execution suite",
					insertText = 'terminal.run("${1:command}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "fs",
					kind = KIND.object,
					detail = "krsnvim.fs - File system manipulation suite",
					insertText = 'fs.exists("${1:path}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "describe",
					kind = KIND.object,
					detail = "krsnvim.test - Test suite block",
					insertText = 'describe("${1:suite}", function()\n\t${2}\nend)',
					insertTextFormat = SNIPPET,
				},
				{
					label = "test",
					kind = KIND.object,
					detail = "krsnvim.test - Test case block",
					insertText = 'test("${1:name}", function()\n\t${2}\nend)',
					insertTextFormat = SNIPPET,
				},
				{
					label = "expect",
					kind = KIND.object,
					detail = "krsnvim.test - Assertion builder",
					insertText = "expect(${1:actual}).toBe(${2:expected})",
					insertTextFormat = SNIPPET,
				},
				{
					label = "async",
					kind = KIND.object,
					detail = "krsnvim.async - Concurrency, parallelism & async/await suite",
					insertText = "async",
					insertTextFormat = SNIPPET,
				},
				{
					label = "import",
					kind = KIND.object,
					detail = "krsnvim.import - Smart module & file loader",
					insertText = 'import("${1:module}")',
					insertTextFormat = SNIPPET,
				},
				{
					label = "krsnvim",
					kind = KIND.module,
					detail = "krsnvim - Automation library suite",
					insertText = "krsnvim",
				},
			},
		},
	},
}

-- ============================================================================
-- BLINK.CMP SOURCE INTERFACE
-- ============================================================================

--- Constructs a source instance. Required by blink.cmp.
--- @return table source
function M.new()
	return setmetatable({}, { __index = M })
end

--- Completions for the expression under the cursor.
--- @param context table blink.cmp context.
--- @param callback fun(result: table)
function M:get_completions(context, callback)
	local function respond(items)
		callback({ items = items or {}, is_incomplete_forward = false, is_incomplete_backward = false })
	end

	local ft = vim.bo[buf].filetype
	if not (ft == "lua" or ft == "krsnvim" or name:match(M.settings.file_pattern) or name:match("%.lua$") ~= nil) then
		return respond({})
	end

	local line = context.line or ""
	local before_cursor = line:sub(1, context.cursor[2] or #line)

	for _, ctx in ipairs(M.settings.contexts) do
		if not ctx.pattern or before_cursor:match(ctx.pattern) then
			local items = {}
			for _, item in ipairs(ctx.items) do
				table.insert(items, {
					label = item.label,
					kind = item.kind or ctx.kind,
					detail = item.detail,
					insertText = item.insertText,
					insertTextFormat = item.insertTextFormat,
				})
			end
			return respond(items)
		end
	end

	respond({})
end

-- ============================================================================
-- LAZY.NVIM SPEC -- no config(): blink.cmp instantiates this source itself.
-- ============================================================================

return setmetatable({
	name = "krs_krsnvim_cmp",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = true,
}, { __index = M })
