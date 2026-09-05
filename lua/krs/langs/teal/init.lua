-- ============================================================================
-- KRS TEAL & LUA EXTRAS: Centralized Lua Static Analysis & Teal Configuration
-- ============================================================================
-- WHAT IT DOES
--   Provides optional static analysis tools for Lua (luacheck, selene) and language
--   server support for Teal (teal-language-server). Note: core Lua editing remains
--   minimal & essential in lua/init.lua; this optional bundle offers extra static
--   analysis and Teal toolchain support.
-- ============================================================================

---@type KrsLangModule
local M = {}

M.lsp_server = { "teal_ls" }

---@type table<string, vim.lsp.Config>
M.lsp_config = {
	teal_ls = {
		filetypes = { "teal" },
	},
}

M.mason = {
	teal_ls = { mason = "teal-language-server", lang = "Teal", type = "lsp", cmd = "teal-language-server" },
	luacheck = { mason = "luacheck", name = "luacheck", type = "formatter", cmd = "luacheck" },
	selene = { mason = "selene", name = "selene", type = "formatter", cmd = "selene" },
}

M.mason_order = { "teal_ls", "luacheck", "selene" }

M.bundle_name = "🩵 Lua Extras & Teal"
M.requires = {}
M.treesitter = { "teal" }

M.formatters_by_ft = {
	teal = { "stylua" },
}

M.conform_formatters = {
	luacheck = {
		condition = function()
			return vim.fn.executable("luacheck") == 1
		end,
	},
	selene = {
		condition = function()
			return vim.fn.executable("selene") == 1
		end,
	},
}

M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "teal",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
