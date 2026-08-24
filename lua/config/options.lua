-- ============================================================================
-- CONFIG: Editor options -- everything that is set before plugins load.
-- ============================================================================
-- WHAT LIVES HERE
--   1. The `.krsnvim` filetype registration (Lua syntax under the hood).
--   2. Plain Neovim options, grouped by what they are for.
--   3. Shell selection per platform.
--   4. PATH repair: GUI launches (Neovide, the Windows start menu) inherit a
--      minimal PATH, so node/bun/cargo toolchains are found and prepended here.
--
-- WHAT DOES NOT LIVE HERE
--   Keymaps (lua/config/keymaps/), plugins (lua/plugins/), colors (colors/).
--
-- TO CHANGE A SETTING
--   Edit the tables in the CONFIGURATION block below. Everything under API is
--   mechanical application of those values.
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Extension -> filetype registrations.
	filetypes = { krsnvim = "krsnvim" },

	--- Filetypes that borrow another language's syntax and Treesitter parser.
	syntax_aliases = { krsnvim = "lua" },

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

	--- Toolchain directories prepended to PATH when they exist.
	--- ADD A TOOLCHAIN HERE if a GUI launch cannot find your runtime.
	--- Entries may be nil (an unset environment variable); they are filtered out
	--- before use, so the list never ends early on a missing variable.
	path_candidates = {
		windows = function(env)
			return {
				env.APPDATA .. "\\fnm\\aliases\\default",
				env.NVM_SYMLINK,
				env.NVM_HOME,
				"C:\\Program Files\\nodejs",
				"C:\\Program Files (x86)\\nodejs",
				env.APPDATA .. "\\npm",
				env.PNPM_HOME,
				env.LOCALAPPDATA .. "\\pnpm",
				env.APPDATA .. "\\pnpm",
				env.VOLTA_HOME and (env.VOLTA_HOME .. "\\bin"),
				env.LOCALAPPDATA .. "\\volta\\bin",
				env.USERPROFILE .. "\\.volta\\bin",
				env.USERPROFILE .. "\\scoop\\shims",
				env.USERPROFILE .. "\\scoop\\apps\\nodejs\\current",
				env.USERPROFILE .. "\\scoop\\apps\\nodejs-lts\\current",
				"C:\\ProgramData\\chocolatey\\bin",
				env.USERPROFILE .. "\\.bun\\bin",
				env.USERPROFILE .. "\\.deno\\bin",
				env.LOCALAPPDATA .. "\\Yarn\\bin",
				env.USERPROFILE .. "\\.cargo\\bin",
				env.USERPROFILE .. "\\go\\bin",
			}
		end,
		unix = function()
			local home = vim.fn.expand("~")
			return {
				"/data/data/com.termux/files/usr/bin",
				"/opt/homebrew/bin",
				"/usr/local/bin",
				home .. "/.local/share/fnm/current/bin",
				home .. "/.nvm/current/bin",
				home .. "/.local/share/pnpm",
				home .. "/.volta/bin",
				home .. "/.local/share/mise/shims",
				home .. "/.asdf/shims",
				home .. "/.bun/bin",
				home .. "/.deno/bin",
				home .. "/.cargo/bin",
				home .. "/go/bin",
				home .. "/.local/bin",
			}
		end,
	},
}

local is_windows = vim.fn.has("win32") == 1

-- ============================================================================
-- GLOBALS & FILETYPES
-- ============================================================================

for name, value in pairs(settings.disabled_globals) do
	vim.g[name] = value
end

vim.filetype.add({ extension = settings.filetypes })

for filetype, language in pairs(settings.syntax_aliases) do
	-- Treesitter needs the alias registered; `syntax` is the fallback highlighter.
	pcall(function()
		vim.treesitter.language.register(language, filetype)
	end)
	vim.api.nvim_create_autocmd("FileType", {
		pattern = filetype,
		callback = function()
			vim.bo.syntax = language
		end,
	})
end

-- ============================================================================
-- CLIPBOARD PROVIDER SETUP
-- ============================================================================

