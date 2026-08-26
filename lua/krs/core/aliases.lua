local M = {}

M.aliases = {
	{ name = "cc", target = "gcc", env_var = "CC" },
}

function M.setup()
	local is_windows = vim.fn.has("win32") == 1
	local alias_dir = vim.fn.stdpath("config") .. (is_windows and "\\aliases" or "/aliases")

	-- Ensure directory exists
	vim.fn.mkdir(alias_dir, "p")

	-- Generate shim scripts
	for _, alias in ipairs(M.aliases) do
		-- Bash script (Works in WSL/Linux/macOS and Git Bash on Windows)
		local bash_path = alias_dir .. "/" .. alias.name
		if vim.fn.filereadable(bash_path) == 0 then
			vim.fn.writefile({ "#!/bin/bash", alias.target .. ' "$@"' }, bash_path)
			if not is_windows and vim.uv and vim.uv.fs_chmod then
				vim.uv.fs_chmod(bash_path, 493) -- 0755
			end
		end

		-- Batch script (Windows cmd.exe/PowerShell)
		if is_windows then
			local bat_path = alias_dir .. "\\" .. alias.name .. ".bat"
			if vim.fn.filereadable(bat_path) == 0 then
				vim.fn.writefile({ "@echo off", alias.target .. " %*" }, bat_path)
			end
		end

		-- Set Environment Variable if defined and not already set
		if alias.env_var and not vim.env[alias.env_var] then
			vim.env[alias.env_var] = alias.target
		end
	end

	-- Inject into PATH
	local current_path = vim.env.PATH or ""
	local separator = is_windows and ";" or ":"
	if not current_path:find(alias_dir, 1, true) then
		vim.env.PATH = alias_dir .. separator .. current_path
	end
end

return M
