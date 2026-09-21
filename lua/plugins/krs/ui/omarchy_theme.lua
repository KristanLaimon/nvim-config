-- ============================================================================
-- KRS PLUGIN: Omarchy Theme Adapter & Dynamic Color Synchronization.
-- ============================================================================
-- WHAT IT DOES
--   Adapts Neovim's theme and syntax highlights to match Omarchy Linux
--   (Hyprland) desktop theme dynamically.
--   - Reads active theme from ~/.local/state/omarchy/current/theme.name
--   - Parses palette from ~/.local/state/omarchy/current/theme/colors.toml
--   - Translates into complete Nagatoro/NvChad highlights (editor, syntax, treesitter,
--     LSP, git, neo-tree, telescope, cmp kind badges)
--   - Auto-sync toggle in Command Palette (<C-S-p>) and :KrsOmarchySyncToggle
--   - Default state is disabled (false)
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

M.settings = {
	sync_data_file = vim.fn.stdpath("data") .. "/omarchy_sync.json",
	store_file = vim.fn.stdpath("config") .. "/.krsnvim/theme.json",
	omarchy_state_dir = vim.fn.expand("~/.local/state/omarchy/current"),
	omarchy_theme_name_file = vim.fn.expand("~/.local/state/omarchy/current/theme.name"),
	omarchy_colors_file = vim.fn.expand("~/.local/state/omarchy/current/theme/colors.toml"),
	omarchy_system_themes_dir = "/usr/share/omarchy/themes",
	omarchy_user_themes_dir = vim.fn.expand("~/.config/omarchy/themes"),
	default_fallback_theme = "nagatoro-krs",
	debounce_ms = 150,
}

M._watcher = nil
M._debounce_timer = nil
M._did_setup = false
M._last_applied_theme = nil

--- Checks whether Omarchy desktop environment is available.
--- Strictly gates out Windows, WSL, macOS, and Termux environments.
--- @return boolean available
function M.is_omarchy_available()
	local env_ok, env_mod = pcall(require, "krs.core.environment")
	if env_ok then
		local env = env_mod.detect()
		if env.is_windows or env.is_wsl or env.is_mac or env.is_termux then
			return false
		end
		if env.is_omarchy then
			return true
		end
	end

	-- Secondary guard for Windows, WSL, and macOS
	if vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1 or vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
		return false
	end

	local uv = vim.uv or vim.loop
	if uv.fs_stat(M.settings.omarchy_state_dir) or uv.fs_stat(M.settings.omarchy_system_themes_dir) then
		return true
	end
	return false
end

--- Gets the active Omarchy theme name.
--- @return string theme_name
function M.get_omarchy_theme_name()
	local f = io.open(M.settings.omarchy_theme_name_file, "r")
	if f then
		local content = f:read("*a")
		f:close()
		if content then
			content = content:gsub("^%s+", ""):gsub("%s+$", "")
			if #content > 0 then
				return content
			end
		end
	end

	if vim.fn.executable("omarchy") == 1 then
		local out = vim.fn.system({ "omarchy", "theme", "current" })
		if vim.v.shell_error == 0 and out and #out > 0 then
			return out:gsub("^%s+", ""):gsub("%s+$", "")
		end
	end

	return "Unknown"
end

--- Parses key = "value" pairs from a TOML string into a Lua table.
--- @param content string
--- @return table<string, string>
function M.parse_colors_toml(content)
	local colors = {}
	if not content or content == "" then
		return colors
	end
	for line in content:gmatch("[^\r\n]+") do
		local key, val = line:match("^%s*([%w_%-]+)%s*=%s*[\"']([^\"']+)[\"']")
		if key and val then
			colors[key] = val
		end
	end
	return colors
end

