-- ============================================================================
-- KRS PLUGIN: Statusline Theme Picker & NvChad Statusline Engine.
-- ============================================================================
-- WHAT IT DOES
--   Provides NvChad-style statusline layouts (pills, blocks, classic, minimal,
--   vscode) and an interactive theme picker command `:KrsStatuslineTheme`.
-- ============================================================================

local store = require("krs.core.store")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.krsnvim/statusline.json",
	default_theme = "nvchad_pills",
}

M.available_themes = {
	nvchad_pills = "NvChad Pills (Rounded Statusline)",
	nvchad_blocks = "NvChad Blocks (Slanted Powerline)",
	nvchad_round = "NvChad Round (Curved Slants)",
	nagatoro_classic = "Nagatoro Classic (Minimal & Clean)",
	vscode = "VSCode Modern (Flat Bar)",
	minimal = "Minimalist (Compact)",
}

--- Formats active LSP clients into NvChad statusline string.
--- @return string lsp_info
function M.lsp_status()
	if not vim.lsp then
		return " No LSP"
	end
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	if not get_clients then
		return " No LSP"
	end
	local clients = get_clients({ bufnr = 0 })
	if not clients or #clients == 0 then
		return " No LSP"
	end
	local names = {}
	for _, client in ipairs(clients) do
		if client.name and client.name ~= "null-ls" and client.name ~= "copilot" then
			table.insert(names, client.name)
		end
	end
	if #names == 0 then
		return " Active"
	end
	return " " .. table.concat(names, ", ")
end

--- Formats editor mode into NvChad style pill string.
--- @param mode_str string
--- @return string formatted
function M.format_mode(mode_str)
	local modes = {
		["NORMAL"] = " NORMAL",
		["INSERT"] = "󰏫 INSERT",
		["VISUAL"] = "󰈈 VISUAL",
		["V-LINE"] = "󰈈 V-LINE",
		["V-BLOCK"] = "󰈈 V-BLOCK",
		["SELECT"] = "󰈈 SELECT",
		["S-LINE"] = "󰈈 S-LINE",
		["S-BLOCK"] = "󰈈 S-BLOCK",
		["REPLACE"] = "󰛔 REPLACE",
		["V-REPLACE"] = "󰛔 V-REPLACE",
		["COMMAND"] = "󰘳 COMMAND",
		["EX"] = "󰘳 EX",
		["MORE"] = "󰘳 MORE",
		["CONFIRM"] = "󰘳 CONFIRM",
		["SHELL"] = "󰞷 SHELL",
		["TERMINAL"] = "󰞷 TERMINAL",
	}
	return modes[mode_str] or (" " .. mode_str)
end

--- Extracts a clean, concise process title from vim.b.term_title or raw terminal URL.
--- @param str string Raw buffer name or term:// string
--- @return string|nil title
function M.get_term_title(str)
	local title = vim.b and vim.b.term_title
	if type(title) == "string" and title ~= "" and not title:find("^term://") then
		title = title:gsub("^Administrator:%s*", "")
		title = title:gsub("^Windows PowerShell", "powershell")
		if title:find("[/\\]") then
			title = vim.fn.fnamemodify(title, ":t")
		end
		title = title:gsub("%.[eE][xX][eE]$", "")
		title = vim.trim(title)
		if #title > 30 then
			title = title:sub(1, 27) .. "..."
		end
		if title ~= "" then
			return title
		end
	end

	if str then
		local shell_path = str:match("//%d+:(.*)$") or str:match(".*:(.*)$")
		if shell_path and shell_path ~= "" then
			shell_path = shell_path:gsub("\\", "/")
			local shell_name = vim.fn.fnamemodify(shell_path, ":t"):gsub("%.[eE][xX][eE]$", "")
			if shell_name ~= "" then
				return shell_name
			end
		end
	end

	return nil
end

