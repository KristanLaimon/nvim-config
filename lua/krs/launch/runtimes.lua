-- ============================================================================
-- krs.launch.runtimes -- One table describing every runtime a launch profile
-- can use: how to RUN it in a terminal, and how to DEBUG it through DAP.
-- ============================================================================
-- WHY THIS EXISTS
--   Adding a language used to mean editing two long if/elseif chains inside
--   launch_profiles.lua and hoping neither was missed. Both chains now live as
--   data in each language's own lua/krs/langs/<lang>/init.lua (`M.launch_runtimes`
--   -- see lua/krs/langs/typescript/init.lua for the fullest example), and this
--   file only merges them into one registry plus the shared dispatch API.
--
-- HOW TO ADD A RUNTIME
--   1. Add an entry to the owning language's `M.launch_runtimes` (or, for a
--      runtime with no owning language, to `GENERIC_RUNTIMES` below).
--   2. Add its key to `M.order` so the profile form can cycle to it.
--   3. If it needs a debug adapter, make sure mason-nvim-dap installs it and that
--      `adapter_hint` explains how, or the error message will be useless.
--
-- ENTRY SHAPE
--   command      string|function(ctx) -> string
--                  Executable prefix. The entry point and args are appended by
--                  the caller. An empty string runs the entry point directly.
--   dap          function(profile, root, ctx) -> table|nil
--                  DAP configuration. Omit to use the js-debug default.
--   execute      function(ctx) -> boolean
--                  Fully custom launch. Return true when the runtime handled the
--                  launch itself and no command should be run.
--
-- CONTEXT (`ctx`) passed to every callback
--   { root, entry, full_entry, is_ts, args, args_str, profile }
-- ============================================================================

local path = require("krs.core.path")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

--- Runtime keys in the order the profile form cycles through them.
M.order = {
	"bun",
	"node",
	"deno",
	"python",
	"go",
	"php",
	"dotnet",
	"cpp",
	"zig",
	"ruby",
	"haskell",
	"lua",
	"krsnvimscript",
	"krsnvimtranspiler",
	"custom",
}

--- Runtime used when a profile does not name one.
M.default_runtime = "node"

--- Runtimes with no owning lua/krs/langs/<lang> module: `custom` has no
--- language at all, and is not a real command.
local GENERIC_RUNTIMES = {
	-- Runs the entry point as-is, for anything not covered by a language module.
	custom = { command = "" },
}

--- Every supported runtime, merged from each language module's `launch_runtimes`
--- plus the generic ones above. Adapter type names must match what
--- mason-nvim-dap and nvim-dap-go register: pwa-node (js-debug), go, python, php
--- (xdebug), coreclr (netcoredbg), bun (krs bun adapter), krsnvimscript (built in).
M.registry = vim.deepcopy(GENERIC_RUNTIMES)
for _, lang in pairs(require("krs.langs").langs) do
	if lang.launch_runtimes then
		for name, def in pairs(lang.launch_runtimes) do
			M.registry[name] = def
		end
	end
end

-- ============================================================================
-- API
-- ============================================================================

--- Builds the launch context shared by command building and DAP configuration.
---
--- @param profile table Launch profile.
--- @param root string Project root.
--- @return table ctx `{ root, entry, full_entry, is_ts, args, args_str, profile }`
function M.context(profile, root)
	local entry = profile.entry_point or ""
	local rt = profile.runtime or M.default_runtime

	-- Safety fallback for incompatible/legacy entry points (e.g. src/index.ts on a Go profile)
	if rt == "go" and (entry == "" or (entry:match("%.go$") == nil and entry ~= "." and not path.is_file(path.join(root, entry)))) then
		if path.is_file(path.join(root, "main.go")) then
			entry = "main.go"
		elseif path.is_file(path.join(root, "cmd/main.go")) then
			entry = "cmd/main.go"
		elseif path.is_file(path.join(root, "go.mod")) then
			entry = "."
		end
	elseif rt == "python" and (entry == "" or (entry:match("%.py$") == nil and not path.is_file(path.join(root, entry)))) then
		if path.is_file(path.join(root, "main.py")) then
			entry = "main.py"
		elseif path.is_file(path.join(root, "app.py")) then
			entry = "app.py"
		end
	elseif rt == "dotnet" and (entry == "" or (entry:match("%.cs$") == nil and entry:match("%.csproj$") == nil and entry:match("%.dll$") == nil and not path.is_file(path.join(root, entry)))) then
		if path.is_file(path.join(root, "Program.cs")) then
			entry = "Program.cs"
		end
	end

	local args = profile.args or {}
	return {
		profile = profile,
		root = root,
		entry = entry,
		full_entry = path.join(root, entry),
		is_ts = entry:match("%.[cm]?tsx?$") ~= nil,
		args = args,
		args_str = type(args) == "table" and table.concat(args, " ") or tostring(args),
	}
end

--- Looks up a runtime definition, falling back to `custom` for unknown names.
---
--- @param name string|nil Runtime key.
--- @return table definition
function M.get(name)
	return M.registry[name or M.default_runtime] or M.registry.custom
end

--- Builds the shell command that runs a profile in a terminal.
---
--- @param profile table Launch profile.
--- @param root string Project root.
--- @return string|nil cmd Command line, or nil when the runtime executes itself.
--- @return table ctx Launch context, reusable by the caller.
function M.build_command(profile, root)
	local ctx = M.context(profile, root)
	local def = M.get(profile.runtime)

	if def.execute then
		return nil, ctx
	end

	local prefix = type(def.command) == "function" and def.command(ctx) or def.command
	local cmd = prefix ~= "" and (prefix .. " " .. ctx.entry) or ctx.entry
	if ctx.args_str ~= "" then
		cmd = cmd .. " " .. ctx.args_str
	end

	return cmd, ctx
end

--- Builds the nvim-dap configuration for a profile.
---
--- @param profile table Launch profile.
--- @param root string Project root.
--- @return table|nil config nil when the runtime cannot be debugged right now.
function M.build_dap_config(profile, root)
	local ctx = M.context(profile, root)
	local def = M.get(profile.runtime)

	if def.dap then
		return def.dap(profile, root, ctx)
	end
	return require("krs.langs.typescript").js_debug_config(profile, root, ctx)
end

return M
