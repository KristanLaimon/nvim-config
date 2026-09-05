-- ============================================================================
-- KRS HASKELL: Centralized Haskell Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Configures haskell-language-server (hls), fourmolu formatter, hlint static
--   checker, and launch profile runtimes for Haskell.
-- ============================================================================

---@type KrsLangModule
local M = {}

M.lsp_server = { "hls" }

---@type table<string, vim.lsp.Config>
M.lsp_config = {
	hls = {
		filetypes = { "haskell", "lhaskell" },
		settings = {
			haskell = {
				formattingProvider = "fourmolu",
			},
		},
	},
}

M.mason = {
	hls = { mason = "haskell-language-server", lang = "Haskell", type = "lsp", cmd = "haskell-language-server-wrapper" },
	fourmolu = { mason = "fourmolu", name = "fourmolu", type = "formatter", cmd = "fourmolu" },
	hlint = { mason = "hlint", name = "hlint", type = "formatter", cmd = "hlint" },
}

M.mason_order = { "hls", "fourmolu", "hlint" }

M.bundle_name = "🔮 Haskell (haskell-language-server, fourmolu, hlint)"
M.requires = {
	{ cmd = "ghc", name = "GHC Compiler", hint = "https://www.haskell.org/ghcup/" },
	{ cmd = "cabal", name = "Cabal / Stack build tool", alt = "stack", hint = "https://www.haskell.org/ghcup/" },
}
M.treesitter = { "haskell" }

M.formatters_by_ft = {
	haskell = { "fourmolu" },
}

M.conform_formatters = {
	fourmolu = {
		condition = function()
			return vim.fn.executable("fourmolu") == 1
		end,
	},
	hlint = {
		condition = function()
			return vim.fn.executable("hlint") == 1
		end,
	},
}

M.launch_runtimes = {
	haskell = {
		command = "runghc",
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
		pattern = { "haskell", "lhaskell" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
