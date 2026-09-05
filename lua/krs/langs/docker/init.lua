-- ============================================================================
-- KRS DOCKER: Centralized Dockerfile Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard 2-space indentation defaults for Dockerfile buffers when no
--   .editorconfig file specifies buffer settings. Also owns the dockerls LSP server
--   and dockerfmt formatter.
-- ============================================================================

---@type KrsLangModule
local M = {}

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "dockerls" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	dockerls = {},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	dockerls = { mason = "dockerfile-language-server", lang = "Docker", type = "lsp", cmd = "docker-langserver" },
}

--- Mason packages to auto-install for Docker files.
M.mason_order = { "dockerls" }

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "🐳 Docker"
M.requires = {} -- dockerfile-language-server is a standalone Mason binary
M.treesitter = { "dockerfile" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	dockerfile = { "dockerfmt" },
}

--- Standard defaults for Dockerfile (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply Docker language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Dockerfile language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "dockerfile" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
