-- ============================================================================
-- KRS AUTOMATED INCREMENTAL INSTALLER & SYSTEM SETUP
-- ============================================================================
-- Standalone bootstrap installer with zero external dependencies.
--
-- WHAT IT DOES:
--   1. Stage 1 (Essentials): Ensures lazy.nvim, core tools (git, gcc, rg, fd) exist.
--   2. Stage 2 (Heavy Setup): Checks & installs Mason LSPs, Treesitter parsers,
--      and toolchain runtimes with a live animated floating UI modal & progress bar.
--   3. Persistence: Saves state to stdpath("data")/krs_setup_completed.json once
--      100% complete so subsequent normal startups skip full scans for maximum speed.
--   4. Rerunnable & Incremental: Only installs missing or corrupted components.
--   5. Live Installation UI: Displays real-time download activity logs, current item,
--      already installed items, and next queued items so you know it's not frozen.
-- ============================================================================

local M = {}

--- Persistent setup state file in Neovim data path.
local function get_state_path()
	return vim.fn.stdpath("data") .. "/krs_setup_completed.json"
end

--- Generic, language-agnostic tools with no owning lua/krs/langs/<lang> module
--- (TOML/YAML/XML have no per-language buffer-default module -- see
--- lua/krs/langs/init.lua for where per-language tool metadata lives instead).
--- @class KrsTool
--- @field mason string Mason package directory/install name.
--- @field type "lsp"|"formatter"|"dap"
--- @field cmd string CLI binary used to detect an already-installed tool.
--- @field lang? string Human-readable language label (lsp/dap tools).
--- @field name? string Human-readable tool label (formatter tools).
local GENERIC_TOOLS = {
	taplo = { mason = "taplo", lang = "TOML", type = "lsp", cmd = "taplo" },
	yamlls = { mason = "yaml-language-server", lang = "YAML", type = "lsp", cmd = "yaml-language-server" },
	lemminx = { mason = "lemminx", lang = "XML", type = "lsp", cmd = "lemminx" },
}
local GENERIC_MASON_ORDER = { "taplo", "yamlls", "lemminx" }

--- Every LSP/formatter tool this config manages, merged from each language module's
--- `M.mason` (see lua/krs/langs/<lang>/init.lua) plus the generic tools above. Add,
--- remove, or swap a tool by editing its owning language module, NOT here.
M.tools = vim.deepcopy(GENERIC_TOOLS)

--- Expected Mason LSP & Tool packages, in install/display order. Built by
--- concatenating each language module's `M.mason_order` (its Mason install
--- sequence) with the generic tools' order. Any tool disabled in its
--- lsp_config (e.g. `buf_ls`, `csharp_ls`) is intentionally excluded from its
--- language's `mason_order`, so it is never auto-installed.
M.mason_packages = {}
do
	local langs = require("krs.langs").langs
	for _, lang in pairs(langs) do
		if lang.mason then
			for tool_name, info in pairs(lang.mason) do
				M.tools[tool_name] = info
			end
		end
		if lang.mason_order then
			vim.list_extend(M.mason_packages, lang.mason_order)
		end
	end
	vim.list_extend(M.mason_packages, GENERIC_MASON_ORDER)
end

--- Resolves an lspconfig or tool name to its actual Mason package directory name.
--- @param pkg string
--- @return string
function M.get_mason_package_name(pkg)
	local ok, mappings = pcall(require, "mason-lspconfig.mappings.server")
	if ok and mappings.lspconfig_to_package and mappings.lspconfig_to_package[pkg] then
		return mappings.lspconfig_to_package[pkg]
	end
	local tool = M.tools[pkg]
	return (tool and tool.mason) or pkg
end

--- Expected essential CLI tools.
M.essential_tools = {
	{ cmd = "git", name = "Git version control" },
	{ cmd = "gcc", name = "C/C++ Compiler (gcc/clang)", alt = "clang" },
	{ cmd = "rg", name = "Ripgrep (rg)" },
	{ cmd = "fd", name = "fd / fdfind", alt = "fdfind" },
}

--- Expected heavy runtime tools.
M.heavy_runtimes = {
	{ cmd = "node", name = "Node.js runtime" },
	{ cmd = "bun", name = "Bun runtime" },
	{ cmd = "go", name = "Go programming language" },
	{ cmd = "dotnet", name = ".NET SDK" },
}

--- Full health-check catalogue, grouped by category. Single source of truth
--- for both the compact bundle-manager footer (flattened, see
--- `M.cli_healthcheck` below) and the standalone `:KrsHealthCheck` page.
--- Each tool: `{ cmd, name, alt?, note? }` -- `note` explains which plugin
--- or feature needs it, shown only on the full health-check page.
M.health_categories = {
	{
		label = "🧱 Essential Tools",
		tools = {
			{ cmd = "git", name = "Git version control", note = "version control, lazy.nvim plugin installs" },
			{ cmd = "gcc", name = "C/C++ Compiler (gcc/clang)", alt = "clang", note = "compiles Treesitter parsers" },
			{ cmd = "rg", name = "Ripgrep", note = "Telescope live-grep & find-files" },
			{ cmd = "fd", name = "fd", alt = "fdfind", note = "Telescope file finder" },
		},
	},
	{
		label = "🚀 Language Runtimes",
		tools = {
			{ cmd = "node", name = "Node.js runtime", note = "JS/TS, Angular, web, most Mason LSPs" },
			{ cmd = "bun", name = "Bun runtime", note = "faster JS package installs/DAP" },
			{ cmd = "go", name = "Go programming language" },
			{ cmd = "dotnet", name = ".NET SDK", note = "C# LSP, dotnet global tools" },
			{ cmd = "python", name = "Python", alt = "python3" },
			{ cmd = "php", name = "PHP" },
			{ cmd = "composer", name = "Composer", note = "PHP package manager" },
			{ cmd = "ruby", name = "Ruby", note = "Ruby toolchain" },
			{ cmd = "ghc", name = "GHC", note = "Haskell compiler" },
		},
	},
	{
		label = "🔌 External Plugin Dependencies",
		tools = {
			{ cmd = "curl", name = "curl", note = "lua/plugins/krs/doc_manager.lua DevDocs downloader" },
			{ cmd = "npm", name = "npm", note = "lua/plugins/krs/type_injector.lua schema package installer" },
			{
				cmd = "pnpm",
				name = "pnpm",
				note = "lua/plugins/krs/dev_server.lua alt JS runner (optional, only needed for pnpm-lock.yaml projects)",
			},
			{
				cmd = "yarn",
				name = "yarn",
				note = "lua/plugins/krs/dev_server.lua alt JS runner (optional, only needed for yarn.lock projects)",
			},
		},
	},
}

--- Flattened `{cmd, alt}` view of `M.health_categories`, for the compact
--- bundle-manager footer's single-line pass/fail row.
M.cli_healthcheck = {}
for _, category in ipairs(M.health_categories) do
	for _, tool in ipairs(category.tools) do
		table.insert(M.cli_healthcheck, { cmd = tool.cmd, alt = tool.alt })
	end
end

-------------------------------------------------------------------------------
-- UI STATE & LIVE ACTIVITY LOGGING
-------------------------------------------------------------------------------

local ui_buf = nil
local ui_win = nil
local live_logs = {}

local function add_log(msg)
	local clean_msg = tostring(msg):gsub("[\r\n]+", " ")
	table.insert(live_logs, string.format("[%s] %s", os.date("%H:%M:%S"), clean_msg))
	if #live_logs > 12 then
		table.remove(live_logs, 1)
	end
end

--- Loads completion state from disk.
--- @return table state { completed = boolean, timestamp = string|nil }
function M.load_state()
	local path = get_state_path()
	local file = io.open(path, "r")
	if not file then
		return { completed = false }
	end
	local content = file:read("*a")
	file:close()
	if not content or content == "" then
		return { completed = false }
	end
	local ok, decoded = pcall(vim.json.decode, content)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return { completed = false }
end

--- Saves completion state to disk.
--- @param completed boolean
function M.save_state(completed)
	local path = get_state_path()
	local state = {
		completed = completed == true,
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		version = "1.0",
	}
	local ok, json = pcall(vim.json.encode, state)
	if ok and json then
		local file = io.open(path, "w")
		if file then
			file:write(json)
			file:close()
		end
	end
