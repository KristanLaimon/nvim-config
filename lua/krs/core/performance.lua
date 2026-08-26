local M = {}

function M.setup()
	local env_ok_opt, env_mod_opt = pcall(require, "krs.core.environment")
	if not env_ok_opt then
		return
	end

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

return M
