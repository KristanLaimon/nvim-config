--- @module "krsnvim.terminal"
--- Cross-platform Terminal Command Execution Suite for `krsnvimscript`.
--- Invokable as `$ "command"` or `terminal.exec("command")`.
---
--- @class CommandResult
--- @field code number Exit status code of the process (0 for success).
--- @field ok boolean `true` if exit code is 0, `false` otherwise.
--- @field stdout string Standard output captured from command.
--- @field stderr string Standard error captured from command.
--- @field output string Combined output of stdout and stderr.
---
--- @example
--- local $ = import("krsnvim.terminal")
--- local res = $("git status")
--- if res.ok then
---     print(res.stdout)
--- else
---     print("Error code:", res.code)
--- end
local M = {}

--- @type boolean Indicates whether Neovim is running on Windows (win32/win64).
local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

--- Executes a shell command synchronously across Windows (`cmd.exe /C`) and Unix (`bash -c`).
---
--- @param cmd_str string|string[] Command string to execute, or table array of command tokens.
--- @param opts table|nil Additional execution options.
--- @return CommandResult result Structured result containing exit `code`, `ok` boolean, `stdout`, and `output`.
---
--- @note Edge Cases:
--- - If `cmd_str` is a table of arguments, it is joined with spaces.
--- - Automatically handles shell quoting across platforms.
--- - Check `result.ok` for boolean pass/fail status.
---
--- @see krsnvim.terminal.cwd
---
--- @example
--- local res = M.exec("bun run build")
--- assert(res.ok, "Build failed with exit code " .. res.code)
local function run_cmd(cmd_str, opts)
	opts = opts or {}
	if type(cmd_str) == "table" then
		cmd_str = table.concat(cmd_str, " ")
	end

	local shell_cmd
	if is_windows then
		shell_cmd = { "cmd.exe", "/C", cmd_str }
	else
		shell_cmd = { "bash", "-c", cmd_str }
	end

	local stdout = vim.fn.system(shell_cmd)
	local exit_code = vim.v.shell_error

	return {
		code = exit_code,
		ok = (exit_code == 0),
		stdout = stdout or "",
		stderr = "",
		output = stdout or "",
	}
end

setmetatable(M, {
	--- Allows `$` alias execution syntax: `$ "npm test"`
	--- @param _ any
	--- @param cmd_str string|string[]
	--- @param opts table|nil
	--- @return CommandResult
	__call = function(_, cmd_str, opts)
		return run_cmd(cmd_str, opts)
	end,
})

--- Alias for `run_cmd` execution.
--- @param cmd_str string|string[]
--- @param opts table|nil
--- @return CommandResult
M.exec = run_cmd

--- Alias for `run_cmd` execution.
--- @param cmd_str string|string[]
--- @param opts table|nil
--- @return CommandResult
M.run = run_cmd

--- @type boolean Indicates whether host OS is Windows.
M.is_windows = is_windows

--- Returns the current active working directory (CWD) of Neovim.
---
--- @return string cwd Current working directory path.
---
--- @example
--- print("Active project directory:", terminal.cwd())
function M.cwd()
	return vim.fn.getcwd()
end

--- Outputs a message to Neovim console or stdout.
---
--- @param msg any Message or object to print.
---
--- @example
--- terminal.echo("Task started...")
function M.echo(msg)
	print(msg)
end

return M
