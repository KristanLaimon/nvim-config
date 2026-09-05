-- ============================================================================
-- KRS PROTOBUF: Centralized Protocol Buffers Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard 2-space indentation defaults for Protobuf (.proto) buffers when no
--   .editorconfig file specifies buffer settings. Also owns the buf_ls and protols
--   LSP servers, and the protolint formatter/linter.
-- ============================================================================

---@type KrsLangModule
local M = {}

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "buf_ls", "protols" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	buf_ls = {
		filetypes = { "proto" },
		single_file_support = true,
	},
	protols = {
		filetypes = { "proto" },
		single_file_support = true,
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	buf_ls = { mason = "buf", lang = "Protobuf (buf)", type = "lsp", cmd = "buf" },
	protols = { mason = "protols", lang = "Protobuf (protols)", type = "lsp", cmd = "protols" },
	protolint = { mason = "protolint", name = "protolint", type = "formatter", cmd = "protolint" },
}

--- Mason packages to auto-install for Protobuf files.
M.mason_order = { "buf_ls", "protols", "protolint" }

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "📜 Protocol Buffers"
M.requires = {} -- buf, protols & protolint are standalone Mason binaries
M.treesitter = { "proto" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	proto = { "protolint" },
}

--- Standard defaults for Protobuf (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply Protobuf language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Protobuf language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "proto" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
