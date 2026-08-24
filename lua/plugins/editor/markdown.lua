-- ============================================================================
-- PLUGIN: render-markdown -- readable markdown inside the editor.
-- ============================================================================
-- Renders headings, code blocks, tables, checkboxes and callouts in place, so
-- docs/*.md and the in-editor wiki read like a document rather than raw text.
-- Loads only for markdown buffers.
-- ============================================================================

return {
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = { "markdown" },
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-tree/nvim-web-devicons",
		},
		opts = {
			heading = {
				enabled = true,
				sign = true,
				icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
				width = "block",
				left_pad = 1,
				right_pad = 1,
				min_width = 0,
				border = false,
				backgrounds = {},
			},
			code = {
				enabled = true,
				sign = false,
				style = "full",
			},
			bullet = {
				enabled = true,
			},
			checkbox = {
				enabled = true,
			},
			quote = {
				enabled = true,
			},
			pipe_table = {
				enabled = true,
				preset = "round",
				style = "full",
				cell = "padded",
				padding = 1,
				min_width = 0,
				alignment_indicator = "━",
			},
			callout = {
				note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
				tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
				important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint" },
				warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
				caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
			},
		},
		config = function(_, opts)
			require("render-markdown").setup(opts)

			-- Define bright, vibrant heading foreground highlights (Green, Orange, Yellow, Cyan, Purple, Pink)
			local set_hl = vim.api.nvim_set_hl
			set_hl(0, "RenderMarkdownH1", { fg = "#50fa7b", bold = true }) -- Bright Green
			set_hl(0, "RenderMarkdownH2", { fg = "#ff9e64", bold = true }) -- Bright Orange
			set_hl(0, "RenderMarkdownH3", { fg = "#f1fa8c", bold = true }) -- Bright Yellow
			set_hl(0, "RenderMarkdownH4", { fg = "#8be9fd", bold = true }) -- Bright Cyan
			set_hl(0, "RenderMarkdownH5", { fg = "#bd93f9", bold = true }) -- Bright Purple
			set_hl(0, "RenderMarkdownH6", { fg = "#ff79c6", bold = true }) -- Bright Pink

			-- Register global user commands for quick access
			vim.api.nvim_create_user_command("MarkdownToggleRender", "RenderMarkdown toggle", {
				desc = "Toggle in-editor rendered markdown display",
			})

			-- Autocmd for markdown buffer options and keymaps
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "markdown",
				callback = function(ev)
					-- Conceallevel 2 is REQUIRED for render-markdown to conceal #, **, links, etc.
					vim.opt_local.conceallevel = 2
					vim.opt_local.concealcursor = "nc"

					vim.keymap.set("n", "<C-S-v>", "<Cmd>RenderMarkdown toggle<CR>", {
						buffer = ev.buf,
						noremap = true,
						silent = true,
						desc = "Toggle In-Editor Rendered Markdown",
					})
					vim.keymap.set("n", "<C-S-V>", "<Cmd>RenderMarkdown toggle<CR>", {
						buffer = ev.buf,
						noremap = true,
						silent = true,
						desc = "Toggle In-Editor Rendered Markdown",
					})
					vim.keymap.set("n", "<leader>mp", "<Cmd>MarkdownPreviewToggle<CR>", {
						buffer = ev.buf,
						noremap = true,
						silent = true,
						desc = "Toggle Live Markdown Browser Preview",
					})
					vim.keymap.set("n", "<C-A-m>", "<Cmd>MarkdownPreviewToggle<CR>", {
						buffer = ev.buf,
						noremap = true,
						silent = true,
						desc = "Toggle Live Markdown Browser Preview",
					})
				end,
			})
		end,
	},
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = "cd app && npm install",
	},
}
