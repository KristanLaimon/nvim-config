-- ============================================================================
-- PLUGINS: Starter Dashboard (alpha-nvim) with Environment Detection & Responsive Banners
-- ============================================================================

local env_lib = require("krs.core.environment")

local settings = {
	--- Colour of the ASCII banner. Re-applied on every colorscheme change.
	header_highlight = { name = "AlphaHeaderOrange", opts = { fg = "#FF8800", bold = true } },

	--- Menu entries, in order: { key, icon, label, command }.
	buttons = {
		{ "f", "📁", "File Explorer", ":TelescopeFileBrowserDesktop<CR>" },
		{ "p", "💼", "Recent projects", ":RecentProjects<CR>" },
		{ "s", "📦", "Dependencies & Toolchains", ":KrsInstallDependencies<CR>" },
		{ "h", "🩺", "Health Check", ":KrsHealthCheck<CR>" },
		{ "w", "📚", "Wiki & Docs (Ctrl+Shift+D)", ":KrsWiki<CR>" },
		{ "e", "🧩", "Plugins & Extensions", ":Lazy<CR>" },
		{ "m", "⚙️", "Server Manager (Mason)", ":Mason<CR>" },
		{ "q", "🚪", "Quit", ":qa<CR>" },
	},

	--- WSL entry, inserted at this position when WSL is available.
	wsl_button = { "l", "🐧", "File Explorer (WSL)", ":TelescopeFileBrowserWSL<CR>" },
	wsl_button_position = 4,

	--- Filetypes that must never be replaced by the dashboard.
	protected_filetypes = { "alpha", "neo-tree" },
}