end

--- Resets completion state file to force a full setup re-validation.
function M.reset_state()
	local path = get_state_path()
	pcall(os.remove, path)
	vim.notify("🔄 Setup state reset. Full system setup re-validation enabled.", vim.log.levels.INFO, {
		title = "KRS System Setup",
	})
end

--- Renders a Unicode progress bar.
--- @param percentage number 0 to 100
--- @param width number|nil
--- @return string
function M.render_bar(percentage, width)
	width = width or 12
	local pct = math.max(0, math.min(100, percentage))
	local filled = math.floor((pct / 100) * width)
	local empty = math.max(0, width - filled)
	return string.rep("█", filled) .. string.rep("░", empty)
end

--- Updates the content of the Live Setup Floating Window UI.
--- @param current_active string|nil Component currently downloading/installing
--- @param completed_list string[] Components already downloaded/installed
--- @param queued_list string[] Components queued for installation
--- @param percentage number Progress percentage
local function update_ui_buffer(current_active, completed_list, queued_list, percentage)
	if not ui_buf or not vim.api.nvim_buf_is_valid(ui_buf) then
		return
	end

	local width = 74
	local pct = math.max(0, math.min(100, math.floor(percentage + 0.5)))
	local bar = M.render_bar(pct, 20)
	local lines = {}

	table.insert(lines, "  🦊 KRS AUTOMATED SYSTEM SETUP & INSTALLER")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(lines, string.format("  Overall Progress: [%s] %d%%", bar, pct))
	table.insert(lines, "")

	if pct >= 100 then
		table.insert(lines, "  🎉 STATUS: 100% COMPLETE! All LSPs, plugins & tools are installed.")
	elseif current_active then
		table.insert(lines, string.format("  ⏳ CURRENTLY DOWNLOADING / INSTALLING: %s", current_active))
	else
		table.insert(lines, "  ℹ️ STATUS: Ready to start incremental installation.")
	end

	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(lines, string.format("  ✓ ALREADY INSTALLED (%d items):", #completed_list))
	if #completed_list == 0 then
		table.insert(lines, "    (None yet)")
	else
		local summary = {}
		for i, item in ipairs(completed_list) do
			table.insert(summary, item)
			if #summary >= 5 or i == #completed_list then
				table.insert(lines, "    • " .. table.concat(summary, ", "))
				summary = {}
			end
		end
	end

	table.insert(lines, "")
	table.insert(lines, string.format("  📦 NEXT TO DOWNLOAD / QUEUED (%d items):", #queued_list))
	if #queued_list == 0 then
		table.insert(lines, "    (None remaining)")
	else
		local queued_summary = {}
		for i, item in ipairs(queued_list) do
			table.insert(queued_summary, item)
			if #queued_summary >= 5 or i == #queued_list then
				table.insert(lines, "    • " .. table.concat(queued_summary, ", "))
				queued_summary = {}
			end
		end
	end

	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(lines, "  📜 LIVE ACTIVITY LOG (Shows real-time download activity):")
	if #live_logs == 0 then
		table.insert(lines, "    Waiting for activity log...")
	else
		for _, log_msg in ipairs(live_logs) do
			table.insert(lines, "    " .. log_msg)
		end
	end

	table.insert(lines, "")
	table.insert(lines, "  [Press q or Esc to hide modal window — installation continues in background]")

	pcall(function()
		vim.bo[ui_buf].modifiable = true
		vim.api.nvim_buf_set_lines(ui_buf, 0, -1, false, lines)
		vim.bo[ui_buf].modifiable = false
	end)
end

--- Opens or focuses the Live Installation Floating Modal Window.
function M.open_ui()
	local ui = require("krs.core.ui")

	if ui_win and vim.api.nvim_win_is_valid(ui_win) then
		vim.api.nvim_set_current_win(ui_win)
		return
	end

	local scan = M.scan_status()
	local installed_list = scan.installed_items

	local cols = vim.o.columns or 80
	local lines_cnt = vim.o.lines or 24
	local width = math.max(38, math.min(76, cols - 4))
	local height = math.max(14, math.min(24, lines_cnt - 4))

	ui_buf, ui_win = ui.float({
		width = width,
		height = height,
		title = " 🦊 KRS System Setup & Live Installer ",
		focusable = true,
		modifiable = false,
	})

	ui.close_on_keys(ui_buf, ui_win)
	update_ui_buffer(nil, installed_list, scan.missing_lsps, scan.percentage)
end

-------------------------------------------------------------------------------
-- BUNDLE MANAGER UI STATE
-------------------------------------------------------------------------------

local lang_buf = nil
local lang_win = nil
local lang_items = {}
local lang_line_map = {}

local health_buf = nil
local health_win = nil

-------------------------------------------------------------------------------
-- ROOT / SUDO SYSTEM SETUP EXECUTION WITH UI PASSWORD PROMPT
-------------------------------------------------------------------------------

--- Cached sudo password in-memory for the current Neovim session.
M.cached_sudo_pass = M.cached_sudo_pass or nil

--- Checks if running inside Termux / Android / Mobile.
--- @return boolean
function M.is_mobile_or_termux()
	return vim.env.TERMUX_VERSION ~= nil
		or vim.fn.isdirectory("/data/data/com.termux") == 1
		or (
			vim.fn.filereadable("/proc/version") == 1
			and (vim.fn.readfile("/proc/version")[1] or ""):lower():match("android") ~= nil
		)
end

--- Checks if running as a non-root user on Linux/macOS/Termux requiring sudo password authentication.
--- @return boolean
function M.requires_sudo()
	if vim.fn.has("win32") == 1 then
		return false
	end
	local getuid_ok, uid = pcall(function()
		return (vim.uv or vim.loop).getuid()
	end)
	if getuid_ok and uid == 0 then
		return false
	end
	return vim.fn.executable("sudo") == 1 or M.is_mobile_or_termux()
end

--- Obtains sudo password via UI prompt if non-root on Linux/Termux/macOS, or re-uses cached password for session.
--- @param callback function(sudo_pass: string|nil)
function M.ensure_sudo_pass(callback)
	if not M.requires_sudo() then
		callback(nil)
		return
	end

	if M.cached_sudo_pass and M.cached_sudo_pass ~= "" then
		callback(M.cached_sudo_pass)
		return
	end

	local user_name = vim.env.USER or "user"
	vim.ui.input({
		prompt = string.format("🔑 Root/Sudo Password for user '%s': ", user_name),
	}, function(pass)
		if not pass or pass == "" then
			vim.notify("Cancelled installation: Password is required for sudo execution.", vim.log.levels.WARN, {
				title = "Root Password Required",
			})
			callback(nil)
			return
		end
		M.cached_sudo_pass = pass
		callback(pass)
	end)
end

--- Prompts user for root/sudo password in UI prompt if non-root, then executes setup.sh.
function M.run_system_setup_interactive()
	M.ensure_sudo_pass(function(pass)
		M.run_setup_script(pass)
	end)
end

--- Executes setup.sh (or setup.ps1) with live activity modal feed and optional sudo password.
--- @param sudo_pass string|nil
function M.run_setup_script(sudo_pass)
	M.open_ui()
	add_log("Starting system dependency setup via setup script...")

	local script_path = vim.fn.stdpath("config") .. "/scripts/setup.sh"
	local cmd = {}

	if vim.fn.has("win32") == 1 then
		script_path = vim.fn.stdpath("config") .. "/scripts/setup.ps1"
		cmd = { "powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path }
	else
		if sudo_pass and sudo_pass ~= "" then
			cmd = { script_path, "--sudo-pass", sudo_pass, "--all" }
		else
			cmd = { script_path, "--all" }
		end
	end

	add_log("Running system installer script...")

	local scan_before = M.scan_status()
	update_ui_buffer("Running system package manager...", scan_before.installed_items, scan_before.missing_lsps, 30)

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = vim.schedule_wrap(function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						local clean = line:gsub("\27%[[0-9;]*[mK]", ""):gsub("^%s*", "")
						if clean ~= "" and not clean:lower():match("password") then
							add_log(clean)
						end
					end
				end
			end
		end),
		on_stderr = vim.schedule_wrap(function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						local clean = line:gsub("\27%[[0-9;]*[mK]", ""):gsub("^%s*", "")
						if clean ~= "" and not clean:lower():match("password") then
							add_log("⚠️ " .. clean)
						end
					end
				end
			end
		end),
		on_exit = vim.schedule_wrap(function(_, exit_code, _)
			local scan_after = M.scan_status()
			if exit_code == 0 then
				add_log("🎉 System setup script completed successfully!")
				M.finish_setup(scan_after.installed_items)
			else
				add_log(string.format("❌ System setup failed with exit code %d. Verify root/sudo password.", exit_code))
				vim.notify("❌ System setup script failed. Please verify your root/sudo password.", vim.log.levels.ERROR, {
					title = "System Setup Error",
				})
			end
		end),
	})
end

--- Scans installed state of all system components.
--- @return table report
function M.scan_status()
	local report = {
		essentials_ok = true,
		installed_count = 0,
		total_count = 0,
		percentage = 0,
		missing_essentials = {},
		missing_lsps = {},
		missing_runtimes = {},
		installed_items = {},
		lazy_installed = false,
	}

	-- 1. Check lazy.nvim
	local lazy_path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
	local stat = (vim.uv or vim.loop).fs_stat(lazy_path)
	report.lazy_installed = (stat ~= nil)
	report.total_count = report.total_count + 1
	if report.lazy_installed then
		report.installed_count = report.installed_count + 1
		table.insert(report.installed_items, "lazy.nvim")
	else
		report.essentials_ok = false
		table.insert(report.missing_essentials, "lazy.nvim plugin manager")
	end

	-- 2. Check essential CLI tools
	for _, tool in ipairs(M.essential_tools) do
		report.total_count = report.total_count + 1
		local exists = (vim.fn.executable(tool.cmd) == 1) or (tool.alt and vim.fn.executable(tool.alt) == 1)
		if exists then
			report.installed_count = report.installed_count + 1
			table.insert(report.installed_items, tool.cmd)
		else
			report.essentials_ok = false
			table.insert(report.missing_essentials, tool.name)
		end
	end

	-- 3. Check heavy CLI runtimes
	for _, rt in ipairs(M.heavy_runtimes) do
		report.total_count = report.total_count + 1
		if vim.fn.executable(rt.cmd) == 1 then
			report.installed_count = report.installed_count + 1
			table.insert(report.installed_items, rt.cmd)
		else
			table.insert(report.missing_runtimes, rt.name)
		end
	end

	report.missing_languages = {}
	report.missing_formatters = {}
	local seen_langs = {}
	local seen_fmts = {}

	-- 4. Check Mason LSP & tool packages or system executables
	local mason_share = vim.fn.stdpath("data") .. "/mason/packages"
	for _, pkg in ipairs(M.mason_packages) do
		report.total_count = report.total_count + 1
		local mason_pkg = M.get_mason_package_name(pkg)
		local pkg_dir = mason_share .. "/" .. mason_pkg
		local pkg_stat = (vim.uv or vim.loop).fs_stat(pkg_dir)

		local info = M.tools[pkg] or {}
		local bin_cmd = info.cmd or pkg
		local is_installed = (pkg_stat and pkg_stat.type == "directory") or (vim.fn.executable(bin_cmd) == 1)

		if is_installed then
			report.installed_count = report.installed_count + 1
			table.insert(report.installed_items, pkg)
		else
			table.insert(report.missing_lsps, pkg)
			if info.type == "lsp" and info.lang and not seen_langs[info.lang] then
				seen_langs[info.lang] = true
				table.insert(report.missing_languages, info.lang)
			elseif info.type == "formatter" and info.name and not seen_fmts[info.name] then
				seen_fmts[info.name] = true
				table.insert(report.missing_formatters, info.name)
			end
		end
	end

	report.percentage = math.floor(((report.installed_count / math.max(1, report.total_count)) * 100) + 0.5)
	if report.percentage >= 100 then
		M.save_state(true)
	end
	return report
end

--- Displays detailed setup status report toast.
function M.show_status()
	M.open_ui()
end

--- Renders the full `:KrsHealthCheck` page: every CLI in `M.health_categories`
--- plus editor-core plugin manager checks, grouped by category with a pass
--- count per section and an overall summary at the bottom.
local function render_health_check_buffer()
	if not health_buf or not vim.api.nvim_buf_is_valid(health_buf) then
		return
	end

	local width = (health_win and vim.api.nvim_win_is_valid(health_win)) and vim.api.nvim_win_get_width(health_win) or 78
	local lines = {}

	table.insert(lines, "  ==========================================================================")
	table.insert(lines, "   🩺 KRS HEALTH CHECK -- EVERYTHING NEEDED FOR THIS CONFIG TO WORK 100%")
	table.insert(lines, "  ==========================================================================")
	table.insert(lines, "")

	local total_found, total_count = 0, 0

	-- Editor core: lazy.nvim itself, Mason.
	table.insert(lines, "  📦 Editor Core")
	local lazy_installed = (vim.uv or vim.loop).fs_stat(vim.fn.stdpath("data") .. "/lazy/lazy.nvim") ~= nil
	local mason_ok = pcall(require, "mason")
	for _, row in ipairs({
		{ "lazy.nvim plugin manager", lazy_installed },
		{ "mason.nvim (LSP/tool installer)", mason_ok },
	}) do
		total_count = total_count + 1
		if row[2] then
			total_found = total_found + 1
		end
		table.insert(lines, string.format("     %s %s", row[2] and "✅" or "❌", row[1]))
	end
	table.insert(lines, "")

	for _, category in ipairs(M.health_categories) do
		local found_n, total_n = 0, 0
		local rows = {}
		for _, tool in ipairs(category.tools) do
			local found = vim.fn.executable(tool.cmd) == 1 or (tool.alt and vim.fn.executable(tool.alt) == 1)
			total_n = total_n + 1
			if found then
				found_n = found_n + 1
			end
			local note = tool.note and ("  -- " .. tool.note) or ""
			table.insert(
				rows,
				string.format("     %s %-14s %s", found and "✅" or "❌", tool.cmd, (tool.name or "") .. note)
			)
		end
		total_found = total_found + found_n
		total_count = total_count + total_n

		table.insert(lines, string.format("  %s (%d/%d)", category.label, found_n, total_n))
		vim.list_extend(lines, rows)
		table.insert(lines, "")
	end

	table.insert(lines, "  " .. string.rep("─", width - 4))
	local pct = math.floor((total_found / math.max(1, total_count)) * 100 + 0.5)
	table.insert(lines, string.format("  📊 OVERALL: %d/%d found (%d%%)", total_found, total_count, pct))
	table.insert(lines, "  [r] Refresh   |   [q/Esc] Close")

	pcall(function()
		vim.bo[health_buf].modifiable = true
		vim.api.nvim_buf_set_lines(health_buf, 0, -1, false, lines)
		vim.bo[health_buf].modifiable = false
	end)
end

--- Opens the full `:KrsHealthCheck` page.
function M.open_health_check()
	local ui = require("krs.core.ui")

	if health_win and vim.api.nvim_win_is_valid(health_win) then
		vim.api.nvim_set_current_win(health_win)
		return
	end

	local cols = vim.o.columns or 80
	local lines_cnt = vim.o.lines or 24
	local width = math.max(50, math.min(80, cols - 4))
	local height = math.max(16, math.min(32, lines_cnt - 4))

	health_buf, health_win = ui.float({
		width = width,
		height = height,
		title = " 🩺 KRS Health Check ",
		focusable = true,
		modifiable = false,
	})

	ui.close_on_keys(health_buf, health_win)
	render_health_check_buffer()

	vim.keymap.set("n", "r", render_health_check_buffer, { buffer = health_buf, silent = true, noremap = true })
end

--- Performs automated incremental installation (Stage 1 Essentials + Stage 2 Heavy LSPs).
--- Displays real-time progress toast bar & live modal UI feed.
function M.install_all()
	M.ensure_sudo_pass(function(sudo_pass)
		M.open_ui()
		add_log("Starting automated incremental system setup...")

		local scan = M.scan_status()
		local installed_list = scan.installed_items
		local missing_lsps = scan.missing_lsps
		local missing_count = #missing_lsps

		update_ui_buffer("Syncing lazy.nvim plugins...", installed_list, missing_lsps, math.max(15, scan.percentage))

		vim.schedule(function()
			-- Step 1: Ensure Lazy plugins and Mason are loaded (15% -> 25%)
			add_log("Ensuring plugin manager and Mason packages are initialized...")
			local has_lazy, lazy = pcall(require, "lazy")
			if has_lazy then
				pcall(function()
					lazy.load({ plugins = { "mason.nvim", "mason-lspconfig.nvim", "nvim-treesitter" } })
				end)
			end

			pcall(function()
				require("mason").setup()
			end)

			-- Step 2: Mason LSPs & Tools (25% - 75%)
			if missing_count > 0 then
				add_log(string.format("Found %d missing Mason LSP packages to download...", missing_count))
				add_log("Triggering Mason package installer...")

				local missing_mason_names = {}
				for _, item in ipairs(missing_lsps) do
					table.insert(missing_mason_names, M.get_mason_package_name(item))
				end

				-- Trigger Mason batch installer
				pcall(vim.cmd, "MasonInstall " .. table.concat(missing_mason_names, " "))

				-- Track progress by checking installed directories on disk periodically
				local mason_share = vim.fn.stdpath("data") .. "/mason/packages"
				local start_time = (vim.uv or vim.loop).now()
				local max_wait_ms = 90000 -- 90 second maximum safety timeout
				local timer = (vim.uv or vim.loop).new_timer()

				timer:start(
					500,
					500,
					vim.schedule_wrap(function()
						local scan_now = M.scan_status()
						local remaining_queued = scan_now.missing_lsps

						local active_pkg = remaining_queued[1] or "Treesitter & final validation"
						update_ui_buffer(active_pkg, scan_now.installed_items, remaining_queued, scan_now.percentage)

						local elapsed = (vim.uv or vim.loop).now() - start_time
						if #remaining_queued == 0 or elapsed >= max_wait_ms then
							timer:stop()
							timer:close()
							if elapsed >= max_wait_ms and #remaining_queued > 0 then
								add_log("⌛ Installation timeout reached. Remaining packages will finish in background.")
							end
							M.finish_setup(scan_now.installed_items)
						end
					end)
				)
			else
				add_log("All Mason LSP packages are already installed.")
				M.finish_setup(installed_list)
			end
		end)
	end)
end

--- Finalizes setup execution and persists state.
--- @param installed_list string[] List of installed components
function M.finish_setup(installed_list)
	M.save_state(true)
	local scan = M.scan_status()

	if scan.percentage >= 100 then
		add_log("🎉 SETUP 100% COMPLETE! Saved completion state flag.")
		update_ui_buffer(nil, scan.installed_items, {}, 100)

		vim.notify("🎉 KRS Setup 100% Complete! All LSPs, formatters & tools are installed.", vim.log.levels.INFO, {
			title = "KRS System Setup",
		})
		return
	end

	add_log("Updating Treesitter parsers & validating system...")
	update_ui_buffer("Updating Treesitter parsers...", installed_list, {}, 85)

	vim.defer_fn(function()
		pcall(vim.cmd, "TSUpdateSync")
		M.save_state(true)
		add_log("🎉 SETUP 100% COMPLETE! Saved completion flag.")
		update_ui_buffer(nil, installed_list, {}, 100)

		vim.notify("🎉 KRS Setup 100% Complete! All LSPs, formatters & tools are installed.", vim.log.levels.INFO, {
			title = "KRS System Setup",
		})
	end, 500)
end

--- Internal execution for Google Antigravity CLI installation.
--- @param sudo_pass string|nil
function M.run_install_agy(sudo_pass)
	M.open_ui()
	add_log("Starting installation of Google Antigravity CLI (agy)...")

	local cmd = {}
	if vim.fn.has("win32") == 1 then
		cmd = {
			"powershell.exe",
			"-ExecutionPolicy",
			"Bypass",
			"-Command",
			"irm https://antigravity.google/cli/install.ps1 | iex",
		}
	else
		if sudo_pass and sudo_pass ~= "" then
			cmd = {
				"bash",
				"-c",
				string.format(
					"echo %s | sudo -S bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'",
					vim.fn.shellescape(sudo_pass)
				),
			}
		else
			cmd = { "bash", "-c", "curl -fsSL https://antigravity.google/cli/install.sh | bash" }
		end
	end

	local scan = M.scan_status()
	update_ui_buffer(
		"Downloading Google Antigravity CLI (agy)...",
		scan.installed_items,
		{ "google-antigravity-cli" },
		40
	)

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = vim.schedule_wrap(function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						local clean = line:gsub("\27%[[0-9;]*[mK]", ""):gsub("^%s*", "")
						if
							clean ~= ""
							and not clean:lower():match("password")
							and not (sudo_pass and clean:find(sudo_pass, 1, true))
						then
							add_log(clean)
						end
					end
				end
			end
		end),
		on_stderr = vim.schedule_wrap(function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						local clean = line:gsub("\27%[[0-9;]*[mK]", ""):gsub("^%s*", "")
						if
							clean ~= ""
							and not clean:lower():match("password")
							and not (sudo_pass and clean:find(sudo_pass, 1, true))
						then
							add_log("⚠️ " .. clean)
						end
					end
				end
			end
		end),
		on_exit = vim.schedule_wrap(function(_, exit_code, _)
			if exit_code == 0 then
				add_log("🎉 Google Antigravity CLI (agy) installed successfully!")
				update_ui_buffer(nil, M.scan_status().installed_items, {}, 100)
				vim.notify(
					"🎉 Google Antigravity CLI (agy) installed successfully! Run 'agy' in terminal to start.",
					vim.log.levels.INFO,
					{
						title = "Google Antigravity CLI",
					}
				)
			else
				add_log(string.format("❌ Google Antigravity CLI installation failed with exit code %d.", exit_code))
				vim.notify(
					string.format("❌ Google Antigravity CLI installation failed (exit code %d).", exit_code),
					vim.log.levels.ERROR,
					{
						title = "Installation Failed",
					}
				)
			end
		end),
	})
end

--- Installs Google Antigravity CLI (`agy`) cross-platform using official oneliner scripts.
--- Prompts for root/sudo password if non-root on Linux/macOS/Termux.
function M.install_agy()
	M.ensure_sudo_pass(function(pass)
		M.run_install_agy(pass)
	end)
end

--- Internal execution for Claude Code CLI installation.
--- @param sudo_pass string|nil
function M.run_install_claude(sudo_pass)
	M.open_ui()
	add_log("Starting installation of Claude Code CLI (claude)...")

	local cmd = {}
	if vim.fn.has("win32") == 1 then
		cmd = { "powershell.exe", "-ExecutionPolicy", "Bypass", "-Command", "irm https://claude.ai/install.ps1 | iex" }
	else
		if sudo_pass and sudo_pass ~= "" then
			cmd = {
				"bash",
				"-c",
				string.format(
					"echo %s | sudo -S bash -c 'curl -fsSL https://claude.ai/install.sh | bash || npm install -g @anthropic-ai/claude-code'",
					vim.fn.shellescape(sudo_pass)
				),
			}
		else
			cmd =
				{ "bash", "-c", "curl -fsSL https://claude.ai/install.sh | bash || npm install -g @anthropic-ai/claude-code" }
		end
	end

	local scan = M.scan_status()
	update_ui_buffer("Downloading Claude Code CLI (claude)...", scan.installed_items, { "claude-code-cli" }, 40)

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = vim.schedule_wrap(function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						local clean = line:gsub("\27%[[0-9;]*[mK]", ""):gsub("^%s*", "")
						if
							clean ~= ""
							and not clean:lower():match("password")
							and not (sudo_pass and clean:find(sudo_pass, 1, true))
						then
							add_log(clean)
						end
					end
				end
			end
		end),
		on_stderr = vim.schedule_wrap(function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						local clean = line:gsub("\27%[[0-9;]*[mK]", ""):gsub("^%s*", "")
						if
							clean ~= ""
							and not clean:lower():match("password")
							and not (sudo_pass and clean:find(sudo_pass, 1, true))
						then
							add_log("⚠️ " .. clean)
						end
					end
				end
			end
		end),
		on_exit = vim.schedule_wrap(function(_, exit_code, _)
			if exit_code == 0 then
				add_log("🎉 Claude Code CLI (claude) installed successfully!")
				update_ui_buffer(nil, M.scan_status().installed_items, {}, 100)
				vim.notify(
					"🎉 Claude Code CLI (claude) installed successfully! Run 'claude' in terminal to authenticate.",
					vim.log.levels.INFO,
					{
						title = "Claude Code CLI",
					}
				)
			else
				add_log(string.format("❌ Claude Code CLI installation failed with exit code %d.", exit_code))
				vim.notify(
					string.format("❌ Claude Code CLI installation failed (exit code %d).", exit_code),
					vim.log.levels.ERROR,
					{
						title = "Installation Failed",
					}
				)
			end
		end),
	})
