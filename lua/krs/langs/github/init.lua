-- ============================================================================
-- KRS GITHUB: Centralized GitHub Actions Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Configures gh-actions-language-server and actionlint linter for GitHub Actions
--   workflows and actions.
-- ============================================================================

---@type KrsLangModule
local M = {}

M.lsp_server = { "gh_actions_ls" }

---@type table<string, vim.lsp.Config>
M.lsp_config = {
	gh_actions_ls = {
		filetypes = { "yaml.github" },
	},
}

M.mason = {
	gh_actions_ls = {
		mason = "gh-actions-language-server",
		lang = "GitHub Actions",
		type = "lsp",
		cmd = "gh-actions-language-server",
	},
	actionlint = { mason = "actionlint", name = "actionlint", type = "formatter", cmd = "actionlint" },
}

M.mason_order = { "gh_actions_ls", "actionlint" }

M.bundle_name = "🐙 GitHub Actions"
M.requires = {
	{ cmd = "node", name = "Node.js runtime", hint = "https://nodejs.org" },
}
M.treesitter = { "yaml" }

M.formatters_by_ft = {
	["yaml.github"] = { "actionlint" },
}

M.conform_formatters = {
	actionlint = {
		condition = function()
			return vim.fn.executable("actionlint") == 1
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
	vim.filetype.add({
		pattern = {
			[".*/%.github/workflows/.*%.ya?ml"] = "yaml.github",
			[".*/%.github/actions/.*%.ya?ml"] = "yaml.github",
		},
	})
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "yaml.github",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
