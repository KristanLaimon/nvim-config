-- ============================================================================
-- docs/krsnvim-testing.lua
-- Comprehensive Testing, Usage Guide, & Feature Demo for `krsnvim.cli` & `krsnvim`.
-- ============================================================================
-- HOW TO RUN THIS SCRIPT IN NEOVIM
--   Method 1: Open this file in Neovim and press `<C-,>` (Control + comma)
--   Method 2: Execute `:KrsRun` or run headlessly: `nvim --headless -l docs/krsnvim-testing.lua`
-- ============================================================================

local krsnvim = require("krsnvim")
local cli = krsnvim.cli
local terminal = krsnvim.terminal

print("\n" .. string.rep("=", 64))
print(" 🚀 KRSNVIM CLI MINI-FRAMEWORK TEST & DEMO SUITE")
print(string.rep("=", 64) .. "\n")

-- ---------------------------------------------------------------------------
-- 1. ASCII ART TITLE GENERATOR
-- ---------------------------------------------------------------------------
print(cli.colorize("--- [1] ASCII ART TITLE GENERATOR ---", cli.colors.cyan))
local banner = cli.ascii_title("KRSNVIM", {
	color = cli.colors.green,
	subtitle = "Next-Gen Neovim Automation & CLI Framework",
})
print(banner .. "\n")

-- ---------------------------------------------------------------------------
-- 2. STYLIZED CONTAINER BOX & DATA TABLES
-- ---------------------------------------------------------------------------
print(cli.colorize("--- [2] BOX CONTAINERS & DATA TABLES ---", cli.colors.yellow))

local info_box = cli.box({
	"Framework: KRSNVIM CLI Mini-Framework v2.0",
	"Terminal Execution: krsnvim.terminal",
	"OS Platform: " .. (terminal.is_windows and "Windows (PowerShell/CMD)" or "Unix/Linux/WSL"),
	"Working Dir: " .. terminal.cwd(),
}, { title = "SYSTEM DIAGNOSTICS", style = "rounded" })

print(info_box .. "\n")

local table_output = cli.table({ "ID", "Module", "Status", "Control Input" }, {
	{ "01", "cli.ascii_title", "ACTIVE", "Single Text String" },
	{ "02", "cli.menu", "ACTIVE", "Vim (j/k) + Arrows + Mouse Click" },
	{ "03", "cli.multi_select", "ACTIVE", "Vim + Arrows + Space + Mouse Click" },
	{ "04", "terminal.exec", "ACTIVE", "Cross-Platform Shell" },
})

print(cli.box(table_output, { title = "CLI COMPONENT MATRIX", style = "double" }) .. "\n")

-- ---------------------------------------------------------------------------
-- 3. ARGUMENT PARSING & HELP TEXT GENERATION
-- ---------------------------------------------------------------------------
print(cli.colorize("--- [3] ARGUMENT PARSER & HELP GENERATOR ---", cli.colors.magenta))

local sample_args = { "--env=production", "--verbose", "--min-depth=3", "deploy" }
local parsed = cli.parse_args(sample_args)

print("Parsed raw flags:")
print("  --env       : " .. tostring(parsed.flags.env))
print("  --verbose   : " .. tostring(parsed.flags.verbose))
print("  --min-depth : " .. tostring(parsed.flags["min-depth"]))
print("  Positional  : " .. table.concat(parsed.positional, ", ") .. "\n")

local help_text = cli.help({
	name = "KRS TEST",
	description = "Automated test harness and CLI runner",
	options = {
		env = "Target deployment environment (development|production)",
		verbose = "Enable detailed logging output",
	},
})
print(help_text .. "\n")

-- ---------------------------------------------------------------------------
-- 4. ANIMATED SPINNER TASK
-- ---------------------------------------------------------------------------
print(cli.colorize("--- [4] SPINNER TASK EXECUTION ---", cli.colors.blue))

local result = cli.spinner("Performing system integrity verification...", function()
	local res = terminal.exec("echo KRSNVIM CLI Engine Active")
	return res.output
end)

print("Task output: " .. result:gsub("%s+$", "") .. "\n")

-- ---------------------------------------------------------------------------
-- 5. INTERACTIVE MENUS (Single Select & Multi-Select Checkbox)
-- ---------------------------------------------------------------------------
print(cli.colorize("--- [5] INTERACTIVE MENU DEMO ---", cli.colors.cyan))

if vim and vim.api and vim.api.nvim_open_win then
	print("Launching floating interactive menu modal with Vim keys (j/k), Arrows (↑/↓), and Mouse click support...\n")

	cli.menu("KRS DEMO", {
		"Run Full Diagnostic Check",
		"Launch Multi-Select Checkbox Demo",
		"Inspect CLI Environment",
		"Exit Demo Suite",
	}, function(choice, idx)
		print(cli.colorize(string.format("Selected Choice #%d: %s", idx, choice), cli.colors.green))

		if idx == 2 then
			vim.schedule(function()
				cli.multi_select("PLUGINS", {
					"LSP IntelliSense",
					"DAP Debugger",
					"Git Center",
					"Command Palette",
					"Pinned Tabs",
				}, function(selected)
					print(cli.colorize("Selected " .. #selected .. " items:", cli.colors.yellow))
					for _, item in ipairs(selected) do
						print("  [x] " .. item)
					end
				end)
			end)
		end
	end)
else
	print("Interactive menu requires Neovim UI. Run inside Neovim with <C-,> to test floating modal menu.")
end
