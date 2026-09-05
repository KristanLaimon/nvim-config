-- ============================================================================
-- KRS ZIG: Centralized Zig Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Configures zls (Zig Language Server), zigfmt formatter, and launch profile
--   runtimes for Zig.
-- ============================================================================

---@class ZigLangModule : KrsLangModule
local M = {}

M.lsp_server = { "zls" }

---@type table<string, vim.lsp.Config>
M.lsp_config = {
	zls = {
		filetypes = { "zig", "zir" },
		settings = {
			zls = {
				enable_autofix = true,
				enable_inlay_hints = true,
			},
		},
	},
}

M.mason = {
	zls = { mason = "zls", lang = "Zig", type = "lsp", cmd = "zls" },
}

M.mason_order = { "zls" }

M.bundle_name = "⚡ Zig"
M.requires = {
	{ cmd = "zig", name = "Zig compiler & toolchain", hint = "https://ziglang.org/download/" },
}
M.treesitter = { "zig" }

M.formatters_by_ft = {
	zig = { "zigfmt" },
}

M.conform_formatters = {
	zigfmt = {
		condition = function()
			return vim.fn.executable("zig") == 1
		end,
	},
}

M.launch_runtimes = {
	zig = {
		command = "zig run",
	},
}

M.defaults = {
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 4,
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
		pattern = { "zig", "zir" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
