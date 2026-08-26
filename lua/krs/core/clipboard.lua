local M = {}

--- Configures a fallback clipboard provider (OSC 52 + Termux API) for environments
--- where X11/Wayland display servers are missing or broken (Termux, Ubuntu PRoot, SSH, headless).
function M.setup()
	if vim.g.clipboard ~= nil then
		return
	end

	local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
	if is_win then
		-- On Windows, Neovim uses native win32yank / powershell / Win32 API clipboard providers.
		-- Do NOT override with OSC 52, which hangs waiting for terminal responses.
		return
	end

	local env_ok, env_mod = pcall(require, "krs.core.environment")
	local env = env_ok and env_mod.detect() or {}
	local is_termux_or_proot = env.is_termux or env.is_proot or env.is_mobile
	local is_ssh = vim.env.SSH_CLIENT ~= nil or vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

	if is_termux_or_proot or is_ssh then
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
					if has_termux_get then
						local out = vim.fn.systemlist({ termux_get })
						if vim.v.shell_error == 0 and #out > 0 then
							return out, vim.fn.getregtype("+")
						end
					end
					if osc52_ok then
						local osc_val = osc52.paste("+")()
						if type(osc_val) == "table" and #osc_val > 0 and osc_val[1] ~= "" then
							return osc_val
						end
					end
					return {}, "v"
				end,
				["*"] = function()
					if has_termux_get then
						local out = vim.fn.systemlist({ termux_get })
						if vim.v.shell_error == 0 and #out > 0 then
							return out, vim.fn.getregtype("*")
						end
					end
					if osc52_ok then
						local osc_val = osc52.paste("*")()
						if type(osc_val) == "table" and #osc_val > 0 and osc_val[1] ~= "" then
							return osc_val
						end
					end
					return {}, "v"
				end,
			},
		}
	end
end

return M
