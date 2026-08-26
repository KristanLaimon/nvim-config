-- ============================================================================
-- KRS PLUGIN: PHP Environment Check -- is PHP tooling actually installed?
-- ============================================================================
-- WHAT IT DOES
--   Looks for PHP and Composer on the Windows host and, failing that, inside WSL,
--   then shows a modal with copy-paste install instructions for whatever is
--   missing. Called by the PHP/Laravel LSP setup before it tries to start.
--
-- WHY IT PROBES WSL SECOND
--   `wsl php -v` boots the distro, which is slow. It only runs when the Windows
--   side did not already answer.
-- ============================================================================

local ui = require("krs.core.ui")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Width of the modal, in cells.
	modal_width = 64,

	--- Modal title.
	modal_title = " 🐘 PHP & Laravel Environment ",

	--- Keys that dismiss the modal.
	close_keys = { "<Esc>", "q", "<CR>" },

	--- Tools that must exist, in report order.
	--- `wsl_probe` is the command run inside WSL, and `wsl_match` the pattern its
	--- output must contain for the tool to count as present.
	tools = {
		{
			key = "php",
			label = "PHP CLI binary (php)",
			executable = "php",
			wsl_probe = "wsl php -v 2>/dev/null",
			wsl_match = "PHP%s+%d",
		},
		{
			key = "composer",
			label = "Composer package manager (composer)",
			executable = "composer",
			wsl_probe = "wsl composer --version 2>/dev/null",
			wsl_match = "Composer",
		},
	},

	--- Shown under the status list.
	install_help = {
		" 📌  How to install PHP & Composer:",
		"  • Windows (Native):",
		"     1. Install Laravel Herd: https://herd.laravel.com",
		"        OR via Scoop: `scoop install php composer`",
		"        OR via Chocolatey: `choco install php composer`",
		"  • WSL (Linux/Ubuntu):",
		"     1. Open WSL terminal and run:",
		"        `sudo apt update && sudo apt install php-cli composer php-xml php-mbstring`",
	},
}

-- ============================================================================
-- API
-- ============================================================================

--- Checks the environment and, unless silenced, shows the modal when something
--- is missing.
---
--- @param silent boolean|nil Suppress the modal and only return the status.
--- @return table status `{ php, composer, win_php, wsl_php, ..., has_wsl }`
function M.check_tools(silent)
	local is_win = vim.fn.has("win32") == 1
	local has_wsl = is_win and (vim.fn.executable("wsl.exe") == 1 or vim.fn.executable("wsl") == 1)

	local status = { has_wsl = has_wsl }
	local all_present = true

	for _, tool in ipairs(M.settings.tools) do
		local on_windows = vim.fn.executable(tool.executable) == 1
		local on_wsl = false

		if has_wsl and not on_windows then
			local out = vim.fn.system(tool.wsl_probe)
			on_wsl = type(out) == "string" and out:match(tool.wsl_match) ~= nil
		end

		status["win_" .. tool.key] = on_windows
		status["wsl_" .. tool.key] = on_wsl
		status[tool.key] = on_windows or on_wsl
		all_present = all_present and status[tool.key]
	end

	if not all_present and not silent then
		M.show_missing_modal(status)
	end
	return status
end

--- Renders the environment report modal.
--- @param status table Result of `M.check_tools`.
function M.show_missing_modal(status)
	local lines = {
		" ⚠️  PHP & Laravel Environment Status ",
		" ──────────────────────────────────────────────────────────",
		" Neovim detected missing PHP development tools:",
		"",
	}

	for _, tool in ipairs(M.settings.tools) do
		if status[tool.key] then
			local where = status["win_" .. tool.key] and "Windows" or "WSL"
			table.insert(lines, "  ✅  " .. tool.label .. " is available (" .. where .. ")")
		else
			table.insert(lines, "  ❌  " .. tool.label .. " is NOT installed or in PATH")
		end
	end

	table.insert(lines, "")
	vim.list_extend(lines, M.settings.install_help)
	vim.list_extend(lines, {
		"",
		" ──────────────────────────────────────────────────────────",
		" Press <Esc> or 'q' to dismiss this window.",
	})

	local buf, win = ui.float({
		lines = lines,
		width = M.settings.modal_width,
		height = #lines,
		filetype = "krsphpmodal",
		title = M.settings.modal_title,
	})
	pcall(vim.api.nvim_set_option_value, "cursorline", false, { win = win })
	ui.close_on_keys(buf, win, M.settings.close_keys)
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.PhpToolsModal = M

-- ============================================================================
-- LAZY.NVIM SPEC -- no config(): callers invoke check_tools() directly.
-- ============================================================================

return setmetatable({
	name = "krs_php_tools_modal",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = "PHPCheckTools",
}, { __index = M })
