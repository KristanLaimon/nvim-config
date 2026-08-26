-- ============================================================================
-- PLUGINS: LSP Symbol Usage (Reference Counter for Go & all LSP servers)
-- ============================================================================
-- WHAT IT DOES
--   Displays reference counts (e.g. "󰌹 3 references") above functions, methods,
--   classes, interfaces, and structs across all LSP servers, including gopls.
--   Integrates with `:KrsUsagesTheme` for Bubbles (default), Plain, & Labels.
-- ============================================================================

return {
	"Wansmer/symbol-usage.nvim",
	event = "LspAttach",
	config = function(_, opts)
		local ok, picker = pcall(require, "plugins.krs.tools.usages_picker")
		opts = opts or {}
		opts.kinds = {
			vim.lsp.protocol.SymbolKind.Function,
			vim.lsp.protocol.SymbolKind.Method,
			vim.lsp.protocol.SymbolKind.Class,
			vim.lsp.protocol.SymbolKind.Interface,
			vim.lsp.protocol.SymbolKind.Struct,
		}
		opts.vt_position = "above"
		if ok and picker.get_text_format then
			opts.text_format = picker.get_text_format()
		end

		require("symbol-usage").setup(opts)
	end,
}
