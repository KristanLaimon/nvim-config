-- ============================================================================
-- CONFIG: Editor options -- everything that is set before plugins load.
-- ============================================================================
-- WHAT LIVES HERE
--   1. Plain Neovim options, grouped by what they are for.
--   2. Shell selection per platform.
--
-- WHAT DOES NOT LIVE HERE
--   Keymaps (lua/keymaps/), plugins (lua/plugins/), colors (colors/).
--
-- TO CHANGE A SETTING
--   Edit the tables in the CONFIGURATION block below. Everything under API is
--   mechanical application of those values.
-- ============================================================================

-- ============================================================================
-- MODULE DELEGATION (Extracted Responsibilities)
-- ============================================================================

-- 1. Filetype registration and syntax aliases
require("krs.core.filetypes").setup()

-- 2. Fallback clipboard provider for headless / mobile
require("krs.core.clipboard").setup()

-- 3. Prepend local toolchains to PATH for GUI launches
require("krs.core.path_repair").setup()

-- 4. Set up system aliases (shim executables) like CC -> gcc
require("krs.core.aliases").setup()

-- 5. Mobile & low-power performance overrides
require("krs.core.performance").setup()

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Editor options, applied through `vim.opt`.
	options = {
		-- Appearance
		number = true,
		relativenumber = true,
		cursorline = true,
		showmode = false, -- The statusline already shows the mode.
		cmdheight = 1, -- Reserve 1 row at bottom for messages to prevent hit-enter prompts.
		laststatus = 3, -- One global statusline.

		-- Indentation: spaces, two columns wide (standard for Astro, JS/TS, Tailwind, Biome, HTML, JSON).
		expandtab = true,
		shiftwidth = 2,
		tabstop = 2,
		softtabstop = 2,
		autoindent = true,
		smartindent = false,

		-- Encoding
		encoding = "utf-8",

		-- Folding: Treesitter folding for HTML tags, functions, and scope blocks with mouse click foldcolumn support.
		foldmethod = "expr",
		foldexpr = "v:lua.vim.treesitter.foldexpr()",
		foldlevel = 99,
		foldlevelstart = 99,
		foldenable = true,
		foldcolumn = "1",
		fillchars = "eob: ,fold: ,foldopen:,foldclose:,foldsep: ",
		viewoptions = "folds,cursor",

		-- Behaviour and performance
		mouse = "a",
		autoread = true, -- Pick up files changed outside the editor.
		clipboard = "", -- Only copy to system clipboard explicitly (e.g. <C-c>, "+y).
		updatetime = 250, -- Faster CursorHold and diagnostics.
		timeoutlen = 300, -- Snappier multi-key mappings.
		redrawtime = 1500, -- Do not freeze redrawing huge files.
		synmaxcol = 300, -- Stop highlighting very long lines.
		swapfile = false,
		writebackup = false,
		undofile = true, -- Persistent undo instead.
		shortmess = "sWICcFsotT", -- Suppress unnecessary startup, file info, and hit-enter prompts.
		fileformats = "unix,dos", -- Preserve LF (\n) and CRLF (\r\n) line endings automatically on open/save.
	},

	--- Options set through pcall because a build may not support them.
	optional_options = { fileencoding = "utf-8" },

	--- Providers disabled outright (netrw is replaced by neo-tree).
	disabled_globals = { loaded_netrw = 1, loaded_netrwPlugin = 1 },

	--- Neovide window padding. The defaults leave a visible gap under the status line.
	neovide = {
		neovide_padding_top = 0,
		neovide_padding_bottom = 0,
		neovide_padding_right = 0,
		neovide_padding_left = 0,
	},

	--- Shell used for `:!` and `:terminal`, per platform.
	--- The Windows value is resolved below: Git Bash when it is actually
	--- installed, otherwise the PowerShell included with Windows.
	shell = {
		unix = { shell = "bash" },
	},
}

local is_windows = vim.fn.has("win32") == 1

-- ============================================================================
-- GLOBALS & OPTIONS
-- ============================================================================

for name, value in pairs(settings.disabled_globals) do
	vim.g[name] = value
end

for name, value in pairs(settings.options) do
	vim.opt[name] = value
end

for name, value in pairs(settings.optional_options) do
	pcall(function()
		vim.opt[name] = value
	end)
end

-- Plugins that print messages restore cmdheight=1 during startup; put it back.
vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter" }, {
	callback = function()
		vim.opt.cmdheight = settings.options.cmdheight
	end,
})

-- Ensure autoindent is always enabled for all filetypes, preventing legacy runtime
-- indent scripts (such as `indent/php.vim`) from disabling autoindent on newlines/cc.
vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufNewFile" }, {
	pattern = "*",
	callback = function(args)
		vim.bo[args.buf].autoindent = true
	end,
})

if vim.g.neovide then
	for name, value in pairs(settings.neovide) do
		vim.g[name] = value
	end
end

-- ============================================================================
-- SHELL
-- ============================================================================

--- Returns an executable Git Bash path without relying on a volume's optional
--- 8.3 short-name support (for example, `C:\\PROGRA~1`).
--- @return string|nil
local function git_bash_path()
	local candidates = {}
	local git = vim.fn.exepath("git.exe")
	if git ~= "" then
		table.insert(candidates, vim.fn.fnamemodify(git, ":h:h") .. "/bin/bash.exe")
	end

	for _, program_files in ipairs({ vim.env.ProgramFiles, vim.env.ProgramW6432, vim.env["ProgramFiles(x86)"] }) do
		if program_files and program_files ~= "" then
			table.insert(candidates, program_files .. "/Git/bin/bash.exe")
		end
	end

	for _, candidate in ipairs(candidates) do
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end
end

--- Builds Windows shell options. Git Bash is preferred for POSIX command
--- compatibility; a missing or relocated Git install falls back to PowerShell.
--- @return table
local function windows_shell_settings()
	local bash = git_bash_path()
	if bash then
		return {
			shell = bash,
			shellcmdflag = "-c",
			shellxquote = "",
			shellquote = "",
			shellredir = ">%s 2>&1",
			shellpipe = "2>&1| tee",
		}
	end

	local powershell = vim.fn.exepath("pwsh.exe")
	if powershell == "" then
		powershell = vim.fn.exepath("powershell.exe")
	end
	if powershell ~= "" then
		return {
			shell = powershell,
			shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command",
			shellredir = "2>&1 | Out-File -Encoding UTF8 %s",
			shellpipe = "2>&1 | Tee-Object -FilePath %s",
			shellquote = "",
			shellxquote = "",
		}
	end

	-- `cmd.exe` is present on supported Windows installations and gives Neovim
	-- a functional terminal even on unusually stripped-down systems.
	return { shell = "cmd.exe" }
end

local shell_settings = (vim.fn.has("wsl") == 1 or vim.fn.has("unix") == 1) and settings.shell.unix
	or (is_windows and windows_shell_settings())

for name, value in pairs(shell_settings or {}) do
	vim.opt[name] = value
end

-- ============================================================================
-- LANGUAGE SUBSYSTEM INITIALIZATION
-- ============================================================================

-- Initialize per-language internal configurations (e.g. PHP Composer vendor bin)
require("krs.langs").setup()