--- Retrieves current Omarchy theme colors from colors.toml.
--- @param theme_slug? string Optional theme slug override
--- @return table<string, string>|nil colors
function M.get_omarchy_colors(theme_slug)
	local colors_path = M.settings.omarchy_colors_file
	local uv = vim.uv or vim.loop

	if not uv.fs_stat(colors_path) and theme_slug then
		local slug = theme_slug:lower():gsub("%s+", "-")
		local user_path = M.settings.omarchy_user_themes_dir .. "/" .. slug .. "/colors.toml"
		local sys_path = M.settings.omarchy_system_themes_dir .. "/" .. slug .. "/colors.toml"
		if uv.fs_stat(user_path) then
			colors_path = user_path
		elseif uv.fs_stat(sys_path) then
			colors_path = sys_path
		end
	end

	local f = io.open(colors_path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return M.parse_colors_toml(content)
end

--- Translates raw Omarchy colors into Nagatoro/NvChad standardized palette `p`.
--- @param colors table<string, string>
--- @return table palette
function M.build_palette(colors)
	local is_dark = (colors.mode ~= "light")
	local p = {}

	if is_dark then
		p.bg = colors.background or "#1e1e2e"
		p.bg_dark = colors.dark_background or colors.darker_background or "#161622"
		p.bg_highlight = colors.lighter_background or "#313244"
		p.bg_selected = colors.selection or "#45475a"
		p.fg = colors.foreground or "#cdd6f4"
		p.fg_muted = colors.light_foreground or colors.dark_foreground or colors.muted or "#a6adc8"
		p.comment = colors.dark_foreground or colors.muted or "#6c7086"
	else
		p.bg = colors.background or "#FAFAFA"
		p.bg_dark = colors.dark_background or colors.darker_background or "#F0F0F0"
		p.bg_highlight = colors.lighter_background or "#EAEAEA"
		p.bg_selected = colors.selection or "#E2D0C6"
		p.fg = colors.foreground or "#2A2A2A"
		p.fg_muted = colors.light_foreground or colors.dark_foreground or colors.muted or "#666666"
		p.comment = colors.muted or colors.dark_foreground or "#7A8288"
	end

	p.keyword = colors.magenta or colors.blue or (is_dark and "#cba6f7" or "#4A5BB2")
	p.func = colors.blue or colors.yellow or (is_dark and "#89b4fa" or "#C28500")
	p.string = colors.green or (is_dark and "#a6e3a1" or "#456D8A")
	p.number = colors.orange or colors.yellow or (is_dark and "#fab387" or "#B34289")
	p.type = colors.yellow or colors.cyan or (is_dark and "#f9e2af" or "#299999")
	p.operator = colors.cyan or colors.green or (is_dark and "#94e2d5" or "#2E9931")
	p.declaration = colors.bright_magenta or colors.magenta or colors.accent or (is_dark and "#f5c2e7" or "#A81D80")
	p.accent = colors.accent or colors.blue or (is_dark and "#89b4fa" or "#C45B1E")
	p.error = colors.red or (is_dark and "#f38ba8" or "#D91E1E")
	p.warning = colors.yellow or (is_dark and "#f9e2af" or "#D9821E")
	p.none = "NONE"

	return p
end

--- Generates full highlight definitions dictionary from palette and mode.
--- @param p table
--- @param colors table
--- @return table<string, table>
function M.build_highlights(p, colors)
	local is_dark = (colors.mode ~= "light")
	local line_nr_fg = is_dark and (colors.muted or "#585b70") or (colors.muted or "#A0A0A0")
	local sep_fg = colors.darker_background or colors.dark_background or (is_dark and "#181825" or "#D0D0D0")

	return {
		-- Base Editor
		Normal = { fg = p.fg, bg = p.bg },
		NormalNC = { fg = p.fg, bg = p.bg },
		NormalFloat = { fg = p.fg, bg = p.bg_dark },
		FloatBorder = { fg = p.accent, bg = p.bg_dark },
		FloatTitle = { fg = p.accent, bg = p.bg_dark, bold = true },
		Cursor = { fg = p.bg, bg = p.accent },
		CursorLine = { bg = p.bg_highlight },
		CursorColumn = { bg = p.bg_highlight },
		ColorColumn = { bg = p.bg_dark },
		LineNr = { fg = line_nr_fg },
		CursorLineNr = { fg = p.accent, bold = true },
		VertSplit = { fg = sep_fg, bg = p.none },
		WinSeparator = { fg = sep_fg, bg = p.none },
		MatchParen = { fg = p.accent, bg = p.bg_selected, bold = true },

		-- Visual & Search
		Visual = { bg = p.bg_selected },
		VisualNOS = { bg = p.bg_selected },
		Search = { fg = p.fg, bg = p.bg_selected },
		IncSearch = { fg = p.bg, bg = p.accent, bold = true },
		CurSearch = { fg = p.bg, bg = p.accent, bold = true },

		-- Statusline & Tabline
		StatusLine = { fg = p.fg, bg = p.bg_dark },
		StatusLineNC = { fg = p.fg_muted, bg = p.bg_dark },
		TabLine = { fg = p.fg_muted, bg = p.bg_dark },
		TabLineFill = { bg = p.bg_dark },
		TabLineSel = { fg = p.accent, bg = p.bg, bold = true },

		-- Popup Menu
		Pmenu = { fg = p.fg, bg = p.bg_dark },
		PmenuSel = { fg = p.fg, bg = p.bg_selected, bold = true },
		PmenuSbar = { bg = p.bg_dark },
		PmenuThumb = { bg = p.accent },

		-- Standard Syntax Highlighting
		Comment = { fg = p.comment, italic = true },
		Constant = { fg = p.number },
		String = { fg = p.string },
		Character = { fg = p.string },
		Number = { fg = p.number },
		Boolean = { fg = p.keyword, bold = true },
		Float = { fg = p.number },

		Identifier = { fg = p.fg },
		Function = { fg = p.func, bold = true },
		Statement = { fg = p.keyword, bold = true },
		Conditional = { fg = p.keyword, bold = true },
		Repeat = { fg = p.keyword, bold = true },
		Label = { fg = p.keyword },
		Operator = { fg = p.operator },
		Keyword = { fg = p.keyword, bold = true },
		Exception = { fg = p.error, bold = true },

		PreProc = { fg = p.accent },
		Include = { fg = p.keyword },
		Define = { fg = p.keyword },
		Macro = { fg = p.keyword },

		Type = { fg = p.type, bold = true },
		StorageClass = { fg = p.keyword, bold = true },
		Structure = { fg = p.type },
		Typedef = { fg = p.type },

		Special = { fg = p.accent },
		SpecialChar = { fg = p.accent },
		Tag = { fg = p.operator },
		Delimiter = { fg = p.fg },
		SpecialComment = { fg = p.accent, italic = true },
		Debug = { fg = p.error },

		Underlined = { underline = true },
		Bold = { bold = true },
		Italic = { italic = true },
		Error = { fg = p.error, bold = true },
		Todo = { fg = p.bg, bg = p.accent, bold = true },

		-- Treesitter Captures
		["@comment"] = { fg = p.comment, italic = true },
		["@variable"] = { fg = p.fg },
		["@variable.builtin"] = { fg = p.keyword, italic = true },
		["@variable.parameter"] = { fg = p.string },
		["@function"] = { fg = p.func, bold = true },
		["@function.builtin"] = { fg = p.func, bold = true },
		["@function.call"] = { fg = p.func },
		["@function.method"] = { fg = p.func },
		["@function.method.call"] = { fg = p.func },
		["@keyword"] = { fg = p.keyword, bold = true },
		["@keyword.function"] = { fg = p.keyword, bold = true },
		["@keyword.return"] = { fg = p.keyword, bold = true },
		["@keyword.conditional"] = { fg = p.keyword, bold = true },
		["@keyword.repeat"] = { fg = p.keyword, bold = true },
		["@keyword.import"] = { fg = p.keyword, bold = true },
		["@keyword.operator"] = { fg = p.keyword },
		["@string"] = { fg = p.string },
		["@number"] = { fg = p.number },
		["@boolean"] = { fg = p.keyword, bold = true },
		["@type"] = { fg = p.type, bold = true },
		["@type.builtin"] = { fg = p.type, italic = true },
		["@property"] = { fg = p.fg, bold = true },
		["@operator"] = { fg = p.operator },
		["@punctuation.delimiter"] = { fg = p.fg },
		["@punctuation.bracket"] = { fg = p.fg },
		["@module"] = { fg = p.type },

		-- LSP Diagnostics
		DiagnosticError = { fg = p.error },
		DiagnosticWarn = { fg = p.warning },
		DiagnosticInfo = { fg = p.keyword },
		DiagnosticHint = { fg = p.type },
		DiagnosticUnderlineError = { underline = true, sp = p.error },
		DiagnosticUnderlineWarn = { underline = true, sp = p.warning },

		-- Git Signs & Diff
		GitSignsAdd = { fg = p.operator },
		GitSignsChange = { fg = p.warning },
		GitSignsDelete = { fg = p.error },
		DiffAdd = { bg = is_dark and "#132A13" or "#E6F4EA", fg = p.operator },
		DiffChange = { bg = is_dark and "#255926" or "#FEF7E0", fg = p.warning },
		DiffDelete = { bg = is_dark and "#3E1D1D" or "#FCE8E6", fg = p.error },

		-- Neo-Tree
		NeoTreeNormal = { fg = p.fg, bg = p.bg_dark },
		NeoTreeNormalNC = { fg = p.fg, bg = p.bg_dark },
		NeoTreeDirectoryName = { fg = p.accent, bold = true },
		NeoTreeDirectoryIcon = { fg = p.accent },
		NeoTreeFileName = { fg = p.fg },

		-- Telescope
		TelescopeNormal = { fg = p.fg, bg = p.bg_dark },
		TelescopeBorder = { fg = p.accent, bg = p.bg_dark },
		TelescopePromptBorder = { fg = p.accent, bg = p.bg_dark },
		TelescopePromptTitle = { fg = p.bg, bg = p.accent, bold = true },
		TelescopeResultsTitle = { fg = p.bg, bg = p.func, bold = true },
		TelescopePreviewTitle = { fg = p.bg, bg = p.operator, bold = true },
		TelescopeSelection = { fg = p.fg, bg = p.bg_selected, bold = true },

		-- NvChad Style Completion Kind Icon Highlights
		CmpKindBg_Function = { fg = p.bg, bg = p.func, bold = true },
		CmpKindBg_Method = { fg = p.bg, bg = p.func, bold = true },
		CmpKindBg_Constructor = { fg = p.bg, bg = p.func, bold = true },
		CmpKindBg_Snippet = { fg = is_dark and "#ffffff" or p.bg, bg = p.declaration, bold = true },
		CmpKindBg_Variable = { fg = p.bg, bg = p.number, bold = true },
		CmpKindBg_Constant = { fg = p.bg, bg = p.number, bold = true },
		CmpKindBg_Value = { fg = p.bg, bg = p.number, bold = true },
		CmpKindBg_Keyword = { fg = is_dark and "#ffffff" or p.bg, bg = p.keyword, bold = true },
		CmpKindBg_Statement = { fg = is_dark and "#ffffff" or p.bg, bg = p.keyword, bold = true },
		CmpKindBg_Class = { fg = p.bg, bg = p.type, bold = true },
		CmpKindBg_Interface = { fg = p.bg, bg = p.type, bold = true },
		CmpKindBg_Struct = { fg = p.bg, bg = p.type, bold = true },
		CmpKindBg_TypeParameter = { fg = p.bg, bg = p.type, bold = true },
		CmpKindBg_Enum = { fg = p.bg, bg = p.type, bold = true },
		CmpKindBg_Field = { fg = p.bg, bg = p.operator, bold = true },
		CmpKindBg_Property = { fg = p.bg, bg = p.operator, bold = true },
		CmpKindBg_Operator = { fg = p.bg, bg = p.operator, bold = true },
		CmpKindBg_Module = { fg = p.bg, bg = p.accent, bold = true },
		CmpKindBg_Folder = { fg = p.bg, bg = p.accent, bold = true },
		CmpKindBg_File = { fg = p.bg, bg = p.string, bold = true },
		CmpKindBg_Text = { fg = p.fg, bg = p.bg_highlight, bold = true },
		CmpKindBg_Color = { fg = p.bg, bg = p.type, bold = true },

		-- Standard CmpItemKind aliases
		CmpItemKindFunction = { fg = p.bg, bg = p.func, bold = true },
		CmpItemKindMethod = { fg = p.bg, bg = p.func, bold = true },
		CmpItemKindSnippet = { fg = is_dark and "#ffffff" or p.bg, bg = p.declaration, bold = true },
		CmpItemKindVariable = { fg = p.bg, bg = p.number, bold = true },
		CmpItemKindKeyword = { fg = is_dark and "#ffffff" or p.bg, bg = p.keyword, bold = true },
		CmpItemKindClass = { fg = p.bg, bg = p.type, bold = true },
		CmpItemKindField = { fg = p.bg, bg = p.operator, bold = true },
		CmpItemKindModule = { fg = p.bg, bg = p.accent, bold = true },
		-- Dashboard Alpha Header
		AlphaHeader = { fg = p.accent, bold = true },
		AlphaHeaderTheme = { fg = p.accent, bold = true },
		AlphaHeaderOrange = { fg = p.accent, bold = true },
	}
end

--- Applies current Omarchy theme to active Neovim session.
--- @param opts? { quiet?: boolean, force?: boolean }
--- @return boolean success, string theme_name
function M.apply_omarchy_theme(opts)
	opts = opts or {}
	local theme_name = M.get_omarchy_theme_name()
	local colors = M.get_omarchy_colors(theme_name)

	if not colors or not colors.background then
		if not opts.quiet then
			vim.notify("⚠️ Could not read Omarchy colors.toml for theme: " .. theme_name, vim.log.levels.WARN)
		end
		return false, theme_name
	end

	vim.cmd("highlight clear")
	if vim.fn.exists("syntax_on") == 1 then
		vim.cmd("syntax reset")
	end

	vim.o.background = colors.mode or "dark"
	vim.g.colors_name = "omarchy-krs"

	local p = M.build_palette(colors)
	local highlights = M.build_highlights(p, colors)

	for hl, spec in pairs(highlights) do
		vim.api.nvim_set_hl(0, hl, spec)
	end

	pcall(vim.cmd, "redrawstatus")
	M._last_applied_theme = theme_name
	pcall(vim.api.nvim_exec_autocmds, "ColorScheme", { modeline = false })

	if not opts.quiet then
		vim.notify(
			"🎨 Omarchy Theme applied: " .. theme_name .. " (" .. (colors.mode or "dark") .. ")",
			vim.log.levels.INFO
		)
	end

	return true, theme_name
end

--- Checks if Omarchy theme synchronization is enabled in store.
--- Checks if Omarchy theme synchronization is enabled in nvim data.
--- Default is false.
--- @return boolean enabled
function M.is_sync_enabled()
	local data = store.load(M.settings.sync_data_file, {})
	if data.enabled ~= nil then
		return data.enabled == true
	end
	-- Fallback to config store if data file doesn't exist yet
	local config_data = store.load(M.settings.store_file, {})
	return config_data.omarchy_sync == true
end

--- Enables or disables Omarchy theme synchronization.
--- @param enable boolean
--- @param opts? { quiet?: boolean, restore_theme?: boolean, new_theme?: string }
--- @return boolean success
function M.set_sync_enabled(enable, opts)
	opts = opts or {}
	if enable then
		if not M.is_omarchy_available() then
			vim.notify("⚠️ Omarchy Linux desktop was not detected on this system.", vim.log.levels.WARN)
			return false
		end

		-- Persist boolean in nvim data
		store.save(M.settings.sync_data_file, { enabled = true })

		-- Also update config theme.json for picker/backward compatibility
		local cfg = store.load(M.settings.store_file, {})
		local current = cfg.theme or vim.g.colors_name or M.settings.default_fallback_theme
		if current ~= "omarchy-krs" then
			cfg.previous_theme = current
		end
		cfg.theme = "omarchy-krs"
		cfg.omarchy_sync = true
		store.save(M.settings.store_file, cfg)

		M.start_watcher()
		local ok, name = M.apply_omarchy_theme({ quiet = opts.quiet == true })
		if not opts.quiet then
			if ok then
				vim.notify("🎨 Omarchy Theme Sync: ENABLED (Current: " .. name .. ")", vim.log.levels.INFO)
			else
				vim.notify("🎨 Omarchy Theme Sync: ENABLED (Theme: " .. name .. ")", vim.log.levels.INFO)
			end
		end
		return true
	else
		-- Persist boolean in nvim data
		store.save(M.settings.sync_data_file, { enabled = false })

		M.stop_watcher()

		local cfg = store.load(M.settings.store_file, {})
		cfg.omarchy_sync = false

		if opts.new_theme then
			cfg.theme = opts.new_theme
			store.save(M.settings.store_file, cfg)
			return true
		end

		if opts.restore_theme ~= false then
			local restored = cfg.previous_theme or M.settings.default_fallback_theme
			if restored == "omarchy-krs" then
				restored = M.settings.default_fallback_theme
			end
			cfg.theme = restored
			store.save(M.settings.store_file, cfg)
			pcall(vim.cmd.colorscheme, restored)
			if not opts.quiet then
				vim.notify("🎨 Omarchy Theme Sync: DISABLED (Restored: " .. restored .. ")", vim.log.levels.INFO)
			end
		else
			store.save(M.settings.store_file, cfg)
		end
		return true
	end
end

--- Toggles synchronization on/off.
--- @return boolean new_state
function M.toggle_sync()
	local current = M.is_sync_enabled()
	local new_state = not current
	M.set_sync_enabled(new_state)
	return new_state
end

--- Manually syncs active Neovim colors with Omarchy immediately and enables sync.
function M.sync_now()
	if not M.is_omarchy_available() then
		vim.notify("⚠️ Omarchy Linux desktop is not available.", vim.log.levels.WARN)
		return
	end
	M.set_sync_enabled(true)
end

--- Starts filesystem watcher and FocusGained autocmd to adapt dynamically on theme change.
function M.start_watcher()
	M.stop_watcher()

	local uv = vim.uv or vim.loop
	if uv.fs_stat(M.settings.omarchy_state_dir) then
		local ev = uv.new_fs_event()
		if ev then
			ev:start(
				M.settings.omarchy_state_dir,
				{},
				vim.schedule_wrap(function(err, fname, _)
					if err then
						return
					end
					if not fname or fname:match("theme") or fname:match("colors") or fname:match("background") then
						if M._debounce_timer then
							M._debounce_timer:stop()
							M._debounce_timer:close()
							M._debounce_timer = nil
						end
						M._debounce_timer = uv.new_timer()
						if M._debounce_timer then
							M._debounce_timer:start(
								M.settings.debounce_ms,
								0,
								vim.schedule_wrap(function()
									if M._debounce_timer then
										M._debounce_timer:stop()
										M._debounce_timer:close()
										M._debounce_timer = nil
									end
									if M.is_sync_enabled() then
										M.apply_omarchy_theme({ quiet = false })
									end
								end)
							)
						end
					end
				end)
			)
			M._watcher = ev
		end
	end

	local group = vim.api.nvim_create_augroup("krs_omarchy_theme_sync", { clear = true })
	vim.api.nvim_create_autocmd("FocusGained", {
		group = group,
		callback = function()
			if M.is_sync_enabled() then
				local cur = M.get_omarchy_theme_name()
				if cur ~= M._last_applied_theme then
					M.apply_omarchy_theme({ quiet = false })
				end
			end
		end,
	})
end

--- Stops watcher and clears autocommands.
function M.stop_watcher()
	if M._watcher then
		pcall(function()
			M._watcher:stop()
			M._watcher:close()
		end)
		M._watcher = nil
	end
	if M._debounce_timer then
		pcall(function()
			M._debounce_timer:stop()
			M._debounce_timer:close()
		end)
		M._debounce_timer = nil
	end
	pcall(vim.api.nvim_del_augroup_by_name, "krs_omarchy_theme_sync")
end

--- Initializes commands and starts watcher if enabled in settings.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("KrsOmarchySyncToggle", function()
		M.toggle_sync()
	end, { desc = "Toggle Omarchy theme synchronization (Default: OFF)" })

	vim.api.nvim_create_user_command("KrsOmarchySyncNow", function()
		M.sync_now()
	end, { desc = "Sync Neovim colors with Omarchy theme immediately" })

	vim.api.nvim_create_user_command("KrsOmarchySyncStatus", function()
		local enabled = M.is_sync_enabled()
		local theme = M.get_omarchy_theme_name()
		local status = enabled and "ENABLED (Auto-syncing with: " .. theme .. ")" or "DISABLED (Manual theme)"
		vim.notify("🎨 Omarchy Theme Sync: " .. status, vim.log.levels.INFO)
	end, { desc = "Show Omarchy theme synchronization status" })

	if M.is_sync_enabled() and M.is_omarchy_available() then
		M.apply_omarchy_theme({ quiet = true })
		M.start_watcher()
	end
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "krs_omarchy_theme",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = false,
	cmd = { "KrsOmarchySyncToggle", "KrsOmarchySyncNow", "KrsOmarchySyncStatus" },
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
