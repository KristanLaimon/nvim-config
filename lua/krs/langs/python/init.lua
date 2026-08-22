-- ============================================================================
-- KRS PYTHON: Centralized Python Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard PEP 8 4-space indentation defaults for Python buffers when no
--   .editorconfig file specifies buffer settings. Also owns the pyright LSP
--   server, the debugpy DAP adapter, and the `python` launch-profile runtime.
-- ============================================================================

---@type KrsLangModule
local M = {}

local _version_cache = {}
local _version_pending = {}
local _interpreter_cache = {}
local _active_interpreter = nil

--- Resolves the active Python interpreter path for the project/buffer.
--- @param bufnr integer|nil
--- @return string interpreter_path
function M.get_python_interpreter(bufnr)
	local cwd = vim.fn.getcwd()
	if _interpreter_cache[cwd] and _interpreter_cache[cwd] ~= "" then
		local cached = _interpreter_cache[cwd]
		if cached == "python" or cached == "python3" or vim.fn.executable(cached) == 1 then
			return cached
		end
	end

	-- 1. Check vscode_settings or .vscode/settings.json / .krsnvim/settings.json
	local ok_vsc, vsc = pcall(require, "plugins.krs.vscode_settings")
	if ok_vsc then
		local _, settings = vsc.load_settings()
		if settings then
			local py_path = settings["python.defaultInterpreterPath"] or settings["python.pythonPath"]
			if type(py_path) == "string" and py_path ~= "" and vim.fn.executable(py_path) == 1 then
				_interpreter_cache[cwd] = py_path
				_active_interpreter = py_path
				return py_path
			end
		end
	end

	-- 2. Check vim.g.python3_host_prog
	if vim.g.python3_host_prog and vim.g.python3_host_prog ~= "" and vim.fn.executable(vim.g.python3_host_prog) == 1 then
		_interpreter_cache[cwd] = vim.g.python3_host_prog
		_active_interpreter = vim.g.python3_host_prog
		return vim.g.python3_host_prog
	end

	-- 3. Check attached LSP clients (basedpyright / pyright)
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	if get_clients then
		local clients = get_clients({ bufnr = bufnr or 0 })
		for _, client in ipairs(clients or {}) do
			if client.name == "basedpyright" or client.name == "pyright" then
				local py = vim.tbl_get(client.config, "settings", "python", "pythonPath")
					or vim.tbl_get(client.config, "settings", "basedpyright", "pythonPath")
				if type(py) == "string" and py ~= "" and vim.fn.executable(py) == 1 then
					_interpreter_cache[cwd] = py
					_active_interpreter = py
					return py
				end
			end
		end
	end

	-- 4. Check workspace virtualenvs
	for _, candidate in ipairs({
		"/venv/Scripts/python.exe",
		"/.venv/Scripts/python.exe",
		"/env/Scripts/python.exe",
		"/.env/Scripts/python.exe",
		"/venv/bin/python",
		"/.venv/bin/python",
		"/env/bin/python",
		"/.env/bin/python",
	}) do
		local full = cwd .. candidate
		if vim.fn.executable(full) == 1 then
			_interpreter_cache[cwd] = full
			_active_interpreter = full
			return full
		end
	end

	-- 5. Fallback to system python
	local fallback = "python"
	if vim.fn.executable("python3") == 1 then
		fallback = "python3"
	end
	_interpreter_cache[cwd] = fallback
	_active_interpreter = fallback
	return fallback
end

--- Retrieves cached or fresh Python version string (e.g. "3.12.2")
--- Non-blocking: background async version check prevents UI stalls on startup/file load.
--- @param exec_path string|nil
--- @return string version
function M.get_python_version(exec_path)
	exec_path = exec_path or M.get_python_interpreter()
	if _version_cache[exec_path] then
		return _version_cache[exec_path]
	end

	if not _version_pending[exec_path] then
		_version_pending[exec_path] = true
		if vim.system then
			vim.system({ exec_path, "--version" }, { text = true }, function(obj)
				_version_pending[exec_path] = nil
				local out = (obj and (obj.stdout or obj.stderr)) or ""
				local ver = out:match("Python%s+([%d%.]+)") or out:match("([%d%.]+)") or "3.x"
				_version_cache[exec_path] = ver
				vim.schedule(function()
					pcall(vim.cmd, "redrawstatus")
				end)
			end)
		else
			local out = vim.fn.system({ exec_path, "--version" })
			local ver = out:match("Python%s+([%d%.]+)") or out:match("([%d%.]+)") or "3.x"
			_version_cache[exec_path] = ver
			_version_pending[exec_path] = nil
		end
	end

	return "3.x"
end