--- Formats filename for statusline, simplifying raw terminal URLs (term://...) into clean labels.
--- @param str string
--- @return string formatted
function M.format_filename(str)
	if not str or str == "" then
		return "[No Name]"
	end

	local is_term = false
	if vim.bo and vim.bo.buftype == "terminal" then
		is_term = true
	elseif str:find("^term://") then
		is_term = true
	end

	if is_term then
		local title = M.get_term_title(str)

		if vim.b and vim.b.krs_task_name then
			if title and title ~= "" and title ~= vim.b.krs_task_name then
				return "🖥️ Task: " .. tostring(vim.b.krs_task_name) .. " - " .. title
			end
			return "🖥️ Task: " .. tostring(vim.b.krs_task_name)
		end

		if vim.b and vim.b.krs_term_num then
			local num = tostring(vim.b.krs_term_num)
			if title and title ~= "" then
				return "󰞷 Terminal #" .. num .. " - " .. title
			end
			return "󰞷 Terminal #" .. num
		end

		if title and title ~= "" then
			return "󰞷 Terminal (" .. title .. ")"
		end

		return "󰞷 Terminal"
	end

	return str
end

--- Formats current buffer line ending into a statusline label (LF / CRLF / CR).
--- @return string formatted
function M.fileformat_status()
	local fmt = vim.bo[vim.api.nvim_get_current_buf()].fileformat
	local map = { unix = "LF", dos = "CRLF", mac = "CR" }
	return "⏎ " .. (map[fmt] or fmt:upper())
end

--- Formats active Python interpreter version & env for statusline when editing Python files or when Python LSP is active.
--- @return string python_info
function M.python_status()
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return ""
	end
	local ft = vim.bo[buf].filetype
	local show = (ft == "python")
	if not show then
		local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
		local clients = get_clients and get_clients({ bufnr = buf }) or {}
		for _, c in ipairs(clients) do
			if c.name == "basedpyright" or c.name == "pyright" or c.name == "ruff" then
				show = true
				break
			end
		end
	end
	if not show then
		return ""
	end

	local ok, py = pcall(require, "krs.langs.python")
	if ok and py.python_status then
		return py.python_status()
	end
	return ""
end

--- Retrieves current statusline theme selection.
--- @return string theme_name
function M.get_current_theme()
	local data = store.load(M.settings.store_file, {})
	return data.theme or M.settings.default_theme
end

--- Generates Lualine options table for a given statusline theme.
--- @param theme_name string
--- @return table lualine_options
function M.get_lualine_config(theme_name)
	M.setup()
	theme_name = theme_name or M.get_current_theme()

	local common_diagnostics = {
		"diagnostics",
		symbols = { error = " ", warn = " ", info = "󰋼 ", hint = "󰌵 " },
	}

	local common_diff = {
		"diff",
		symbols = { added = " ", modified = "󰝤 ", removed = " " },
	}

	local common_filename = {
		"filename",
		file_status = true,
		path = 1,
		fmt = M.format_filename,
		symbols = { modified = " 󰏫", readonly = " 󰌾", unnamed = "[No Name]", newfile = "[New]" },
	}

	if theme_name == "nvchad_blocks" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				lualine_a = { { "mode", fmt = M.format_mode } },
				lualine_b = { M.fileformat_status, { "branch", icon = "" }, common_diff, common_diagnostics },
				lualine_c = { common_filename },
				lualine_x = { M.python_status, M.lsp_status, "filetype" },
				lualine_y = { "encoding", "fileformat" },
				lualine_z = { { "location", icon = "" }, "progress" },
			},
		}
	elseif theme_name == "nvchad_round" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				lualine_a = { { "mode", fmt = M.format_mode } },
				lualine_b = { M.fileformat_status, { "branch", icon = "" }, common_diff, common_diagnostics },
				lualine_c = { common_filename },
				lualine_x = { M.python_status, M.lsp_status, "filetype" },
				lualine_y = { "encoding" },
				lualine_z = { { "location", icon = "" }, "progress" },
			},
		}
	elseif theme_name == "vscode" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = { M.fileformat_status, { "branch", icon = "" }, common_diagnostics },
				lualine_c = { common_filename },
				lualine_x = { M.python_status, M.lsp_status, "filetype" },
				lualine_y = { "progress" },
				lualine_z = { "location" },
			},
		}
	elseif theme_name == "minimal" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = "",
				section_separators = "",
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = { M.fileformat_status, common_filename },
				lualine_c = {},
				lualine_x = { M.python_status, { "branch", icon = "" }, M.lsp_status },
				lualine_y = { "filetype" },
				lualine_z = { "location" },
			},
		}
	elseif theme_name == "nagatoro_classic" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
			},
			sections = {
				lualine_a = { M.fileformat_status, { "branch", icon = "🌿" }, common_diff, common_diagnostics },
				lualine_b = { common_filename },
				lualine_c = {},
				lualine_x = {
					{
						"mode",
						fmt = function(str)
							return "-- " .. str .. " --"
						end,
					},
					M.python_status,
					"encoding",
					"fileformat",
					"filetype",
				},
				lualine_y = { "progress" },
				lualine_z = { "location" },
			},
		}
	end

	-- Default: nvchad_pills
	return {
		options = {
			theme = "auto",
			globalstatus = true,
			component_separators = { left = "", right = "" },
			section_separators = { left = "", right = "" },
		},
		sections = {
			lualine_a = { { "mode", fmt = M.format_mode } },
			lualine_b = { M.fileformat_status, { "branch", icon = "" }, common_diff, common_diagnostics },
			lualine_c = { common_filename },
			lualine_x = { M.python_status, M.lsp_status, "filetype" },
			lualine_y = { "encoding" },
			lualine_z = { { "location", icon = "" }, "progress" },
		},
	}
end

--- Sets active statusline theme and applies configuration.
--- @param theme_name string
function M.set_theme(theme_name)
	if not M.available_themes[theme_name] then
		vim.notify("Unknown statusline theme: " .. tostring(theme_name), vim.log.levels.WARN)
		return
	end

	store.save(M.settings.store_file, { theme = theme_name })
	local has_lualine, lualine = pcall(require, "lualine")
	if has_lualine then
		lualine.setup(M.get_lualine_config(theme_name))
	end
	vim.notify("Statusline theme set to: " .. M.available_themes[theme_name], vim.log.levels.INFO)
end

--- Opens interactive statusline theme picker.
function M.open_picker()
	local items = {}
	local keys = {}
	for k, label in pairs(M.available_themes) do
		table.insert(keys, k)
		table.insert(items, label .. " (" .. k .. ")")
	end

	vim.ui.select(items, { prompt = "Select Statusline Theme:" }, function(choice, index)
		if choice and index then
			M.set_theme(keys[index])
		end
	end)
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup("KrsStatuslineTermTitle", { clear = true })
	vim.api.nvim_create_autocmd({ "TermOpen", "TermClose", "TermRequest", "TermEnter", "TermLeave" }, {
		group = group,
		callback = function()
			vim.cmd("redrawstatus")
		end,
	})

	vim.api.nvim_create_user_command("KrsStatuslineTheme", function(opts)
		if opts.args and opts.args ~= "" then
			M.set_theme(opts.args)
		else
			M.open_picker()
		end
	end, {
		nargs = "?",
		complete = function()
			local names = {}
			for k in pairs(M.available_themes) do
				table.insert(names, k)
			end
			return names
		end,
		desc = "Pick or set statusline theme",
	})
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "krs_statusline_picker",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = "KrsStatuslineTheme",
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