return {
	"goolord/alpha-nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")
		local env = env_lib.detect()

		--- Determines the visible width of the dashboard window, accounting for Neo-tree width.
		local function get_dashboard_width()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_is_valid(win) then
					local cfg = vim.api.nvim_win_get_config(win)
					local is_float = cfg and cfg.relative and cfg.relative ~= ""
					if not is_float then
						local buf = vim.api.nvim_win_get_buf(win)
						if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "alpha" then
							return vim.api.nvim_win_get_width(win)
						end
					end
				end
			end

			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_is_valid(win) then
					local buf = vim.api.nvim_win_get_buf(win)
					if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "neo-tree" then
						local nw = vim.api.nvim_win_get_width(win)
						return math.max(20, (vim.o.columns or 80) - nw - 1)
					end
				end
			end

			return vim.o.columns or 80
		end

		--- Returns an ASCII banner adapted to the current dashboard window width & environment.
		--- @param target_width integer|nil
		local function get_responsive_header(target_width)
			local width = target_width or get_dashboard_width()
			if width < 55 or env.is_mobile then
				return {
					[[        K R S V I M        ]],
					[[ "Foxes can be coders too!"]],
					"      [ " .. env.label .. " ]",
				}
			elseif width < 100 then
				return {
					[[  _  ______  ______     _____ __  __  ]],
					[[ | |/ /  _ \/ ___/\ \  / /_ _|  \/  | ]],
					[[ | ' /| |_) \___ \ \ \/ / | || |\/| | ]],
					[[ | . \|  _ < ___) | \  /  | || |  | | ]],
					[[ |_|\_\_| \_\____/   \/  |___|_|  |_| ]],
					[[]],
					[[        "Foxes can be coders too!"    ]],
					"     📱 Environment: " .. env.label,
				}
			else
				return {
					[[       ___           ___           ___           ___           ___                       ___     ]],
					[[     /\__\         /\  \         /\  \         /\__\         /\__\          ___        /\__\    ]],
					[[    /:/  /        /::\  \       /::\  \       /::|  |       /:/  /         /\  \      /::|  |   ]],
					[[   /:/__/        /:/\:\  \     /:/\ \  \     /:|:|  |      /:/  /          \:\  \    /:|:|  |   ]],
					[[  /::\__\____   /::\~\:\  \   _\:\~\ \  \   /:/|:|  |__   /:/__/  ___      /::\__\  /:/|:|__|__ ]],
					[[ /:/\:::::\__\ /:/\:\ \:\__\ /\ \:\ \ \__\ /:/ |:| /\__\  |:|  | /\__\  __/:/\/__/ /:/ |::::\__\ ]],
					[[ \/_|:|~~|~    \/_|::\/:/  / \:\ \:\ \/__/ \/__|:|/:/  /  |:|  |/:/  / /\/:/  /    \/__/~~/:/  / ]],
					[[    |:|  |        |:|::/  /   \:\ \:\__\       |:/:/  /   |:|__/:/  /  \::/__/           /:/  /  ]],
					[[    |:|  |        |:|\/__/     \:\/:/  /       |::/  /     \::::/__/    \:\__\          /:/  /   ]],
					[[    |:|  |        |:|  |        \::/  /        /:/  /       ~~~~         \/__/         /:/  /    ]],
					[[     \|__|         \|__|         \/__/         \/__/                                   \/__/     ]],
					[[]],
					[[]],
					[[]],
					[[                       "Foxes can be coders too!" - A random fox                                 ]],
					"                              💻 Environment: " .. env.label,
				}
			end
		end

		dashboard.section.header.val = get_responsive_header()

		--- Determines the visible height of the dashboard window.
		local function get_dashboard_height()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_is_valid(win) then
					local cfg = vim.api.nvim_win_get_config(win)
					local is_float = cfg and cfg.relative and cfg.relative ~= ""
					if not is_float then
						local buf = vim.api.nvim_win_get_buf(win)
						if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "alpha" then
							return vim.api.nvim_win_get_height(win)
						end
					end
				end
			end
			return vim.o.lines or 24
		end

		--- Calculates top padding lines so the dashboard content is centered vertically in the window.
		local function get_vertical_padding()
			local win_height = get_dashboard_height()

			local header_lines = 0
			local h_val = dashboard.section.header.val
			if type(h_val) == "function" then
				local res = h_val()
				header_lines = type(res) == "table" and #res or 1
			elseif type(h_val) == "table" then
				header_lines = #h_val
			end

			local btn_count = (type(dashboard.section.buttons.val) == "table" and #dashboard.section.buttons.val) or 0
			local spacing = (dashboard.section.buttons.opts and dashboard.section.buttons.opts.spacing) or 1
			local btn_lines = btn_count > 0 and (btn_count + (btn_count - 1) * spacing) or 0

			local footer_lines = (
				dashboard.section.footer
				and dashboard.section.footer.val
				and dashboard.section.footer.val ~= ""
			)
					and 1
				or 0
			local middle_padding = 2
			local footer_padding = footer_lines > 0 and 1 or 0

			local content_height = header_lines + middle_padding + btn_lines + footer_padding + footer_lines
			local pad = math.floor((win_height - content_height) / 2)
			return math.max(1, pad)
		end

		-- Set vertical centering dynamic padding on the top layout element
		if dashboard.opts and dashboard.opts.layout and dashboard.opts.layout[1] then
			dashboard.opts.layout[1].val = get_vertical_padding
		end

		local function refresh_dashboard()
			dashboard.section.header.val = get_responsive_header()
			pcall(alpha.redraw)
		end

		_G.Alpha_Refresh_Header = refresh_dashboard

		-- Dynamic header update on window resize (e.g. rotating phone screen or resizing split / neo-tree width)
		vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
			group = vim.api.nvim_create_augroup("AlphaResponsiveHeader", { clear = true }),
			callback = function()
				vim.schedule(refresh_dashboard)
			end,
		})

		vim.api.nvim_create_autocmd("BufWinEnter", {
			group = "AlphaResponsiveHeader",
			callback = function(ctx)
				local buf = ctx.buf
				if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "alpha" then
					vim.schedule(refresh_dashboard)
				end
			end,
		})

		-- `:colorscheme` clears user-defined groups, so the banner colour is
		-- re-applied whenever the theme changes, adapting to the active theme accent.
		local function set_header_highlight()
			local hl = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false })
			local fg = hl and hl.fg
			if not fg then
				local cur_hl = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
				fg = cur_hl and cur_hl.fg
			end
			local opts = { fg = fg or "#d2824e", bold = true }
			vim.api.nvim_set_hl(0, "AlphaHeaderTheme", opts)
			vim.api.nvim_set_hl(0, settings.header_highlight.name, opts)
		end
		set_header_highlight()
		vim.api.nvim_create_autocmd("ColorScheme", { callback = set_header_highlight })
		dashboard.section.header.opts.hl = "AlphaHeaderTheme"

		--- Turns a settings entry into an alpha button.
		--- @param entry table `{ key, icon, label, command }`
		local function make_button(entry)
			local icon = entry[2] ~= "" and (entry[2] .. "  ") or ""
			return dashboard.button(entry[1], icon .. entry[3], entry[4])
		end

		dashboard.section.buttons.val = vim.tbl_map(make_button, settings.buttons)

		-- The WSL entry would be a dead end on a machine without WSL.
		local ok_wsl, wsl = pcall(require, "plugins.krs.tools.wsl")
		if ok_wsl and wsl.available() then
			table.insert(dashboard.section.buttons.val, settings.wsl_button_position, make_button(settings.wsl_button))
		end

		dashboard.section.footer.val = "⚡ KRS Neovim (" .. env.label .. ")"

		-- alpha redraws on WinResized, which fires while a window is already gone
		-- (closing a split or the explorer) and then throws "invalid window id".
		-- Wrapping both entry points keeps that out of the message history.
		for _, name in ipairs({ "redraw", "draw" }) do
			local original = alpha[name]
			alpha[name] = function(...)
				return pcall(original, ...)
			end
		end

		alpha.setup(dashboard.opts)

		vim.api.nvim_create_autocmd("VimEnter", {
			callback = function()
				if vim.fn.argc() == 0 then
					vim.schedule(function()
						if vim.bo.filetype ~= "alpha" then
							vim.cmd("Alpha")
						end
					end)
				end
			end,
		})

		local function show_dashboard()
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].filetype ~= "neo-tree" and vim.bo[buf].buftype ~= "terminal" then
					if vim.bo[buf].filetype == "alpha" then
						return
					end
					vim.api.nvim_win_call(win, function()
						vim.cmd("Alpha")
					end)
					return
				end
			end

			-- If we reach here, there are no normal code windows, only neo-tree or terminals.
			-- Find neo-tree and split it to the right, so we don't accidentally split the terminal dock.
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].filetype == "neo-tree" then
					vim.api.nvim_win_call(win, function()
						vim.cmd("rightbelow vsplit | Alpha")
					end)
					return
				end
			end

			-- Fallback if not even neo-tree exists
			vim.cmd("vsplit | Alpha")
		end

		local function has_pins()
			local ok, pinned_tabs = pcall(require, "plugins.krs.ui.pinned_tabs")
			return ok and #pinned_tabs.load_pins() > 0
		end

		-- Closing the last real buffer shows the dashboard instead of quitting.
		vim.api.nvim_create_autocmd("BufDelete", {
			callback = function()
				vim.schedule(function()
					local listed = vim.tbl_filter(function(b)
						return vim.fn.buflisted(b) == 1 and vim.api.nvim_buf_get_name(b) ~= ""
					end, vim.api.nvim_list_bufs())

					if #listed == 0 and not has_pins() then
						show_dashboard()
					end
				end)
			end,
		})
	end,
}
