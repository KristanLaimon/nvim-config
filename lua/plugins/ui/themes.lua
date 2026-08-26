-- ============================================================================
-- PLUGINS: Theme and statusline.
-- ============================================================================
-- doki-theme-vim ships the upstream palettes; the active colorscheme is the local
-- `nagatoro-krs` in colors/, which is where every highlight is actually defined.
--
-- lualine renders the single global statusline (`laststatus = 3`): branch, diff
-- and diagnostics on the left, file name next, mode and position on the right.
-- ============================================================================

return {
	{
		"doki-theme/doki-theme-vim",
		-- Eager: a lazily loaded theme means a flash of the default colours.
		lazy = false,
		config = function()
			pcall(vim.cmd.colorscheme, "nagatoro-krs")
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		opts = function()
			local has_picker, picker = pcall(require, "plugins.krs.ui.statusline_picker")
			if has_picker then
				return picker.get_lualine_config()
			end
			return {
				options = { theme = "auto", globalstatus = true },
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = { "filename" },
					lualine_x = { "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
			}
		end,
	},
}
