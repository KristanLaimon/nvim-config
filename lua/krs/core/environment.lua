-- ============================================================================
-- KRS ENVIRONMENT DETECTOR
-- ============================================================================
-- Detects execution environment layers (TMUX, Termux, Ubuntu PRoot, WSL, Linux, macOS, Windows)
-- ============================================================================

local M = {}

--- Detects active execution environment layers.
--- @return table env `{ is_tmux, is_termux, is_proot, is_ubuntu, is_wsl, is_windows, is_mac, is_linux, is_mobile, label }`
function M.detect()
	local env = {
		is_tmux = vim.env.TMUX ~= nil,
		is_termux = false,
		is_proot = false,
		is_ubuntu = false,
		is_wsl = false,
		is_windows = vim.fn.has("win32") == 1,
		is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1,
		is_linux = vim.fn.has("unix") == 1 and vim.fn.has("mac") == 0 and vim.fn.has("macunix") == 0,
		is_mobile = false,
		label = "",
	}

	-- Check Termux (Android native or path)
	if
		vim.env.TERMUX_VERSION
		or (vim.env.PREFIX and vim.env.PREFIX:match("com.termux"))
		or (vim.uv or vim.loop).fs_stat("/data/data/com.termux")
	then
		env.is_termux = true
		env.is_mobile = true
	end

	-- Check Ubuntu / PRoot container inside Termux or Linux
	local os_release = ""
	local f_os = io.open("/etc/os-release", "r")
	if f_os then
		os_release = f_os:read("*a") or ""
		f_os:close()
	end

	if os_release:lower():match("ubuntu") then
		env.is_ubuntu = true
	end

	if env.is_termux or (vim.uv or vim.loop).fs_stat("/data/data/com.termux") then
		if os_release ~= "" then
			env.is_proot = true
		end
	end

	-- Check WSL
	if vim.fn.has("wsl") == 1 then
		env.is_wsl = true
	else
		local f_ver = io.open("/proc/version", "r")
		if f_ver then
			local ver = f_ver:read("*a") or ""
			f_ver:close()
			if ver:lower():match("microsoft") or ver:lower():match("wsl") then
				env.is_wsl = true
			end
		end
	end

	-- Check mobile terminal dimensions (only if not on a clear desktop OS or GUI)
	local cols = vim.o.columns or 80
	if cols < 72 and not (env.is_windows or env.is_mac or env.is_wsl or vim.g.neovide) then
		env.is_mobile = true
	end

	-- Build hierarchical environment label (e.g. "TMUX > Ubuntu PRoot (Android)")
	local layers = {}
	if env.is_tmux then
		table.insert(layers, "TMUX")
	end

	if env.is_proot and env.is_ubuntu then
		table.insert(layers, "Ubuntu PRoot (Android)")
	elseif env.is_proot then
		table.insert(layers, "Linux PRoot (Android)")
	elseif env.is_termux then
		table.insert(layers, "Termux Native (Android)")
	elseif env.is_wsl then
		table.insert(layers, "WSL Linux")
	elseif env.is_ubuntu then
		table.insert(layers, "Ubuntu Linux")
	elseif env.is_windows then
		table.insert(layers, "Windows")
	elseif env.is_mac then
		table.insert(layers, "macOS")
	else
		table.insert(layers, "Linux")
	end

	env.label = table.concat(layers, " > ")
	return env
end

return M