--- Formats statusline string for Python environment.
--- Returns e.g. " 3.12.2 (.venv)" or " 3.11.4 (System)"
--- @return string status
function M.python_status()
	local interpreter = M.get_python_interpreter()
	local ver = M.get_python_version(interpreter)

	local env_label = "System"
	local norm = interpreter:lower():gsub("\\", "/")
	if norm:find("/%.venv/") or norm:find("%%2e.venv") then
		env_label = ".venv"
	elseif norm:find("/venv/") then
		env_label = "venv"
	elseif norm:find("/%.env/") then
		env_label = ".env"
	elseif norm:find("/env/") then
		env_label = "env"
	elseif norm:find("conda") or norm:find("anaconda") then
		env_label = "conda"
	elseif norm:find("pyenv") then
		env_label = "pyenv"
	elseif norm:find("poetry") then
		env_label = "poetry"
	end

	return " " .. ver .. " (" .. env_label .. ")"
end

--- Scans workspace and system for available Python interpreters.
--- @return table[] candidates List of { label = string, path = string, env = string }
function M.find_interpreter_candidates()
	local cwd = vim.fn.getcwd()
	local candidates = {}
	local seen = {}

	local function add_candidate(path_str, env_type)
		if not path_str or path_str == "" or seen[path_str] then
			return
		end
		if vim.fn.executable(path_str) == 1 then
			seen[path_str] = true
			local ver = M.get_python_version(path_str)
			table.insert(candidates, {
				label = env_type .. " (" .. ver .. ") — " .. path_str,
				path = path_str,
				env = env_type,
				ver = ver,
			})
		end
	end

	-- 1. Virtualenvs in cwd
	local venv_patterns = {
		{ "/.venv/Scripts/python.exe", ".venv (Project)" },
		{ "/venv/Scripts/python.exe", "venv (Project)" },
		{ "/.env/Scripts/python.exe", ".env (Project)" },
		{ "/env/Scripts/python.exe", "env (Project)" },
		{ "/.venv/bin/python", ".venv (Project)" },
		{ "/venv/bin/python", "venv (Project)" },
		{ "/.env/bin/python", ".env (Project)" },
		{ "/env/bin/python", "env (Project)" },
	}
	for _, item in ipairs(venv_patterns) do
		add_candidate(cwd .. item[1], item[2])
	end

	-- 2. Check CONDA_PREFIX
	local conda_prefix = os.getenv("CONDA_PREFIX")
	if conda_prefix then
		add_candidate(conda_prefix .. "/Scripts/python.exe", "Conda (" .. (os.getenv("CONDA_DEFAULT_ENV") or "env") .. ")")
		add_candidate(conda_prefix .. "/bin/python", "Conda (" .. (os.getenv("CONDA_DEFAULT_ENV") or "env") .. ")")
	end

	-- 3. Check pyenv
	local pyenv_root = os.getenv("PYENV_ROOT") or (os.getenv("USERPROFILE") and (os.getenv("USERPROFILE") .. "/.pyenv"))
	if pyenv_root and vim.fn.isdirectory(pyenv_root) == 1 then
		add_candidate(pyenv_root .. "/shims/python", "Pyenv Shim")
	end

	-- 4. Check system python on PATH
	if vim.fn.has("win32") == 1 then
		local sys_py = vim.fn.exepath("python.exe")
		if sys_py and sys_py ~= "" then
			add_candidate(sys_py, "System Global (python.exe)")
		end
		local sys_py3 = vim.fn.exepath("python3.exe")
		if sys_py3 and sys_py3 ~= "" then
			add_candidate(sys_py3, "System Global (python3.exe)")
		end
	else
		local sys_py = vim.fn.exepath("python3") or vim.fn.exepath("python")
		if sys_py and sys_py ~= "" then
			add_candidate(sys_py, "System Global")
		end
	end

	return candidates
end

--- Sets the active Python interpreter path across LSP, VSCode settings, and statusline.
--- @param new_path string
function M.set_interpreter(new_path)
	if not new_path or new_path == "" or vim.fn.executable(new_path) ~= 1 then
		vim.notify("Invalid or non-executable Python path: " .. tostring(new_path), vim.log.levels.ERROR, { title = "Python Interpreter" })
		return
	end

	_active_interpreter = new_path
	vim.g.python3_host_prog = new_path

	-- 1. Save to .vscode/settings.json or .krsnvim/settings.json
	local root = vim.fn.getcwd()
	_interpreter_cache[root] = new_path
	local vscode_dir = root .. "/.vscode"
	local vscode_settings_file = vscode_dir .. "/settings.json"
	vim.fn.mkdir(vscode_dir, "p")

	local settings = {}
	if vim.fn.filereadable(vscode_settings_file) == 1 then
		local raw = io.open(vscode_settings_file, "r"):read("*a")
		local clean = raw:gsub("/%*.-%*/", ""):gsub("//[^\r\n]*", "")
		local ok, decoded = pcall(vim.json.decode, clean)
		if ok and type(decoded) == "table" then
			settings = decoded
		end
	end

	settings["python.defaultInterpreterPath"] = new_path
	settings["python.pythonPath"] = new_path

	local f = io.open(vscode_settings_file, "w")
	if f then
		f:write(vim.json.encode(settings))
		f:close()
	end

	-- 2. Update active basedpyright / pyright / ruff LSP clients
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	if get_clients then
		for _, client in ipairs(get_clients()) do
			if client.name == "basedpyright" or client.name == "pyright" then
				client.config.settings = client.config.settings or {}
				client.config.settings.python = client.config.settings.python or {}
				client.config.settings.python.pythonPath = new_path
				if client.config.settings.basedpyright then
					client.config.settings.basedpyright.pythonPath = new_path
				end
				pcall(client.notify, "workspace/didChangeConfiguration", { settings = client.config.settings })
			end
		end
	end

	-- 3. Redraw statusline
	vim.cmd("redrawstatus")
	local ver = M.get_python_version(new_path)
	vim.notify("Python interpreter set to: " .. new_path .. " (" .. ver .. ")", vim.log.levels.INFO, { title = "Python Interpreter" })
