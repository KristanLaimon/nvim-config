-- ============================================================================
-- 🦊 run_me.lua -- Master CLI Runner for KRSNVIM Scripts (Pure Lua)
-- ============================================================================

local root = vim.fn.stdpath("config")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

-- Explicit krsnvimscript library imports
local cli = require("krs.lib.krsnvim.cli")
local terminal = require("krs.lib.krsnvim.terminal")
local console = require("krs.lib.krsnvim.console")

local schema = {
	name = "run_me",
	description = "Master CLI to run KRSNVIM setup, tests, syntax check, and utility scripts.",
	options = {
		["tests"] = "Run project test suite (run_tests)",
		["syntax"] = "Run syntax check on all Lua files (run_sintaxcheck)",
		["setup"] = "Run dependency setup script (setup.ps1 / setup.sh)",
		["setup-ps"] = "Configure Windows Terminal keymaps (setup-powershell.ps1)",
		["unsetup-ps"] = "Restore Windows Terminal keymaps (unsetup-powershell.ps1)",
		["example"] = "Run example script (example.krsnvim)",
		["lint"] = "Format & lint Lua files (stylua + luacheck)",
		["all"] = "Run all checks: lint, syntax, tests",
		["help"] = "Show this CLI help screen",
	},
}

--- Run a dofile'd script that may call os.exit() without killing nvim.
--- Temporarily replaces os.exit with a throwing proxy, then restores it.
local function safe_dofile(path)
	local real_exit = os.exit
	local exit_code = 0
	local intercepted = false
	os.exit = function(code)
		exit_code = code or 0
		intercepted = true
		error("__EXIT__", 2)
	end
	local ok, err = pcall(dofile, path)
	os.exit = real_exit
	if not ok and not intercepted then
		error(err, 0)
	end
	return exit_code
end

local function run_tests()
	console.log("[run_me] Running Test Suite...")
	local runner = dofile(root .. "/tests/run.lua")
	local code = runner.run(root, nil)
	if code ~= 0 then
		print(cli.colorize("[run_me] Tests failed (exit " .. code .. ").", cli.colors.red))
	end
	return code == 0
end

local function run_syntax()
	console.log("[run_me] Running Syntax Check...")
	local code = safe_dofile(root .. "/tests/syntax_check.lua")
	if code ~= 0 then
		print(cli.colorize("[run_me] Syntax check found errors.", cli.colors.red))
	end
	return code == 0
end

local function run_setup()
	console.log("[run_me] Running Setup Dependencies...")
	if vim.fn.has("win32") == 1 then
		terminal.run("powershell.exe -ExecutionPolicy Bypass -File " .. vim.fn.shellescape(root .. "/scripts/setup.ps1"))
	else
		terminal.run("bash " .. vim.fn.shellescape(root .. "/scripts/setup.sh"))
	end
	return true
end

local function run_setup_ps()
	console.log("[run_me] Setting up Windows Terminal Keymaps...")
	terminal.run(
		"powershell.exe -ExecutionPolicy Bypass -File " .. vim.fn.shellescape(root .. "/scripts/setup-powershell.ps1")
	)
	return true
end

local function run_unsetup_ps()
	console.log("[run_me] Restoring Windows Terminal Keymaps...")
	terminal.run(
		"powershell.exe -ExecutionPolicy Bypass -File " .. vim.fn.shellescape(root .. "/scripts/unsetup-powershell.ps1")
	)
	return true
end

local function run_lint()
	if vim.fn.executable("stylua") ~= 1 then
		print(cli.colorize("Error: 'stylua' is not installed or not in your PATH.", cli.colors.red))
		print("Please install StyLua to format the code (e.g., via 'cargo install stylua' or downloading from GitHub).")
		return false
	end
	if vim.fn.executable("luacheck") ~= 1 then
		print(cli.colorize("Error: 'luacheck' is not installed or not in your PATH.", cli.colors.red))
		print("Please install Luacheck to lint the code (e.g., via 'luarocks install luacheck').")
		return false
	end

	console.log("[run_me] Formatting Lua files with StyLua...")
	local fmt_ok = os.execute("stylua " .. root)
	console.log("[run_me] Linting Lua files with Luacheck...")
	local lint_ok = os.execute("luacheck " .. root)
	if fmt_ok ~= true and fmt_ok ~= 0 then
		print(cli.colorize("[run_me] StyLua failed.", cli.colors.red))
		return false
	end
	if lint_ok ~= true and lint_ok ~= 0 then
		print(cli.colorize("[run_me] Luacheck found issues.", cli.colors.red))
		return false
	end
	print(cli.colorize("[run_me] All checks passed!", cli.colors.green))
	return true
end

local function run_example()
	console.log("[run_me] Running Example Script...")
	safe_dofile(root .. "/scripts/example.krsnvim")
	return true
end

local function run_all()
	local steps = {
		{ name = "Lint & Format", fn = run_lint },
		{ name = "Syntax Check", fn = run_syntax },
		{ name = "Test Suite", fn = run_tests },
	}

	local all_ok = true
	for _, step in ipairs(steps) do
		console.log("\n[run_me] === " .. step.name .. " ===")
		if not step.fn() then
			all_ok = false
		end
	end

	if all_ok then
		print(cli.colorize("\n[run_me] All checks passed!", cli.colors.green))
	else
		print(cli.colorize("\n[run_me] Some checks failed.", cli.colors.red))
	end
	return all_ok
end

local function show_menu()
	local options = {
		"Run Test Suite (tests/run.lua)",
		"Run Syntax Check (tests/syntax_check.lua)",
		"Run Setup Dependencies (setup.ps1 / setup.sh)",
		"Setup Windows Terminal Keymaps (setup-powershell.ps1)",
		"Unsetup Windows Terminal Keymaps (unsetup-powershell.ps1)",
		"Run Example Script (scripts/example.krsnvim)",
		"Lint & Format (stylua + luacheck)",
		"Run All (lint + syntax + tests)",
		"Exit",
	}

	cli.menu({ title = "KRSNVIM", subtitle = "Master CLI Script Runner", items = options }, function(choice, idx)
		if idx == 1 then
			run_tests()
		elseif idx == 2 then
			run_syntax()
		elseif idx == 3 then
			run_setup()
		elseif idx == 4 then
			run_setup_ps()
		elseif idx == 5 then
			run_unsetup_ps()
		elseif idx == 6 then
			run_example()
		elseif idx == 7 then
			run_lint()
		elseif idx == 8 then
			run_all()
		else
			print(cli.colorize("Exiting run_me CLI.", cli.colors.yellow))
		end
	end)
end

-- Parse CLI Flags
local raw_args = arg or {}
local parsed = cli.parse_args(raw_args, schema)

if parsed.flags.help or parsed.flags.h then
	print(cli.help(schema))
elseif parsed.flags.tests or parsed.flags.t then
	if not run_tests() then
		os.exit(1)
	end
elseif parsed.flags.syntax or parsed.flags.s then
	if not run_syntax() then
		os.exit(1)
	end
elseif parsed.flags.setup then
	run_setup()
elseif parsed.flags["setup-ps"] then
	run_setup_ps()
elseif parsed.flags["unsetup-ps"] then
	run_unsetup_ps()
elseif parsed.flags.example or parsed.flags.e then
	run_example()
elseif parsed.flags.lint or parsed.flags.l then
	if not run_lint() then
		os.exit(1)
	end
elseif parsed.flags.all or parsed.flags.a then
	if not run_all() then
		os.exit(1)
	end
else
	show_menu()
end