--- Configures a fallback clipboard provider (OSC 52 + Termux API) for environments
--- where X11/Wayland display servers are missing or broken (Termux, Ubuntu PRoot, SSH, headless).
local function setup_clipboard_provider()
	if vim.g.clipboard ~= nil then
		return
	end

	local env_ok, env_mod = pcall(require, "krs.core.environment")
	local env = env_ok and env_mod.detect() or {}
	local is_termux_or_proot = env.is_termux or env.is_proot or env.is_mobile
	local no_display = (vim.env.DISPLAY == nil or vim.env.DISPLAY == "")
		and (vim.env.WAYLAND_DISPLAY == nil or vim.env.WAYLAND_DISPLAY == "")

	if is_termux_or_proot or no_display then
		local osc52_ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")

		local termux_set = vim.fn.executable("termux-clipboard-set") == 1 and "termux-clipboard-set"
			or (
				(vim.uv or vim.loop).fs_stat("/data/data/com.termux/files/usr/bin/termux-clipboard-set")
				and "/data/data/com.termux/files/usr/bin/termux-clipboard-set"
			)
		local termux_get = vim.fn.executable("termux-clipboard-get") == 1 and "termux-clipboard-get"
			or (
				(vim.uv or vim.loop).fs_stat("/data/data/com.termux/files/usr/bin/termux-clipboard-get")
				and "/data/data/com.termux/files/usr/bin/termux-clipboard-get"
			)

		local has_termux_set = termux_set ~= nil
		local has_termux_get = termux_get ~= nil

		vim.g.clipboard = {
			name = "OSC 52 / Termux Clipboard",
			copy = {
				["+"] = function(lines, regtype)
					if has_termux_set then
						pcall(vim.fn.system, { termux_set }, table.concat(lines, "\n"))
					end
					if osc52_ok then
						osc52.copy("+")(lines, regtype)
					end
				end,
				["*"] = function(lines, regtype)
					if has_termux_set then
						pcall(vim.fn.system, { termux_set }, table.concat(lines, "\n"))
					end
					if osc52_ok then
						osc52.copy("*")(lines, regtype)
					end
				end,
			},
			paste = {
				["+"] = function()
					if osc52_ok then
						local osc_val = osc52.paste("+")()
						if type(osc_val) == "table" and #osc_val > 0 and osc_val[1] ~= "" then
							return osc_val
						end
					end
					if has_termux_get then
						local out = vim.fn.systemlist({ termux_get })
						if vim.v.shell_error == 0 and #out > 0 then
							return out, vim.fn.getregtype("+")
						end
					end
					return {}, "v"
				end,
				["*"] = function()
					if osc52_ok then
						local osc_val = osc52.paste("*")()
						if type(osc_val) == "table" and #osc_val > 0 and osc_val[1] ~= "" then
							return osc_val
						end
					end
					if has_termux_get then
						local out = vim.fn.systemlist({ termux_get })
						if vim.v.shell_error == 0 and #out > 0 then
							return out, vim.fn.getregtype("*")
						end
					end
					return {}, "v"
				end,
			},
		}
	end
end

setup_clipboard_provider()

-- ============================================================================
-- OPTIONS
-- ============================================================================

for name, value in pairs(settings.options) do
	vim.opt[name] = value
end

local env_ok_opt, env_mod_opt = pcall(require, "krs.core.environment")
if env_ok_opt then
	local env = env_mod_opt.detect()
	if env.is_mobile or env.is_termux or env.is_proot then
		-- ARM64 Tablet / Termux / PRoot MAXIMUM PERFORMANCE BOOST:
		-- 1. Disable Treesitter expr folding to eliminate keystroke latency & typing lag
		vim.opt.foldmethod = "manual"
		vim.opt.foldenable = false
		vim.opt.foldcolumn = "0"

		-- 2. Disable relative line number calculations on every cursor move
		vim.opt.relativenumber = false

		-- 3. Restrict cursorline to line number margin (prevents redrawing 80+ columns on j/k)
		pcall(function()
			vim.opt.cursorlineopt = "number"
		end)

		-- 4. Fast ShaDa history & regex max column limit
		vim.opt.synmaxcol = 200
		vim.opt.updatetime = 300
		vim.opt.timeoutlen = 300
		vim.opt.shada = "!,'50,<50,s10,h"
	end
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

-- Shell settings for Windows/Unix are applied via shell_settings.

-- ============================================================================
-- PATH REPAIR
-- ============================================================================

--- Prepends every existing toolchain directory to PATH, once per session.
--- `vim.g._path_setup_done` guards against a config reload doing it twice.
local function setup_path_env()
	if vim.g._path_setup_done then
		return
	end
	vim.g._path_setup_done = true

	local uv = vim.uv or vim.loop
	local separator = is_windows and ";" or ":"
	local current_path = vim.env.PATH or ""

	local env = {
		APPDATA = vim.env.APPDATA or "",
		LOCALAPPDATA = vim.env.LOCALAPPDATA or "",
		USERPROFILE = vim.env.USERPROFILE or "",
		NVM_SYMLINK = vim.env.NVM_SYMLINK,
		NVM_HOME = vim.env.NVM_HOME,
		PNPM_HOME = vim.env.PNPM_HOME,
		VOLTA_HOME = vim.env.VOLTA_HOME,
	}

	local candidates = is_windows and settings.path_candidates.windows(env) or settings.path_candidates.unix(env)

	local seen = {}
	local valid_paths = {}

	for _, candidate in pairs(candidates) do
		if type(candidate) == "string" and candidate ~= "" then
			local normalized = is_windows and candidate:gsub("/", "\\") or candidate
			if not seen[normalized] then
				seen[normalized] = true
				if not current_path:find(normalized, 1, true) then
					local stat = uv.fs_stat(normalized)
					if stat and stat.type == "directory" then
						table.insert(valid_paths, normalized)
					end
				end
			end
		end
	end

	if #valid_paths > 0 then
		vim.env.PATH = table.concat(valid_paths, separator) .. separator .. current_path
	end
end

setup_path_env()

-- Initialize per-language internal configurations (e.g. PHP Composer vendor bin)
require("krs.langs").setup()