end

--- Interactive UI picker for selecting Python interpreter (like VSCode "Python: Select Interpreter").
function M.select_interpreter()
	local candidates = M.find_interpreter_candidates()
	local items = {}
	for _, c in ipairs(candidates) do
		table.insert(items, "🐍 " .. c.label)
	end
	table.insert(items, "✏️ Enter custom path...")

	vim.ui.select(items, { prompt = "🐍 Select Python Interpreter:" }, function(choice, idx)
		if not choice or not idx then
			return
		end

		if idx <= #candidates then
			M.set_interpreter(candidates[idx].path)
		else
			vim.ui.input({ prompt = "Enter full path to python executable:" }, function(input)
				if input and input ~= "" then
					M.set_interpreter(vim.trim(input))
				end
			end)
		end
	end)
end

--- The lspconfig/mason server name(s) this language owns. basedpyright: types,
--- hover, go-to-def, inlay hints. ruff: lint + import-sort diagnostics/code
--- actions (its formatting runs through conform below, not the LSP formatter capability).
M.lsp_server = { "basedpyright", "ruff" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	basedpyright = {
		before_init = function(_, config)
			config.settings = config.settings or {}
			config.settings.python = config.settings.python or {}
			config.settings.python.pythonPath = M.get_python_interpreter()
		end,
		settings = {
			basedpyright = {
				analysis = {
					typeCheckingMode = "strict",
					autoImportCompletions = true,
					inlayHints = {
						variableTypes = true,
						functionReturnTypes = true,
						callArgumentNames = true,
						pytestParameters = true,
						genericTypes = true,
					},
				},
			},
		},
	},
	ruff = {},
}

--- Filetypes the DAP configurations below attach to.
M.dap_filetypes = { "python" }

--- Static nvim-dap configurations, appended by lua/plugins/editor/dap.lua.
M.dap_configs = {
	{
		type = "python",
		request = "launch",
		name = "Launch Current File (Python)",
		program = "${file}",
		cwd = "${workspaceFolder}",
		console = "integratedTerminal",
		pythonPath = function()
			return M.get_python_interpreter()
		end,
	},
}

--- Mason package metadata, keyed by tool name.
M.mason = {
	basedpyright = { mason = "basedpyright", lang = "Python", type = "lsp", cmd = "basedpyright-langserver" },
	ruff = { mason = "ruff", lang = "Python (Ruff)", type = "lsp", cmd = "ruff" },
	debugpy = { mason = "debugpy", lang = "Python Debugger", type = "dap", cmd = "debugpy-adapter" },
}

M.mason_order = { "basedpyright", "ruff", "debugpy" }

--- conform.nvim formatter list per filetype: ruff sorts imports then formats
--- (Black-compatible), in one already-installed tool.
M.formatters_by_ft = {
	python = { "ruff_fix", "ruff_format" },
}

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "🐍 Python"
M.requires = {
	{ cmd = "python3", name = "Python 3", alt = "python", hint = "https://python.org" },
}
M.treesitter = { "python" }

--- Launch-profile runtimes this language owns (see lua/krs/launch/runtimes.lua).
M.launch_runtimes = {
	python = {
		command = "python",
		dap = function(profile, root, ctx)
			return {
				type = "python",
				request = "launch",
				name = profile.name,
				program = ctx.full_entry,
				cwd = root,
				console = "integratedTerminal",
			}
		end,
	},
}

--- Standard PEP 8 defaults for Python (4 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 4,
	autoindent = true,
}

--- Apply Python language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Python language configuration autocmds and user commands.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "python" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})

	vim.api.nvim_create_user_command("PythonSelectInterpreter", function()
		M.select_interpreter()
	end, { desc = "Select Python Interpreter (Virtualenv / System)" })

	vim.api.nvim_create_user_command("KrsPythonSelectInterpreter", function()
		M.select_interpreter()
	end, { desc = "Select Python Interpreter (Virtualenv / System)" })
end

return M