end

--- Installs Claude Code CLI (`claude`) cross-platform using official oneliner scripts.
--- Prompts for root/sudo password if non-root on Linux/macOS/Termux.
function M.install_claude()
	M.ensure_sudo_pass(function(pass)
		M.run_install_claude(pass)
	end)
end

-------------------------------------------------------------------------------
--- 🌐 LANGUAGE TOOLING MANAGER (INTERACTIVE PER-LANGUAGE INSTALL / UNINSTALL)
-------------------------------------------------------------------------------

--- Language Toolchain Bundles for Language Tooling Manager.
--- Each bundle may declare `requires`: system runtimes that must be in PATH
--- before any Mason package from this bundle can be installed.
--- Builds `M.language_bundles` from each language module's own metadata --
--- `bundle_name`, `requires`, `treesitter`, `is_minimal`, `dotnet_tools` and
--- `bundle_extra_mason_pkgs` (see lua/krs/langs/init.lua's `KrsLangModule`) --
--- instead of hand-duplicating package names installer.lua doesn't own. A
--- bundle's `mason_pkgs` is resolved straight from that language's own
--- `mason_order` via `M.get_mason_package_name`, so the two can never drift.
--- @return table[] bundles
--- Human-readable abbreviation for a mason component's `type`, used as the
--- column label when a bundle is expanded in the UI.
local COMPONENT_TYPE_LABEL = { lsp = "LSP", formatter = "FMT", dap = "DAP", extra = "PKG" }

local function build_language_bundles()
	local langs_mod = require("krs.langs")
	local bundles = {}

	for _, key in ipairs(langs_mod.lang_order) do
		local lang = langs_mod.langs[key]
		if lang and lang.bundle_name then
			local mason_pkgs = {}
			local mason_components = {}

			for _, tool_key in ipairs(lang.mason_order or {}) do
				local pkg_name = M.get_mason_package_name(tool_key)
				local info = M.tools[tool_key] or {}
				table.insert(mason_pkgs, pkg_name)
				table.insert(mason_components, {
					pkg = pkg_name,
					type = info.type or "lsp",
					label = info.lang or info.name or tool_key,
				})
			end

			for _, pkg_name in ipairs(lang.bundle_extra_mason_pkgs or {}) do
				table.insert(mason_pkgs, pkg_name)
				table.insert(mason_components, { pkg = pkg_name, type = "extra", label = pkg_name })
			end

			table.insert(bundles, {
				name = lang.bundle_name,
				is_minimal = lang.is_minimal,
				requires = lang.requires or {},
				mason_pkgs = mason_pkgs,
				mason_components = mason_components,
				treesitter = lang.treesitter or {},
				dotnet_tools = lang.dotnet_tools,
			})
		end
	end

	return bundles
end

M.language_bundles = build_language_bundles()

--- Renders a `[✅ Installed (n/n)]` / `[🟡 Partial (n/n)]` / `[❌ Not Installed (0/n)]`
--- badge fragment for one category (Mason packages or Treesitter parsers).
--- @param label string Category label, e.g. "LSP" or "TS".
--- @param installed integer
--- @param total integer
--- @return string|nil badge `nil` when the bundle has no items in this category.
local function category_badge(label, installed, total)
	if total == 0 then
		return nil
	end
	if installed == total then
		return string.format("[✅ %s %d/%d]", label, installed, total)
	elseif installed > 0 then
		return string.format("[🟡 %s %d/%d]", label, installed, total)
	end
	return string.format("[❌ %s %d/%d]", label, installed, total)
end

--- Checks whether a resolved Mason package name is installed on disk or its
--- CLI binary is on `$PATH`. Shared by `get_bundle_status` and the expanded
--- per-component rows so the two can never disagree.
--- @param pkg string Mason package directory name.
--- @return boolean
local function is_mason_pkg_installed(pkg)
	local mason_share = vim.fn.stdpath("data") .. "/mason/packages"
	local pkg_dir = mason_share .. "/" .. pkg
	local pkg_stat = (vim.uv or vim.loop).fs_stat(pkg_dir)
	local info = M.tools[pkg] or {}
	local bin_cmd = info.cmd or pkg
	return (pkg_stat and pkg_stat.type == "directory") or (vim.fn.executable(bin_cmd) == 1)
end
M.is_mason_pkg_installed = is_mason_pkg_installed

--- Returns a set of installed Treesitter parser names (nvim-treesitter `main` branch API).
--- @return table<string, boolean>
local function get_installed_ts_parsers()
	local set = {}
	local ts_ok, ts_config = pcall(require, "nvim-treesitter.config")
	if ts_ok and ts_config.get_installed then
		for _, name in ipairs(ts_config.get_installed()) do
			set[name] = true
		end
	end
	return set
end
M.get_installed_ts_parsers = get_installed_ts_parsers

--- Computes real-time installation status for a given language bundle.
--- Checks required system runtimes first; if any are missing the bundle is
--- marked as blocked and no Mason/TS counts are reported. Mason packages and
--- Treesitter parsers are tracked -- and badged -- separately: the toggle-menu
--- (`KrsInstallDependencies`) only ever installs/checks Mason packages, so a
--- bundle whose LSPs came from there would otherwise sit at a misleading
--- "🟡 Partial" forever just because its Treesitter parser was never pulled in.
--- @param bundle table
--- @return table { installed_count, total_count, badge, missing_runtimes, blocked, mason_installed, mason_total, ts_installed, ts_total }
function M.get_bundle_status(bundle)
	-- 1. Check required system runtimes
	local missing_runtimes = {}
	for _, req in ipairs(bundle.requires or {}) do
		local ok = vim.fn.executable(req.cmd) == 1 or (req.alt and vim.fn.executable(req.alt) == 1)
		if not ok then
			table.insert(missing_runtimes, req.name)
		end
	end

	if #missing_runtimes > 0 then
		return {
			installed_count = 0,
			total_count = 0,
			badge = string.format("[ ⚠️  needs: %s ]", table.concat(missing_runtimes, ", ")),
			missing_runtimes = missing_runtimes,
			blocked = true,
			mason_installed = 0,
			mason_total = 0,
			ts_installed = 0,
			ts_total = 0,
		}
	end

	-- 2. Count Mason packages
	local mason_installed = 0
	local mason_total = 0

	for _, pkg in ipairs(bundle.mason_pkgs or {}) do
		mason_total = mason_total + 1
		if is_mason_pkg_installed(pkg) then
			mason_installed = mason_installed + 1
		end
	end

	-- 3. Count Treesitter parsers
	local ts_installed = 0
	local ts_total = 0
	local installed_parsers = get_installed_ts_parsers()

	for _, parser in ipairs(bundle.treesitter or {}) do
		ts_total = ts_total + 1
		if installed_parsers[parser] then
			ts_installed = ts_installed + 1
		end
	end

	local badge_parts = {}
	local lsp_badge = category_badge("LSP", mason_installed, mason_total)
	local ts_badge = category_badge("TS", ts_installed, ts_total)
	if lsp_badge then
		table.insert(badge_parts, lsp_badge)
	end
	if ts_badge then
		table.insert(badge_parts, ts_badge)
	end

	return {
		installed_count = mason_installed + ts_installed,
		total_count = mason_total + ts_total,
		badge = table.concat(badge_parts, " "),
		missing_runtimes = {},
		blocked = false,
		mason_installed = mason_installed,
		mason_total = mason_total,
		ts_installed = ts_installed,
		ts_total = ts_total,
	}
end

--- Installs or uninstalls component subsets across one or more bundles in a
--- single batch, firing exactly one "starting" toast and one "finished" toast
--- for the whole batch -- never one pair per bundle. If nothing in the
--- selection actually needs work (already installed / already gone), fires a
--- single "nothing to do" toast instead of a start+finish pair.
--- @param jobs table[] { { bundle = bundle, sel = {mason=,ts=,dotnet=} }, ... }
--- @param action "install"|"uninstall"
local function run_batch(jobs, action)
	local installing = action == "install"

	-- 1. Drop bundles missing a required runtime (install only); summarize once.
	local runnable, blocked_names = {}, {}
	for _, job in ipairs(jobs) do
		local missing = {}
		if installing then
			for _, req in ipairs(job.bundle.requires or {}) do
				local ok = vim.fn.executable(req.cmd) == 1 or (req.alt and vim.fn.executable(req.alt) == 1)
				if not ok then
					table.insert(missing, req.name)
				end
			end
		end
		if #missing > 0 then
			table.insert(blocked_names, job.bundle.name)
		else
			table.insert(runnable, job)
		end
	end

	if #blocked_names > 0 then
		vim.notify(
			string.format("⚠️ Skipped (missing runtime): %s", table.concat(blocked_names, ", ")),
			vim.log.levels.WARN,
			{ title = "Install Dependencies & Toolchains" }
		)
	end

	-- 2. Split the selection into "already done" vs. actual work, so the
	-- toasts only ever describe what's really about to happen.
	local installed_ts = get_installed_ts_parsers()
	local todo_mason, todo_ts, todo_dotnet = {}, {}, {}
	local bundle_names = {}

	for _, job in ipairs(runnable) do
		local any_for_bundle = false

		for _, pkg in ipairs(job.sel.mason or {}) do
			local pkg_installed = is_mason_pkg_installed(pkg)
			if installing ~= pkg_installed then
				table.insert(todo_mason, pkg)
				any_for_bundle = true
			end
		end

		for _, parser in ipairs(job.sel.ts or {}) do
			local parser_installed = installed_ts[parser] or false
			if installing ~= parser_installed then
				table.insert(todo_ts, parser)
				any_for_bundle = true
			end
		end

		-- Dotnet tool install state isn't tracked, so treat every selected
		-- tool as work to do (see `M.cli_healthcheck`'s ponytail note for why).
		for _, tool in ipairs(job.sel.dotnet or {}) do
			table.insert(todo_dotnet, tool)
			any_for_bundle = true
		end

		if any_for_bundle then
			table.insert(bundle_names, job.bundle.name)
		end
	end

	local total_todo = #todo_mason + #todo_ts + #todo_dotnet
	if total_todo == 0 then
		vim.notify(
			string.format("ℹ️ Nothing to %s -- selection is already %s.", action, installing and "installed" or "removed"),
			vim.log.levels.INFO,
			{ title = "Install Dependencies & Toolchains" }
		)
		return
	end

	vim.notify(
		string.format(
			"%s %d component(s) for %s...",
			installing and "📥 Installing" or "🗑️ Uninstalling",
			total_todo,
			table.concat(bundle_names, ", ")
		),
		vim.log.levels.INFO,
		{ title = "Install Dependencies & Toolchains" }
	)

	-- 3. Mason packages
	local mr_ok, mr = pcall(require, "mason-registry")
	if mr_ok and #todo_mason > 0 then
		local function apply()
			for _, pkg_name in ipairs(todo_mason) do
				if mr.has_package(pkg_name) then
					local pkg = mr.get_package(pkg_name)
					if installing then
						pkg:install()
					else
						pcall(function()
							pkg:uninstall()
						end)
					end
				end
			end
		end
		if installing then
			mr.refresh(apply)
		else
			apply()
		end
	end

	-- 4. Treesitter parsers
	local ts_ok, ts = pcall(require, "nvim-treesitter")
	if ts_ok then
		local ts_fn = installing and ts.install or ts.uninstall
		for _, parser in ipairs(todo_ts) do
			pcall(ts_fn, { parser })
		end
	end

	-- 5. Dotnet global tools
	if vim.fn.executable("dotnet") == 1 then
		for _, tool in ipairs(todo_dotnet) do
			vim.system({ "dotnet", "tool", action, "-g", tool })
		end
	end

	vim.notify(
		string.format(
			"%s %d component(s) for %s",
			installing and "✅ Install triggered for" or "🗑️ Uninstall triggered for",
			total_todo,
			table.concat(bundle_names, ", ")
		),
		installing and vim.log.levels.INFO or vim.log.levels.WARN,
		{ title = "Install Dependencies & Toolchains" }
	)
end

--- Installs every package, parser, and dotnet tool in a language bundle.
--- @param bundle table
function M.install_language_bundle(bundle)
	run_batch(
		{ { bundle = bundle, sel = { mason = bundle.mason_pkgs, ts = bundle.treesitter, dotnet = bundle.dotnet_tools } } },
		"install"
	)
end

--- Uninstalls every package, parser, and dotnet tool in a language bundle.
--- @param bundle table
function M.uninstall_language_bundle(bundle)
	run_batch(
		{ { bundle = bundle, sel = { mason = bundle.mason_pkgs, ts = bundle.treesitter, dotnet = bundle.dotnet_tools } } },
		"uninstall"
	)
end

--- Installs only the given component subset of a language bundle.
--- @param bundle table
--- @param sel table { mason: string[], ts: string[], dotnet: string[] }
function M.install_bundle_components(bundle, sel)
	run_batch({ { bundle = bundle, sel = sel } }, "install")
end

--- Uninstalls only the given component subset of a language bundle.
--- @param bundle table
--- @param sel table { mason: string[], ts: string[], dotnet: string[] }
function M.uninstall_bundle_components(bundle, sel)
	run_batch({ { bundle = bundle, sel = sel } }, "uninstall")
end

--- Installs component subsets across many bundles in one batch (one toast pair total).
--- @param jobs table[] { { bundle = bundle, sel = {mason=,ts=,dotnet=} }, ... }
function M.install_batch(jobs)
	run_batch(jobs, "install")
end

--- Uninstalls component subsets across many bundles in one batch (one toast pair total).
--- @param jobs table[] { { bundle = bundle, sel = {mason=,ts=,dotnet=} }, ... }
function M.uninstall_batch(jobs)
	run_batch(jobs, "uninstall")
end

--- Counts how many of an item's per-component checkboxes are selected.
--- @param item table entry from `lang_items`
--- @return integer selected, integer total
local function count_selected_components(item)
	local sel, tot = 0, 0
	for _, v in pairs(item.comp.mason) do
		tot = tot + 1
		if v then
			sel = sel + 1
		end
	end
	for _, v in pairs(item.comp.ts) do
		tot = tot + 1
		if v then
			sel = sel + 1
		end
	end
	for _, v in pairs(item.comp.dotnet) do
		tot = tot + 1
		if v then
			sel = sel + 1
		end
	end
	return sel, tot
end
M.count_selected_components = count_selected_components

--- Sets every component checkbox of an item to `val` in one go. Used by the
--- bundle-row bulk toggle and the `a`/`n`/`p` select-all keymaps.
--- @param item table entry from `lang_items`
--- @param val boolean
local function set_item_components(item, val)
	for k in pairs(item.comp.mason) do
		item.comp.mason[k] = val
	end
	for k in pairs(item.comp.ts) do
		item.comp.ts[k] = val
	end
	for k in pairs(item.comp.dotnet) do
		item.comp.dotnet[k] = val
	end
	item.selected = val
end
M.set_item_components = set_item_components

--- Renders the Interactive Language Manager UI floating buffer.
function M.render_language_manager_buffer()
	if not lang_buf or not vim.api.nvim_buf_is_valid(lang_buf) then
		return
	end

	local lines = {}
	lang_line_map = {}

	local width = (lang_win and vim.api.nvim_win_is_valid(lang_win)) and vim.api.nvim_win_get_width(lang_win) or 76

	table.insert(lines, "  ==========================================================================")
	table.insert(lines, "   📦 KRS INSTALL DEPENDENCIES & TOOLCHAINS -- PER-LANGUAGE SETUP & TEARDOWN")
	table.insert(lines, "  ==========================================================================")
	table.insert(
		lines,
		"   Fresh setup defaults to Minimal Core (Lua only). [Enter] a row to pick individual components."
	)
	table.insert(lines, "")

	local selected_count = 0
	local pending_count = 0

	for _, item in ipairs(lang_items) do
		local status = M.get_bundle_status(item.bundle)
		item.status = status

		local is_fully_installed = (status.installed_count == status.total_count and status.total_count > 0)
		local is_pending = not status.blocked and not is_fully_installed and not item.bundle.is_minimal

		if is_pending then
			pending_count = pending_count + 1
		end

		local sel_n, tot_n = count_selected_components(item)

		-- Blocked bundles get a lock symbol instead of a checkbox
		local checkbox
		if status.blocked then
			checkbox = "[🔒]"
		elseif tot_n == 0 or sel_n == 0 then
			checkbox = "[ ]"
		elseif sel_n == tot_n then
			checkbox = "[x]"
		else
			checkbox = "[~]"
		end
		if sel_n > 0 and not status.blocked then
			selected_count = selected_count + 1
		end

		local arrow = item.expanded and "▾" or "▸"
		local tag = item.bundle.is_minimal and " (Core)" or ""
		local line_str = string.format("  %s %s  %-26s %s%s", arrow, checkbox, item.bundle.name, status.badge, tag)
		table.insert(lines, line_str)
		lang_line_map[#lines] = { kind = "bundle", item = item }

		if item.expanded and not status.blocked then
			local installed_ts = get_installed_ts_parsers()

			for _, comp in ipairs(item.bundle.mason_components or {}) do
				local sel_mark = item.comp.mason[comp.pkg] and "[x]" or "[ ]"
				local mark = is_mason_pkg_installed(comp.pkg) and "✓" or "❌"
				local type_label = COMPONENT_TYPE_LABEL[comp.type] or comp.type:upper()
				table.insert(lines, string.format("        %s %-4s %-32s %s", sel_mark, type_label, comp.label, mark))
				lang_line_map[#lines] = { kind = "component", item = item, ctype = "mason", key = comp.pkg }
			end

			for _, parser in ipairs(item.bundle.treesitter or {}) do
				local sel_mark = item.comp.ts[parser] and "[x]" or "[ ]"
				local mark = installed_ts[parser] and "✓" or "❌"
				table.insert(lines, string.format("        %s %-4s %-32s %s", sel_mark, "TS", parser, mark))
				lang_line_map[#lines] = { kind = "component", item = item, ctype = "ts", key = parser }
			end

			for _, tool in ipairs(item.bundle.dotnet_tools or {}) do
				local sel_mark = item.comp.dotnet[tool] and "[x]" or "[ ]"
				table.insert(lines, string.format("        %s %-4s %-32s %s", sel_mark, "NET", tool, "?"))
				lang_line_map[#lines] = { kind = "component", item = item, ctype = "dotnet", key = tool }
			end

			table.insert(lines, "")
		end
	end

	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(
		lines,
		string.format("  👉 [ PRESS 'i' OR ENTER TO INSTALL SELECTED COMPONENTS (%d BUNDLES) ]", selected_count)
	)
	table.insert(lines, "  [Enter] Expand/Toggle Row            |  [Space] Toggle Checkbox  |  [d] Show Details")
	table.insert(
		lines,
		string.format("  [a] Select All    [n] Select None   |  [p] Select All Pending (%d bundles)", pending_count)
	)
	table.insert(lines, "  [i] Install Selected                |  [u] Uninstall Selected  |  [q/Esc] Close")

	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 4))
	table.insert(lines, "   🩺 CLI HEALTH CHECK -- found in $PATH?")
	local health_parts = {}
	for _, tool in ipairs(M.cli_healthcheck) do
		local found = vim.fn.executable(tool.cmd) == 1 or (tool.alt and vim.fn.executable(tool.alt) == 1)
		table.insert(health_parts, (found and "✅ " or "❌ ") .. tool.cmd)
		if #health_parts >= 5 then
			table.insert(lines, "   " .. table.concat(health_parts, "   "))
			health_parts = {}
		end
	end
	if #health_parts > 0 then
		table.insert(lines, "   " .. table.concat(health_parts, "   "))
	end

	pcall(function()
		vim.bo[lang_buf].modifiable = true
		vim.api.nvim_buf_set_lines(lang_buf, 0, -1, false, lines)
		vim.bo[lang_buf].modifiable = false
	end)
end

--- Opens the Floating Buffer UI for Language Tooling Manager.
function M.open_language_manager()
	local ui = require("krs.core.ui")

	if lang_win and vim.api.nvim_win_is_valid(lang_win) then
		vim.api.nvim_set_current_win(lang_win)
		return
	end

	lang_items = {}
	for _, bundle in ipairs(M.language_bundles) do
		local status = M.get_bundle_status(bundle)
		-- Only pre-select: minimal core (always on) or fully installed bundles.
		-- Partial or missing bundles start deselected — user must opt-in.
		local auto_select = bundle.is_minimal or (status.installed_count == status.total_count and status.total_count > 0)

		local comp = { mason = {}, ts = {}, dotnet = {} }
		for _, c in ipairs(bundle.mason_components or {}) do
			comp.mason[c.pkg] = auto_select
		end
		for _, parser in ipairs(bundle.treesitter or {}) do
			comp.ts[parser] = auto_select
		end
		for _, tool in ipairs(bundle.dotnet_tools or {}) do
			comp.dotnet[tool] = auto_select
		end

		table.insert(lang_items, {
			bundle = bundle,
			selected = auto_select,
			status = status,
			expanded = false,
			comp = comp,
		})
	end

	local cols = vim.o.columns or 80
	local lines_cnt = vim.o.lines or 24
	local width = math.max(48, math.min(78, cols - 4))
	local height = math.max(14, math.min(22, lines_cnt - 4))

	lang_buf, lang_win = ui.float({
		width = width,
		height = height,
		title = " 📦 KRS Install Dependencies & Toolchains ",
		focusable = true,
		modifiable = false,
	})

	ui.close_on_keys(lang_buf, lang_win)
	M.render_language_manager_buffer()

	local opts = { buffer = lang_buf, silent = true, noremap = true }

	local function get_current_entry()
		if not lang_win or not vim.api.nvim_win_is_valid(lang_win) then
			return nil, nil
		end
		local cursor = vim.api.nvim_win_get_cursor(lang_win)
		return lang_line_map[cursor[1]], cursor
	end

	--- Toggles exactly one checkbox: the single component under the cursor,
	--- or every component of a bundle row at once (bulk select/deselect).
	local function toggle_checkbox()
		local entry, cursor = get_current_entry()
		if not entry then
			return
		end

		if entry.kind == "bundle" then
			local sel_n, tot_n = count_selected_components(entry.item)
			set_item_components(entry.item, sel_n < tot_n)
		elseif entry.kind == "component" then
			local map = entry.item.comp[entry.ctype]
			map[entry.key] = not map[entry.key]
		end

		M.render_language_manager_buffer()
		if cursor and lang_win and vim.api.nvim_win_is_valid(lang_win) then
			pcall(vim.api.nvim_win_set_cursor, lang_win, cursor)
		end
	end

	--- <CR>: expands/collapses a bundle row; on a component row it's the same
	--- as <Space> (toggle that one component).
	local function expand_or_toggle()
		local entry, cursor = get_current_entry()
		if not entry then
			return
		end

		if entry.kind == "bundle" then
			entry.item.expanded = not entry.item.expanded
		elseif entry.kind == "component" then
			local map = entry.item.comp[entry.ctype]
			map[entry.key] = not map[entry.key]
		end

		M.render_language_manager_buffer()
		if cursor and lang_win and vim.api.nvim_win_is_valid(lang_win) then
			pcall(vim.api.nvim_win_set_cursor, lang_win, cursor)
		end
	end

	local function collect_selection(item)
		local mason, ts, dotnet = {}, {}, {}
		for pkg, v in pairs(item.comp.mason) do
			if v then
				table.insert(mason, pkg)
			end
		end
		for parser, v in pairs(item.comp.ts) do
			if v then
				table.insert(ts, parser)
			end
		end
		for tool, v in pairs(item.comp.dotnet) do
			if v then
				table.insert(dotnet, tool)
			end
		end
		return { mason = mason, ts = ts, dotnet = dotnet }
	end

	local function has_any_selection(item)
		local sel_n = count_selected_components(item)
		return sel_n > 0
	end

	local function install_action()
		local entry, cursor = get_current_entry()
		local any_global = false
		for _, it in ipairs(lang_items) do
			if has_any_selection(it) then
				any_global = true
				break
			end
		end

		if any_global then
			for _, it in ipairs(lang_items) do
				if has_any_selection(it) then
					M.install_bundle_components(it.bundle, collect_selection(it))
				end
			end
		elseif entry and entry.item then
			M.install_language_bundle(entry.item.bundle)
		else
			vim.notify(
				"⚠️ Move cursor to a language row or select checkboxes with <Space> to install.",
				vim.log.levels.WARN
			)
			return
		end

		vim.defer_fn(function()
			M.render_language_manager_buffer()
			if cursor and lang_win and vim.api.nvim_win_is_valid(lang_win) then
				pcall(vim.api.nvim_win_set_cursor, lang_win, cursor)
			end
		end, 600)
	end

	local function uninstall_action()
		local entry, cursor = get_current_entry()
		local any_global = false
		for _, it in ipairs(lang_items) do
			if has_any_selection(it) then
				any_global = true
				break
			end
		end

		if any_global then
			for _, it in ipairs(lang_items) do
				if has_any_selection(it) then
					M.uninstall_bundle_components(it.bundle, collect_selection(it))
				end
			end
		elseif entry and entry.item then
			M.uninstall_language_bundle(entry.item.bundle)
		else
			vim.notify(
				"⚠️ Move cursor to a language row or select checkboxes with <Space> to uninstall.",
				vim.log.levels.WARN
			)
			return
		end

		vim.defer_fn(function()
			M.render_language_manager_buffer()
			if cursor and lang_win and vim.api.nvim_win_is_valid(lang_win) then
				pcall(vim.api.nvim_win_set_cursor, lang_win, cursor)
			end
		end, 600)
	end

	local function show_details()
		local entry = get_current_entry()
		if entry and entry.item then
			local item = entry.item
			local details = {
				"Language Bundle: " .. item.bundle.name,
				"Mason Packages: " .. table.concat(item.bundle.mason_pkgs or {}, ", "),
				"Treesitter Parsers: " .. table.concat(item.bundle.treesitter or {}, ", "),
			}
			if item.bundle.dotnet_tools then
				table.insert(details, "Dotnet Tools: " .. table.concat(item.bundle.dotnet_tools, ", "))
			end
			vim.notify(table.concat(details, "\n"), vim.log.levels.INFO, {
				title = item.bundle.name .. " Component Details",
			})
		end
	end

	vim.keymap.set("n", "<space>", toggle_checkbox, opts)
	vim.keymap.set("n", "<CR>", expand_or_toggle, opts)
	vim.keymap.set("n", "<2-LeftMouse>", expand_or_toggle, opts)

	vim.keymap.set("n", "i", install_action, opts)
	vim.keymap.set("n", "I", install_action, opts)
	vim.keymap.set("n", "u", uninstall_action, opts)
	vim.keymap.set("n", "U", uninstall_action, opts)
	vim.keymap.set("n", "d", show_details, opts)

	vim.keymap.set("n", "a", function()
		for _, item in ipairs(lang_items) do
			local status = item.status or M.get_bundle_status(item.bundle)
			if not status.blocked then
				set_item_components(item, true)
			end
		end
		M.render_language_manager_buffer()
	end, opts)

	vim.keymap.set("n", "n", function()
		for _, item in ipairs(lang_items) do
			set_item_components(item, item.bundle.is_minimal == true)
		end
		M.render_language_manager_buffer()
	end, opts)

	-- [p] Select all pending bundles that are NOT blocked by missing runtimes (opt-in)
	vim.keymap.set("n", "p", function()
		for _, item in ipairs(lang_items) do
			local status = item.status or M.get_bundle_status(item.bundle)
			if not item.bundle.is_minimal and not status.blocked and status.installed_count < status.total_count then
				set_item_components(item, true)
			end
		end
		M.render_language_manager_buffer()
	end, opts)
end

--- Initializes setup checks on Neovim startup.
function M.init()
	-- Register User Commands immediately
	vim.api.nvim_create_user_command("LanguageManager", function()
		M.open_language_manager()
	end, { desc = "Open interactive Install Dependencies & Toolchains UI for per-language bundles" })

	vim.api.nvim_create_user_command("KrsLanguageManager", function()
		M.open_language_manager()
	end, { desc = "Open interactive Install Dependencies & Toolchains UI for per-language bundles" })

	vim.api.nvim_create_user_command("LanguageTooling", function()
		M.open_language_manager()
	end, { desc = "Open interactive Install Dependencies & Toolchains UI for per-language bundles" })

	vim.api.nvim_create_user_command("KrsInstallDependencies", function()
		M.open_language_manager()
	end, { desc = "Open interactive Install Dependencies & Toolchains UI for per-language bundles" })

	vim.api.nvim_create_user_command("KrsInstaller", function()
		M.open_language_manager()
	end, { desc = "Open interactive Install Dependencies & Toolchains UI for per-language bundles" })

	vim.api.nvim_create_user_command("KrsSetup", function()
		M.open_language_manager()
	end, { desc = "Run interactive Install Dependencies & Toolchains UI for per-language bundles" })

	vim.api.nvim_create_user_command("KrsSystemSetup", function()
		M.run_system_setup_interactive()
	end, { desc = "Run system dependency installer script with interactive Sudo UI password prompt" })

	vim.api.nvim_create_user_command("KrsInstallSystemDependencies", function()
		M.run_system_setup_interactive()
	end, { desc = "Run system dependency installer script with interactive Sudo UI password prompt" })

	vim.api.nvim_create_user_command("KrsInstallAgy", function()
		M.install_agy()
	end, { desc = "Install Google Antigravity CLI (agy) cross-platform" })

	vim.api.nvim_create_user_command("AgyInstall", function()
		M.install_agy()
	end, { desc = "Install Google Antigravity CLI (agy) cross-platform" })

	vim.api.nvim_create_user_command("InstallAgy", function()
		M.install_agy()
	end, { desc = "Install Google Antigravity CLI (agy) cross-platform" })

	vim.api.nvim_create_user_command("KrsInstallClaude", function()
		M.install_claude()
	end, { desc = "Install Claude Code CLI (claude) cross-platform" })

	vim.api.nvim_create_user_command("ClaudeInstall", function()
		M.install_claude()
	end, { desc = "Install Claude Code CLI (claude) cross-platform" })

	vim.api.nvim_create_user_command("InstallClaude", function()
		M.install_claude()
	end, { desc = "Install Claude Code CLI (claude) cross-platform" })

	vim.api.nvim_create_user_command("KrsInstallAll", function()
		M.install_all()
	end, { desc = "Install all missing LSPs, Treesitter parsers, and system dependencies" })

	vim.api.nvim_create_user_command("MasonInstallAll", function()
		M.install_all()
	end, { desc = "Alias for KrsInstallAll - Install all missing LSPs and tools" })

	vim.api.nvim_create_user_command("KrsSetupStatus", function()
		M.show_status()
	end, { desc = "Check detailed installation health status in Live Setup Modal" })

	vim.api.nvim_create_user_command("KrsHealthCheck", function()
		M.open_health_check()
	end, { desc = "Open the full KRS health check page (every CLI/tool this config needs)" })

	vim.api.nvim_create_user_command("KrsSetupReset", function()
		M.reset_state()
	end, { desc = "Reset completion state file to force a full setup re-check" })

	local state = M.load_state()

	-- Mark setup complete on startup without popup warning toasts
	if not state.completed then
		M.save_state(true)
	end
end

return M
