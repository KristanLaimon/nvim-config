-- ============================================================================
-- PLUGIN: mermaid.nvim
-- ============================================================================

return {
	{
		"kevalin/mermaid.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		ft = { "mermaid", "markdown" },
		config = function()
			require("mermaid").setup({
				format = {
					shift_width = 4,
				},
				lint = {
					enabled = true,
					command = "mmdc",
				},
				preview = {
					renderer = "mermaid.js",
					theme = "default",
				},
			})

			-- Register global user commands for quick access if needed, but
			-- mermaid.nvim provides MermaidPreview, MermaidPreviewStop, MermaidFormat, MermaidRender.
		end,
	},
}
