-- ============================================================================
-- CONFIG: Editor options -- everything that is set before plugins load.
-- ============================================================================
-- WHAT LIVES HERE
--   1. Plain Neovim options, grouped by what they are for.
--   2. Shell selection per platform.
--
-- WHAT DOES NOT LIVE HERE
--   Keymaps (lua/config/keymaps/), plugins (lua/plugins/), colors (colors/).
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
	--- Windows points at Git Bash, so POSIX one-liners work everywhere.
	shell = {
		unix = { shell = "bash" },
		windows = {
			shell = "C:\\PROGRA~1\\Git\\bin\\bash.exe",
			shellcmdflag = "-c",
			shellxquote = "",
			shellquote = "",
			shellredir = ">%s 2>&1",
			shellpipe = "2>&1| tee",
		},
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

local shell_settings = (vim.fn.has("wsl") == 1 or vim.fn.has("unix") == 1) and settings.shell.unix
	or (is_windows and settings.shell.windows)

for name, value in pairs(shell_settings or {}) do
	vim.opt[name] = value
end

-- ============================================================================
-- LANGUAGE SUBSYSTEM INITIALIZATION
-- ============================================================================

-- Initialize per-language internal configurations (e.g. PHP Composer vendor bin)
require("krs.langs").setup()
