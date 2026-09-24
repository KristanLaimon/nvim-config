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

--- Formats active environment indicator for statusline when > 1 environments are active.
--- @return string env_info
function M.environment_status()
	if _G.Environments and _G.Environments.indicator_status then
		return _G.Environments.indicator_status()
	end
	local ok, envs = pcall(require, "plugins.krs.tools.environments")
	if ok and envs.indicator_status then
		return envs.indicator_status()
	end
	return ""
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

--- Cache for git branch resolution keyed by directory.
M._branch_cache = {}

--- Resolves the git branch of the given directory or current buffer accurately.
--- Never assumes "main" if not on main.
--- @param dir string|nil
--- @return string branch_name
function M.resolve_git_branch(dir)
	dir = dir or vim.fn.getcwd()
	if M._branch_cache[dir] then
		return M._branch_cache[dir]
	end

	local sep = package.config:sub(1, 1)
	local root = dir
	while root and root ~= "" do
		local git_path = root .. sep .. ".git"
		local stat = (vim.uv or vim.loop).fs_stat(git_path)
		if stat then
			local head_file = nil
			if stat.type == "directory" then
				head_file = git_path .. sep .. "HEAD"
			elseif stat.type == "file" then
				local f = io.open(git_path, "r")
				if f then
					local content = f:read("*l") or ""
					f:close()
					local gitdir = content:match("^gitdir:%s*(.+)$")
					if gitdir then
						if gitdir:sub(1, 1) ~= sep and not gitdir:match("^%a:") then
							gitdir = root .. sep .. gitdir
						end
						head_file = gitdir .. sep .. "HEAD"
					end
				end
			end

			if head_file then
				local hf = io.open(head_file, "r")
				if hf then
					local head = hf:read("*l") or ""
					hf:close()
					local branch = head:match("^ref: refs/heads/(.+)$")
					if branch and branch ~= "" then
						M._branch_cache[dir] = branch
						return branch
					end
					if #head >= 7 then
						local short_hash = head:sub(1, 7)
						M._branch_cache[dir] = short_hash
						return short_hash
					end
				end
			end

			-- Secondary git repos or reftable fallback
			local sec_ok, sec = pcall(require, "krs.git.secondary")
			if sec_ok and sec and sec.is_secondary_active and sec.is_secondary_active(root) then
				local sec_branch = sec.get_active_branch and sec.get_active_branch(root)
				if sec_branch and sec_branch ~= "" then
					M._branch_cache[dir] = sec_branch
					return sec_branch
				end
			end

			local out = vim.fn.systemlist({ "git", "-C", root, "branch", "--show-current" })
			if vim.v.shell_error == 0 and #out > 0 and out[1] ~= "" then
				M._branch_cache[dir] = out[1]
				return out[1]
			end
			local out_hash = vim.fn.systemlist({ "git", "-C", root, "rev-parse", "--short", "HEAD" })
			if vim.v.shell_error == 0 and #out_hash > 0 and out_hash[1] ~= "" then
				M._branch_cache[dir] = out_hash[1]
				return out_hash[1]
			end
			break
		end

		local parent = vim.fs.dirname(root)
		if not parent or parent == root then
			break
		end
		root = parent
	end

	M._branch_cache[dir] = ""
	return ""
end

--- Formats active git branch for statusline.
--- Accurately resolves active branch for file, terminal, or working directory.
--- @return string branch_name
function M.git_branch()
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return M.resolve_git_branch(vim.fn.getcwd())
	end

	local gitsigns_head = vim.b[buf] and vim.b[buf].gitsigns_head
	if gitsigns_head and gitsigns_head ~= "" then
		return gitsigns_head
	end

	local name = vim.api.nvim_buf_get_name(buf)
	if name and name:find("^term://") then
		local extracted = name:gsub("term://(.-)//.*", "%1")
		if extracted and extracted ~= "" and vim.fn.isdirectory(extracted) == 1 then
			return M.resolve_git_branch(extracted)
		end
	end

	if name and name ~= "" and vim.bo[buf].buftype == "" then
		local fdir = vim.fs.dirname(name)
		if fdir and fdir ~= "" and vim.fn.isdirectory(fdir) == 1 then
			return M.resolve_git_branch(fdir)
		end
	end

	return M.resolve_git_branch(vim.fn.getcwd())
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
				lualine_b = {
					M.fileformat_status,
					M.environment_status,
					{ M.git_branch, icon = "" },
					common_diff,
					common_diagnostics,
				},
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
				lualine_b = {
					M.fileformat_status,
					M.environment_status,
					{ M.git_branch, icon = "" },
					common_diff,
					common_diagnostics,
				},
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
				lualine_b = { M.fileformat_status, M.environment_status, { M.git_branch, icon = "" }, common_diagnostics },
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
				lualine_b = { M.fileformat_status, M.environment_status, common_filename },
				lualine_c = {},
				lualine_x = { M.python_status, { M.git_branch, icon = "" }, M.lsp_status },
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
				lualine_a = {
					M.fileformat_status,
					M.environment_status,
					{ M.git_branch, icon = "🌿" },
					common_diff,
					common_diagnostics,
				},
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
			lualine_b = {
				M.fileformat_status,
				M.environment_status,
				{ M.git_branch, icon = "" },
				common_diff,
				common_diagnostics,
			},
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

	local branch_group = vim.api.nvim_create_augroup("KrsStatuslineBranchWatcher", { clear = true })
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "BufEnter" }, {
		group = branch_group,
		callback = function(ev)
			if ev.event == "DirChanged" then
				M._branch_cache = {}
			end
			pcall(function()
				local lualine = package.loaded["lualine"]
				if lualine then
					lualine.refresh()
				end
			end)
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
