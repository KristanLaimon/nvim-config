-- ============================================================================
-- KRS RUST: Rust Language Configuration
-- ============================================================================

---@type KrsLangModule
local M = {}

M.lsp_server = { "rust_analyzer" }
M.lsp_config = {
	rust_analyzer = {},
}

M.mason = {
	rust_analyzer = {
		mason = "rust-analyzer",
		lang = "Rust Analyzer",
		type = "lsp",
		cmd = "rust-analyzer",
	},
}

M.mason_order = { "rust_analyzer" }
M.bundle_name = "🦀 Rust"
M.requires = {
	{ cmd = "rustc", name = "Rust compiler (rustc)", hint = "https://rustup.rs" },
	{ cmd = "cargo", name = "Cargo", hint = "https://rustup.rs" },
	{ cmd = "rustfmt", name = "Rust formatter (rustfmt)", hint = "rustup component add rustfmt" },
}
M.treesitter = { "rust" }

M.formatters_by_ft = {
	rust = { "rustfmt" },
}
M.conform_formatters = {
	rustfmt = {
		condition = function()
			return vim.fn.executable("rustfmt") == 1
		end,
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
		pattern = "rust",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
